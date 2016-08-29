node.default['apt']['confd']['install_recommends'] = false
include_recipe 'apt'

package 'openjdk-7-jre-headless'

directory '/var/lib/jenkins' do
  recursive true
end

mount '/var/lib/jenkins' do
  device '/dev/disk/by-id/google-cookbooks-jenkins'
  only_if { File.exists? '/dev/disk/by-id/google-cookbooks-jenkins' }
end

node.default['jenkins']['master'].tap do |master|
  master['install_method'] = 'package'
  master['version'] = '2.7.2'
  master['jvm_options'] = '-Djenkins.install.runSetupWizard=false'
  master['listen_address'] = '127.0.0.1'
end
include_recipe 'jenkins::master'

repo = resources('apt_repository[jenkins]')
repo.uri 'http://pkg.jenkins-ci.org/debian-stable'

ruby_block 'load jenkins credential' do
  block do
    require 'openssl'
    require 'net/ssh'

    key = ::OpenSSL::PKey::RSA.new ::File.read Chef::Config[:client_key]

    node.run_state[:jenkins_private_key] = key.to_pem

    jenkins = resources('jenkins_user[chef]')
    jenkins.public_keys ["#{key.ssh_type} #{[key.to_blob].pack('m0')}"]
  end
end

jenkins_user 'chef' do
  provider CookbookJenkins::User
  id "chef@#{Chef::Config[:node_name]}"
  full_name "Chef"
end


jenkins_script 'get list of latest plugins' do
  command <<-eos.gsub(/^\s+/, '')
    pm = jenkins.model.Jenkins.instance.pluginManager
    pm.doCheckUpdatesServer()
  eos

  not_if do
    update_frequency = 86_400 # daily
    update_file = '/var/lib/jenkins/updates/default.json'
    ::File.exists?(update_file) &&
      ::File.mtime(update_file) > Time.now - update_frequency
  end
end

jenkins_script 'update plugins' do
  command <<-eos.gsub(/^\s+/, '')
    import jenkins.model.Jenkins;

    pm = Jenkins.instance.pluginManager

    uc = Jenkins.instance.updateCenter
    updated = false
    pm.plugins.each { plugin ->
      if (uc.getPlugin(plugin.shortName).version != plugin.version) {
        update = uc.getPlugin(plugin.shortName).deploy(true)
        update.get()
        updated = true
      }
    }
    if (updated) {
      Jenkins.instance.restart()
    }
  eos
end

jenkins_script 'setup plugins' do
  command <<-eos.gsub(/^\s+/, '')
    import jenkins.model.Jenkins;

    pm = Jenkins.instance.pluginManager

    uc = Jenkins.instance.updateCenter
    pm.plugins.each { plugin ->
      plugin.disable()
    }

    deployed = false
    def activatePlugin(plugin) {
      if (! plugin.isEnabled()) {
        plugin.enable()
        deployed = true
      }

      plugin.getDependencies().each {
        activatePlugin(pm.getPlugin(it.shortName))
      }
    }

    ["git", "workflow-aggregator", "github-oauth", "job-dsl", "extended-read-permission"].each {
      if (! pm.getPlugin(it)) {
        deployment = uc.getPlugin(it).deploy(true)
        deployment.get()
      }
      activatePlugin(pm.getPlugin(it))
    }

    if (deployed) {
      Jenkins.instance.restart()
    }
  eos
end

jenkins_script 'secure jenkins' do
  command <<-eos.gsub(/^\s+/, '')
    import jenkins.model.Jenkins;
    import org.jenkinsci.plugins.GithubSecurityRealm;
    import hudson.security.HudsonPrivateSecurityRealm;

    // Jenkins.instance.securityRealm = new GithubSecurityRealm(
    //    'https://github.com', 'https://api.github.com', 'x', 'y')
    Jenkins.instance.securityRealm = new HudsonPrivateSecurityRealm(false, false, null);

    permissions = new hudson.security.GlobalMatrixAuthorizationStrategy()

    permissions.add(Jenkins.ADMINISTER, 'aespinosa')
    permissions.add(Jenkins.ADMINISTER, '#{resources('jenkins_user[chef]').id}')
    permissions.add(hudson.model.View.READ, 'anonymous')
    permissions.add(hudson.model.Item.READ, 'anonymous')
    permissions.add(Jenkins.READ, 'anonymous')

    Jenkins.instance.authorizationStrategy = permissions

    Jenkins.instance.save()
  eos
end

jenkins_script 'install Seed Job' do
  command <<-eos.gsub(/^\s+/, '')
    import jenkins.model.Jenkins;
    import hudson.model.FreeStyleProject;

    job = Jenkins.instance.createProject(FreeStyleProject, 'seed')
    job.displayName = 'Seed Job'

    builder = new javaposse.jobdsl.plugin.ExecuteDslScripts(
      new javaposse.jobdsl.plugin.ExecuteDslScripts.ScriptLocation(
          'false',
          'seed.groovy',
          null),
      false,
      javaposse.jobdsl.plugin.RemovedJobAction.DELETE, 
      javaposse.jobdsl.plugin.RemovedViewAction.DELETE, 
      javaposse.jobdsl.plugin.LookupStrategy.JENKINS_ROOT, 
    )
    job.buildersList.add(builder)

    job.save()
  eos
  not_if { ::File.exists? '/var/lib/jenkins/jobs/seed/config.xml' }
end

directory '/var/lib/jenkins/jobs/seed/workspace' do
  owner 'jenkins'
end

# TODO: create the seed job
cookbook_file '/var/lib/jenkins/jobs/seed/workspace/seed.groovy' do
  action :nothing
  source 'seed.groovy'
  notifies :execute, 'jenkins_script[build seed job]'
end

jenkins_script 'build seed job' do
  command <<-eos.gsub(/^\s+/, '')
    import jenkins.model.Jenkins;
    job = Jenkins.instance.getItem('seed')
    job.scheduleBuild(new hudson.model.Cause.UserIdCause())
  eos
  action :nothing
end

package 'git-core'

ruby_block 'register dns' do
  block do
    require 'gcloud'
    zone = Gcloud.new.dns.zone 'top'

    if zone.records('cookbooks.espinosa.io') == []
      zone.add 'cookbooks.espinosa.io', 'A', 86400, [node['cloud_v2']['public_ipv4']]
    else
      zone.replace 'cookbooks.espinosa.io', 'A', 86400, [node['cloud_v2']['public_ipv4']]
    end
  end

  not_if do
    require 'gcloud'
    zone = Gcloud.new.dns.zone 'top'
    jenkins_record = zone.records('cookbooks.espinosa.io').first
    jenkins_record && jenkins_record.data == [node['cloud_v2']['public_ipv4']]
  end
end


# ACME client

directory '/etc/acme' do
  recursive true
end

ruby_block 'generate acme client key' do
  block do
    require 'openssl'
    key = resources('file[/etc/acme/client.pem]')

    key.content OpenSSL::PKey::RSA.new(4096).to_s
  end
  not_if { File.exists? '/etc/acme/client.pem' }
end

file '/etc/acme/client.pem' do
  owner 'root'
  mode '0600'
  sensitive true
  action :create_if_missing
end

endpoint = 'https://acme-v01.api.letsencrypt.org/'

ruby_block 'load acme client key' do
  block do
    require 'openssl'
    require 'acme-client'
    key = OpenSSL::PKey::RSA.new File.read '/etc/acme/client.pem'
    node.run_state['acme'] = Acme::Client.new(private_key: key, endpoint: endpoint)
  end
end

ruby_block 'register and accept terms' do
  block do
    require 'fileutils'
    client = node.run_state['acme']
    reg = client.register contact: 'mailto:yecartes@gmail.com'
    reg.agree_terms

    FileUtils.touch '/etc/acme/.registered'
  end
  not_if { File.exists? '/etc/acme/.registered' }
end

ruby_block 'ask for a dns challenge' do
  block do
    require 'gcloud'
    require 'resolv'
    client = node.run_state['acme']
    # ask for challenge
    dns01 = client.authorize(domain: 'cookbooks.espinosa.io').dns01
    # provision challenge (GCP)
    dns = Gcloud.new.dns.zone 'top'
    dns.add '_acme-challenge.cookbooks.espinosa.io', dns01.record_type, 300, [dns01.record_content]
    # wait until dns is provisioned
    public_dns = Resolv::DNS.new
    while public_dns.getresources('_acme-challenge.cookbooks.espinosa.io', Resolv::DNS::Resource::IN::TXT).empty? do
      sleep 2.0
    end
    # verify challenge
    dns01.request_verification
    # Wait until it's valid
    while dns01.verify_status == 'pending' do
      sleep 1.0
    end
    # Delete entry clean up after itself
    dns.remove '_acme-challenge.cookbooks.espinosa.io', dns01.record_type
    # raise error if it's invalid
    raise 'Cannot verify DNS Challenge' if dns01.verify_status == 'invalid'
  end
  # FIXME: Wait until 0.5.0 or 1.0.0 of acme-client so we can use
  # fetch_authorization
  # only_if {
  # client.fetch_authorization File.read(authorization_uri_file) # or node
  # object
  #   dns01.expires - Time.now < 10 * 86400
  # }  # days
end

ruby_block 'create server key' do
  action :nothing
end

file '/etc/acme/cookbooks.espinosa.io.key' do
  content lazy {
    if File.exists? '/etc/acme/cookbooks.espinosa.io.key'
      File.read '/etc/acme/cookbooks.espinosa.io.key'
    else
      require 'acme-client'
      Acme::Client::CertificateRequest.new(names: %w(cookbooks.espinosa.io)).private_key.to_s
    end
  }
  mode '0600'
  sensitive true
end

file '/etc/acme/cookbooks.espinosa.io.crt' do
  content lazy {
    require 'acme-client'
    key = OpenSSL::PKey::RSA.new File.read '/etc/acme/cookbooks.espinosa.io.key'
    csr = Acme::Client::CertificateRequest.new(names: %w(cookbooks.espinosa.io), private_key: key)

    client = node.run_state['acme']

    cert = client.new_certificate csr

    cert.fullchain_to_pem
  }
  not_if {
    require 'openssl'
    cert_file = '/etc/acme/cookbooks.espinosa.io.crt'
    certificate_generated = File.exists? cert_file
    certificate_generated && (OpenSSL::X509::Certificate.new(File.read cert_file).not_after - Time.now > 10 * 86400)
  }
end

apt_repository 'nginx' do
  uri "http://nginx.org/packages/#{node['platform']}"
  distribution node['lsb']['codename']
  components %w(nginx)
  key 'http://nginx.org/keys/nginx_signing.key'
end

package 'nginx'

file '/etc/nginx/nginx.conf' do
  content <<-eos
events { }
http {
  access_log syslog:server=unix:/dev/log;
  error_log syslog:server=unix:/dev/log;

  server {
    listen 443 ssl;

    ssl_certificate /etc/acme/cookbooks.espinosa.io.crt;
    ssl_certificate_key /etc/acme/cookbooks.espinosa.io.key;

    location / {
      proxy_pass http://127.0.0.1:8080;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
  }

  server {
    listen 80;
    return 301 https://$host$request_uri;
  }
}
  eos
  notifies :reload, 'service[nginx]'
end

service 'nginx' do
  reload_command '/etc/init.d/nginx reload'
  action %w(enable start)
end
