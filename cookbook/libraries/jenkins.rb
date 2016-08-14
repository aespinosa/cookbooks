#
# Original from the community Jenkins cookbook.  Keep this until #496 is merged.
#
# Copyright 2013-2014, Chef Software, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'json'

module CookbookJenkins
  class User < Chef::Provider::JenkinsUser
    action(:create) do
      if current_resource.exists? &&
         current_resource.full_name == new_resource.full_name &&
         current_resource.email == new_resource.email &&
         current_resource.public_keys == new_resource.public_keys
        Chef::Log.info("#{new_resource} exists - skipping")
      else
        converge_by("Create #{new_resource}") do
          executor.groovy! <<-EOH.gsub(/ ^{12}/, '')
            user = hudson.model.User.get('#{new_resource.id}')
            user.setFullName('#{new_resource.full_name}')

            if (jenkins.model.Jenkins.instance.pluginManager.getPlugin('mailer')) {
              propertyClass = this.class.classLoader.loadClass('hudson.tasks.Mailer$UserProperty')
              email = propertyClass.newInstance('#{new_resource.email}')
              user.addProperty(email)
            }

            password = hudson.security.HudsonPrivateSecurityRealm.Details.fromPlainPassword('#{new_resource.password}')
            user.addProperty(password)

            keys = new org.jenkinsci.main.modules.cli.auth.ssh.UserPropertyImpl('#{new_resource.public_keys.join('\n')}')
            user.addProperty(keys)

            user.save()
          EOH
        end
      end
    end
  end
end

Chef::Platform.set(
  resource: :jenkins_user,
  provider: Chef::Provider::JenkinsUser
)
