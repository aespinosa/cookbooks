name 'jenkins'

default_source :supermarket

cookbook 'allan_jenkins', path: './'
run_list 'allan_jenkins'
