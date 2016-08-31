# Define the cache path.
fastcgi_cache_path /data/nginx/cache levels=1:2 keys_zone=trcom:100m max_size=1g inactive=1d;
fastcgi_temp_path /data/nginx/temp;
fastcgi_cache_key "$scheme$request_method$host$request_uri";

# Redirect www to non-www
server {
  listen 80;
  listen [::]:80;
  listen [::]:443;
  listen 443;
  server_name www.travisrunyard.com;

  # Include defaults for allowed SSL/TLS protocols and handshake caches.
  include /etc/nginx/h5bp/directive-only/ssl.conf;

  # config to enable HSTS(HTTP Strict Transport Security) https://developer.mozilla.org/en-US/docs/Security/HTTP_Strict_Transport_Security
  # to avoid ssl stripping https://en.wikipedia.org/wiki/SSL_stripping#SSL_stripping
  add_header Strict-Transport-Security "max-age=31536000; includeSubdomains;";

  ssl on;
  ssl_certificate_key /etc/ssl/letsencrypt/travisrunyard.com/privkey.pem;
  ssl_certificate /etc/ssl/letsencrypt/travisrunyard.com/fullchain.pem;

  return 301 https://travisrunyard.com$request_uri;
}

server {
  listen 80;
  listen 443;
  server_name travisrunyard.com *.travisrunyard.com;

  # Include defaults for allowed SSL/TLS protocols and handshake caches.
  include /etc/nginx/h5bp/directive-only/ssl.conf;

  # config to enable HSTS(HTTP Strict Transport Security) https://developer.mozilla.org/en-US/docs/Security/HTTP_Strict_Transport_Security
  # to avoid ssl stripping https://en.wikipedia.org/wiki/SSL_stripping#SSL_stripping
  add_header Strict-Transport-Security "max-age=31536000; includeSubdomains;";

  ssl on;
  ssl_certificate_key /etc/ssl/letsencrypt/travisrunyard.com/privkey.pem;
  ssl_certificate /etc/ssl/letsencrypt/travisrunyard.com/fullchain.pem;

  # Path for static files
  root /var/www/travisrunyard.com;

  # Path for log files

  access_log /var/log/nginx/travisrunyard.com.access.log;
  error_log /var/log/nginx/travisrunyard.com.error.log;

  #Specify a charset
  charset utf-8;

  # Include the basic h5bp config set
  include h5bp/basic.conf;

  location / {
    index index.php;
    try_files $uri $uri/ /index.php?$args;
  }

  location ~ \.php$ {
    fastcgi_cache  trcom;
    fastcgi_cache_valid 200 301 304 1d;
    fastcgi_cache_valid 302 1h;
    fastcgi_cache_use_stale updating;
    fastcgi_max_temp_file_size 100M;
    fastcgi_pass   127.0.0.1:9000;
    fastcgi_index  index.php;
    fastcgi_param  SCRIPT_FILENAME   $document_root$fastcgi_script_name;
    include        fastcgi_params;
}

# Rewrites for Yoast SEO XML Sitemap
rewrite ^/sitemap_index.xml$ /index.php?sitemap=1 last;
rewrite ^/([^/]+?)-sitemap([0-9]+)?.xml$ /index.php?sitemap=$1&sitemap_n=$2 last;

#TR Rewrite the base sitemap.xml generated by JetPack
rewrite ^/sitemap.xml$ /index.php?sitemap=1 last;

#TR Rewrite rule permalink change from year/mo/day/post to just /post
rewrite "/([0-9]{4})/([0-9]{2})/([0-9]{2})/(.*)" $scheme://$server_name/$4 permanent;


    # Local variables to track whether to serve a cached page or not.
    set $no_cache_set 0;
    set $no_cache_get 0;

    # If a request comes in with a X-Nginx-Cache-Purge: 1 header, do not grab from cache
    # But note that we will still store to cache
    # We use this to proactively update items in the cache!
    if ( $http_x_nginx_cache_purge ) {
      set $no_cache_get 1;
    }

    # If the user has a user logged-in cookie, circumvent the cache.
    if ( $http_cookie ~* "comment_author_|wordpress_(?!test_cookie)|wp-postpass_" ) {
      set $no_cache_set 1;
      set $no_cache_get 1;
    }

    # fastcgi_no_cache means "Do not store this proxy response in the cache"
    fastcgi_no_cache $no_cache_set;
    # fastcgi_cache_bypass means "Do not look in the cache for this request"
    fastcgi_cache_bypass $no_cache_get;
}
