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
  master['version'] = '2.46.3'
  master['jvm_options'] = '-Djenkins.install.runSetupWizard=false'
  master['listen_address'] = '127.0.0.1'
end
include_recipe 'jenkins::master'

repo = resources('apt_repository[jenkins]')
repo.uri 'http://pkg.jenkins.io/debian-stable'

jenkins_home = node.default['jenkins']['master']['home']

directory ::File.join(jenkins_home, 'init.groovy.d')

file ::File.join(jenkins_home, 'init.groovy.d', '01_update_plugins.groovy') do
  content <<-eos.gsub(/^\s+/, '')
    import jenkins.model.Jenkins;

    pm = Jenkins.instance.pluginManager
    uc = Jenkins.instance.updateCenter

    uc.updateAllSites()

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

file ::File.join(jenkins_home, 'init.groovy.d', '02_install_plugins.groovy') do
  content <<-eos.gsub(/^\s+/, '')
    import jenkins.model.Jenkins;

    pm = Jenkins.instance.pluginManager

    uc = Jenkins.instance.updateCenter

    installed = false

    ["git", "workflow-aggregator", "github-oauth", "job-dsl", "extended-read-permission", "matrix-auth"].each {
      if (! pm.getPlugin(it)) {
        deployment = uc.getPlugin(it).deploy(true)
        deployment.get()
        installed = true
      }
    }

    if (installed) {
      Jenkins.instance.restart()
    }
  eos
end

file ::File.join(jenkins_home, 'init.groovy.d', '03_secure_instance.groovy') do
  content <<-eos.gsub(/^\s+/, '')
    cli = jenkins.CLI.get()
    cli.enabled = false
    cli.save()

    import jenkins.model.Jenkins;
    Jenkins.instance.injector.getInstance(jenkins.security.s2m.AdminWhitelistRule.class).setMasterKillSwitch(false)

    import org.jenkinsci.plugins.GithubSecurityRealm;
    import hudson.security.HudsonPrivateSecurityRealm;

    // Jenkins.instance.securityRealm = new GithubSecurityRealm(
    //    'https://github.com', 'https://api.github.com', 'x', 'y')
    Jenkins.instance.securityRealm = new HudsonPrivateSecurityRealm(false, false, null);

    permissions = new hudson.security.GlobalMatrixAuthorizationStrategy()

    permissions.add(Jenkins.ADMINISTER, 'aespinosa')
    permissions.add(hudson.model.View.READ, 'anonymous')
    permissions.add(hudson.model.Item.READ, 'anonymous')
    permissions.add(Jenkins.READ, 'anonymous')

    Jenkins.instance.authorizationStrategy = permissions
    Jenkins.instance.save()
  eos
end

file ::File.join(jenkins_home, 'init.groovy.d', '04_setup_jobs.groovy') do
  content <<-eos.gsub(/^\s+/, '')
    import jenkins.model.Jenkins;
    import hudson.model.FreeStyleProject;

    if (! Jenkins.instance.getItem('seed') ) {
      job = Jenkins.instance.createProject(FreeStyleProject, 'seed')
      job.displayName = 'Seed Job'

      builder = new javaposse.jobdsl.plugin.ExecuteDslScripts()
      builder.usingScriptText = false
      builder.targets = 'seed.groovy'
      builder.removedJobAction = javaposse.jobdsl.plugin.RemovedJobAction.DELETE
      builder.removedViewAction = javaposse.jobdsl.plugin.RemovedViewAction.DELETE
      builder.lookupStrategy = javaposse.jobdsl.plugin.LookupStrategy.JENKINS_ROOT

      job.buildersList.add(builder)

      job.save()
    }
  eos
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

include_recipe 'allan_jenkins:_https'
