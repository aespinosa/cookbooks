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
