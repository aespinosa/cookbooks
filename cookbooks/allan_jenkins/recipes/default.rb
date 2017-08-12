package 'java-1.8.0-openjdk'

mount '/var/lib/jenkins' do
  device '/dev/disk/by-id/google-cookbooks-jenkins'
  only_if { File.exists? '/dev/disk/by-id/google-cookbooks-jenkins' }
end

node.default['jenkins']['master'].tap do |master|
  master['install_method'] = 'package'
  master['jvm_options'] = '-Djenkins.install.runSetupWizard=false'
  master['listen_address'] = '127.0.0.1'
end
include_recipe 'jenkins::master'

repo = resources('yum_repository[jenkins-ci]')
repo.baseurl 'http://pkg.jenkins.io/redhat-stable'

jenkins_home = node.default['jenkins']['master']['home']

remote_directory jenkins_home do
  owner node['jenkins']['master']['user']
  source 'jenkins_home'
end

include_recipe 'allan_jenkins::_https'
