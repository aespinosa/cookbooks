name 'allan_jenkins'

version '0.1.0'

issues_url nil
source_url 'https://github.com/aespinosa/cookbooks'

maintainer 'Allan Espinosa'
maintainer_email 'allan.espinosa@outlook.com'

depends 'jenkins', '~> 5.0'
depends 'yum-epel', '~> 2.1'

gem 'gcloud', '~> 0.12'
gem 'acme-client', '~> 0.4'
