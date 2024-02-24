#!/bin/sh

# Based on: https://xw.is/wiki/Installing_Mediawiki_1.27_on_FreeBSD_11.1

export ASSUME_ALWAYS_YES=YES
export PAGER=cat

# wiki name
WIKI=homewiki
# wiki admin name and password
ADMIN=Admin
PASSWORD=$(openssl rand -base64 8)
# server name or IP, used by nginx and the wiki
SERVER=10.10.0.62

# max file upload size, in Mb
UPLOAD_MAX=500;

# update, these change frequently
# https://www.mediawiki.org/wiki/Special:ExtensionDistributor?extdistname=MobileFrontend&extdistversion=REL1_40
# https://www.mediawiki.org/wiki/Special:ExtensionDistributor?extdistname=Cite&extdistversion=REL1_40
MOBILEFE="MobileFrontend-REL1_40-62be0e3.tar.gz"
CITES="Cite-REL1_40-723e08a.tar.gz"

# avoid errors about failing post-install scripts
pkg install -y indexinfo
[ -z $(echo $PATH | tr ':' '\n' | grep -x /usr/local/bin) ] && export PATH=$PATH:/usr/local/bin

# install packages
pkg install -y git ImageMagick7 mediawiki140-php83 nginx php83-pecl-APCu php83-gd php83-pdo_sqlite

# enable services
cat <<RCCONF >> /etc/rc.conf

# Enabled for Mediawiki:
# nginx_enable="YES"
# php_fpm_enable="YES"
RCCONF
sysrc nginx_enable="YES"
sysrc php_fpm_enable="YES"

# edit /usr/local/etc/php-fpm.d/www.conf
# ;listen = 127.0.0.1:9000
# listen = /var/run/php-fpm.sock
sed -i '' 's#^listen = 127.0.0.1:9000#listen = /var/run/php-fpm.sock#' /usr/local/etc/php-fpm.d/www.conf

# Theoretically commented values are defaults but leaving these commented doesn't work
# ;listen.owner = www
# ;listen.group = www
# ;listen.mode = 0660
sed -i '' -E '/^;listen.(owner|group|mode)/s/;//g' /usr/local/etc/php-fpm.d/www.conf

# edit /usr/local/etc/php.conf
# to include these extensions: apcu iconv intl xml
sed -i '' 's/^PHP_EXT_INC=/PHP_EXT_INC=apcu iconv intl xml /' /usr/local/etc/php.conf 

# Make this symlink, it's easier
mkdir -p /tank/www
ln -s /usr/local/www/mediawiki /tank/www/w

# This is for sqlite database
mkdir -p /usr/local/www/mediawiki/data
chown www:www /usr/local/www/mediawiki/data

# For uploads
chown www:www /usr/local/www/mediawiki/images

# Download and install extensions (Mobile frontend, Cites)
chmod g+w /usr/local/www/mediawiki/extensions
for i in "$MOBILEFE" "$CITES"; do
	fetch "https://extdist.wmflabs.org/dist/extensions/$i"
	tar -C /usr/local/www/mediawiki/extensions -xzf "$i"
done

# Generate LocalSettings.php
/usr/local/bin/php /usr/local/www/mediawiki/maintenance/run.php install.php \
  --confpath=/usr/local/www/mediawiki/ \
  --dbname=mediawiki_db \
  --dbpath=/usr/local/www/mediawiki/data \
  --dbtype=sqlite \
  --server="http://$SERVER" \
  --scriptpath="/w" \
  --lang=en \
  --pass="$PASSWORD" \
  "$WIKI" "$ADMIN"

# Fix file permission on databases
chown www:www /usr/local/www/mediawiki/data/*.sqlite
chown www:www /usr/local/www/mediawiki/data/locks

# Change timezone from UTC to US East
# shellcheck disable=SC2016
sed -i '' '/^$wgLocaltimezone = "UTC";/a \
date_default_timezone_set( $wgLocaltimezone ); \
' /usr/local/www/mediawiki/LocalSettings.php
sed -i '' 's#UTC#America/New_York#' /usr/local/www/mediawiki/LocalSettings.php

# Disable email
# shellcheck disable=SC2016
sed -i '' 's/^$wgEnableEmail = true;/$wgEnableEmail = false;/' /usr/local/www/mediawiki/LocalSettings.php

# Enable short URLs
# shellcheck disable=SC2016
sed -i '' '/^$wgScriptPath/a \
$wgScriptExtension = ".php"; \
$wgArticlePath = "\/wiki\/$1"; \
$wgUsePathInfo = true; \
' /usr/local/www/mediawiki/LocalSettings.php

# Enable uploads
sed -i '' 's/^$wgEnableUploads = false;/$wgEnableUploads = true;/' /usr/local/www/mediawiki/LocalSettings.php

# increase upload size in php.ini
echo "post_max_size = ${UPLOAD_MAX}M" > /usr/local/etc/php.ini
echo "upload_max_filesize = ${UPLOAD_MAX}M" >> /usr/local/etc/php.ini

# Addons to end of LocalSettings.php
# Increase upload size
# Allow other upload types
# Enable previously installed extensions
echo "\$wgMaxUploadSize = 1024 * 1024 * $UPLOAD_MAX;" >> /usr/local/www/mediawiki/LocalSettings.php
cat << 'EXTRA' >> /usr/local/www/mediawiki/LocalSettings.php
$wgFileExtensions = array_merge( $wgFileExtensions, [
	'doc', 'docx', 'jpg', 'mpp', 'odg', 'odp', 'ods',
	'odt', 'pdf', 'ppt', 'pptx', 'tiff', 'xls', 'xlsx'
] );
wfLoadExtension( 'MobileFrontend' );
$wgMFAutodetectMobileView = true;
wfLoadExtension( 'Cite' );
EXTRA

# Install nginx.conf
cat << 'NGINXCONF' > /usr/local/etc/nginx/nginx.conf
worker_processes  1;

events {
	worker_connections 1024;
}

http {
	include mime.types;
	default_type application/octet-stream;

	sendfile on;
	keepalive_timeout 65;

	server {
		listen 80;
		listen [::]:80;
		server_name CHANGEME;
		client_max_body_size UPLOAD_MAX;

		root /tank/www;
		index index.php;

		location / {
			rewrite ^/$ http://CHANGEME/wiki permanent;
		}

		location /w {
			location ~ \.php$ {
				try_files $uri =404;
				fastcgi_split_path_info ^(.+\.php)(/.+)$;
				fastcgi_pass unix:/var/run/php-fpm.sock;
				fastcgi_index index.php;
				fastcgi_param SCRIPT_FILENAME $request_filename;
				include fastcgi_params;
			}
		}

		location /w/images {
			location ~ ^/w/images/thumb/(archive/)?[0-9a-f]/[0-9a-f][0-9a-f]/([^/]+)/([0-9]+)px-.*$ {
				try_files $uri $uri/ @thumb;
			}
		}
		location /w/images/deleted {
			# Deny access to deleted images folder
			deny all;
		}

		location /w/cache       { deny all; }
		location /w/languages   { deny all; }
		location /w/maintenance { deny all; }
		location /w/serialized  { deny all; }
		location ~ /.(svn|git)(/|$) { deny all; }
		location ~ /.ht { deny all; }

		location /wiki {
			include fastcgi_params;
			fastcgi_param SCRIPT_FILENAME $document_root/w/index.php;
			fastcgi_pass unix:/var/run/php-fpm.sock;
		}

		location @thumb {
			rewrite ^/w/images/thumb/[0-9a-f]/[0-9a-f][0-9a-f]/([^/]+)/([0-9]+)px-.*$ /w/thumb.php?f=$1&width=$2;
			rewrite ^/w/images/thumb/archive/[0-9a-f]/[0-9a-f][0-9a-f]/([^/]+)/([0-9]+)px-.*$ /w/thumb.php?f=$1&width=$2&archived=1;
			include fastcgi_params;
			fastcgi_param SCRIPT_FILENAME $document_root/w/thumb.php;
			fastcgi_pass unix:/var/run/php-fpm.sock;
		}

		error_page 500 502 503 504 /50x.html;
		location = /50x.html {
			root /usr/local/www/nginx-dist;
		}
	}
}
NGINXCONF

# Update nginx.conf with server name
sed -i '' "s/CHANGEME/$SERVER/g" /usr/local/etc/nginx/nginx.conf
sed -i '' "s/UPLOAD_MAX/${UPLOAD_MAX}M/g" /usr/local/etc/nginx/nginx.conf

cat <<WIKISETUP >> /root/wiki-setup
Mediawiki setup completed on: $(date +%c).
The Admin user for the wiki is:
Username: $ADMIN
Password: $PASSWORD
WIKISETUP
