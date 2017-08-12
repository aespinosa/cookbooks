include_recipe 'yum-epel'

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


yum_repository 'nginx' do
  baseurl "http://nginx.org/packages/centos/7/x86_64"
  gpgkey 'http://nginx.org/keys/nginx_signing.key'
end

user 'certbot' do
  system true
end

%w(/var/lib/letsencrypt /etc/letsencrypt /var/log/letsencrypt).each do |d|
  directory d do
    owner 'certbot'
  end
end

package 'certbot'

package 'nginx'

file '/etc/nginx/https.conf' do
  content lazy {
    if ::File.exist? '/etc/letsencrypt/live/cookbooks.espinosa.io/fullchain.pem'
      <<-eos
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
    else
      ''
    end
  }
  notifies :reload, 'service[nginx]'
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
  action %w(enable start)
end
