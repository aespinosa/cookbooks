node.default['apt']['confd']['install_recommends'] = false

include_recipe 'apt'

resources('package[apt-transport-https]').action :remove
