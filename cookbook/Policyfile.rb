name 'jenkins'

default_source :supermarket

cookbook 'cookbooks_jenkins', path: './'
run_list 'cookbooks_jenkins'
