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


apt_repository 'nginx' do
  uri "http://nginx.org/packages/#{node['platform']}"
  distribution node['lsb']['codename']
  components %w(nginx)
  key 'http://nginx.org/keys/nginx_signing.key'
end

apt_repository 'jessie-backports' do
  uri 'http://http.debian.net/debian'
  distribution 'jessie-backports'
  components %w(main)
end

user 'certbot' do
  system true
end

directory '/var/lib/letsencrypt' do
  owner 'certbot'
end

directory '/etc/letsencrypt' do
  owner 'certbot'
end

directory '/var/log/letsencrypt' do
  owner 'certbot'
end

package 'certbot' do
  options '-t jessie-backports'
end

systemd_unit 'certbot.timer' do
  action :enable
end

package 'nginx'

ruby_block 'confirm letsencrypt' do
  block do
    unless ::File.exist? '/etc/letsencrypt/live/cookbooks.espinosa.io/fullchain.pem'
      resources('file[/etc/nginx/https.conf]').content ''
    end
  end
end

file '/etc/nginx/https.conf' do
  
  content <<-eos
server {
  listen 443 ssl;

  ssl_certificate /etc/letsencrypt/live/cookbooks.espinosa.io/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/cookbooks.espinosa.io/privkey.pem;

  location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  }
}
  eos
end

file '/etc/nginx/nginx.conf' do
  content <<-eos
events { }
http {
  access_log syslog:server=unix:/dev/log;
  error_log syslog:server=unix:/dev/log;

  include https.conf;

  server {
    listen 80;
    location / {
      return 301 https://$host$request_uri;
    }
    location /.well-known/acme-challenge {
      root /var/lib/letsencrypt;
    }
  }
}
  eos
  notifies :reload, 'service[nginx]'
end

service 'nginx' do
  reload_command '/etc/init.d/nginx reload'
  action %w(enable start)
end
