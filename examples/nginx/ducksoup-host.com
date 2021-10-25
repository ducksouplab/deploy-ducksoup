upstream experiment {
    server localhost:8080;
}

upstream ducksoup {
    server localhost:8100;
}

upstream grafana {
    server localhost:3000;
}

map $http_upgrade $connection_upgrade {
  default upgrade;
  '' close;
}

server {
    listen [::]:80;
    listen 80;

    server_name ducksoup-host.com;

    return 301 https://$host$request_uri;
}

server {
    listen [::]:443 ipv6only=on;
    listen 443;
    
    server_name ducksoup-host.com;

    location /grafana {
        proxy_pass http://grafana;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "Upgrade";
    }

    location /experiment {
        rewrite /experiment/(.*) /$1  break; # remove path prefix before otree
        proxy_pass "http://experiment";
        proxy_set_header Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Port $server_port;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Host $server_name;
    }

    location / {
        proxy_pass "http://ducksoup";
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Port $server_port;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Host $server_name;
        # increase 1 minute default timeout
        proxy_send_timeout 10m;
        proxy_read_timeout 10m;
    }
}