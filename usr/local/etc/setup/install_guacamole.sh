#!/bin/sh

# Modified from: https://github.com/leandroscardua/freebsd_scritps/blob/main/install_guacamole.sh

############# Installation Folder Location ##########################
# /usr/local/share/guacamole-client = jar for the database connector
# /usr/local/etc/guacamole-client = GUACAMOLE_HOME folder
# /usr/local/etc/guacamole-server = Guacamole configuration server
# /usr/local/apache-tomcat-9.0/logs = Log folder
# tree /etc/guacamole (symlink to GUACAMOLE_HOME)
#.
#├── extensions
#|   ├── guacamole-auth-jdbc-mysql-{{VERSION}}.jar
#|   └── guacamole-auth-totp-{{VERSION}}.jar	<optional>
#├── guacamole.properties
#├── guacamole.properties.sample
#├── lib
#|   └── mysql-connector-j.jar
#├── logback.xml
#├── logback.xml.sample
#└── user-mapping.xml.sample
#####################################################################

export ASSUME_ALWAYS_YES=YES
export PAGER=cat

#generate random password for root and guacamole db user
mysqlroot="$(openssl rand -base64 15)"
guacamole_password="$(openssl rand -base64 15)"

# avoid potential errors about failing post-install scripts
# due to missing indexinfo
pkg install -y indexinfo
[ -z $(echo $PATH | tr ':' '\n' | grep -x /usr/local/bin) ] && export PATH=$PATH:/usr/local/bin

# install packages
pkg install -y guacamole-client guacamole-server mariadb1011-server mysql-connector-j

# add service to startup
cat <<RCCONF >> /etc/rc.conf

# Enabled for Apache Guacamole:
# guacd_enable="YES"
# tomcat9_enable="YES"
# mysql_enable="YES"
RCCONF
sysrc guacd_enable="YES"
sysrc tomcat9_enable="YES"
sysrc mysql_enable="YES"

#create folder structure
mkdir /usr/local/etc/guacamole-client/lib
mkdir /usr/local/etc/guacamole-client/extensions

# extract java connector to guacamole
cp /usr/local/share/java/classes/mysql-connector-j.jar /usr/local/etc/guacamole-client/lib
tar xvfz /usr/local/share/guacamole-client/guacamole-auth-jdbc.tar.gz -C /tmp/
cp /tmp/guacamole-auth-jdbc-*/mysql/*.jar /usr/local/etc/guacamole-client/extensions

# optionally enable TOTP
if [ "$1" = "TOTP" ]; then
	tar xvfz /usr/local/share/guacamole-client/guacamole-auth-totp.tar.gz -C /tmp/
	cp /tmp/guacamole-auth-totp-*/*.jar /usr/local/etc/guacamole-client/extensions
fi

# configure guacamole server files
cp /usr/local/etc/guacamole-server/guacd.conf.sample /usr/local/etc/guacamole-server/guacd.conf
cp /usr/local/etc/guacamole-client/logback.xml.sample /usr/local/etc/guacamole-client/logback.xml
cp /usr/local/etc/guacamole-client/guacamole.properties.sample /usr/local/etc/guacamole-client/guacamole.properties

# Add UTF-8 encoding
sed -i '' '/connectionTimeout="20000"/a \
               URIEncoding="UTF-8"\
' /usr/local/apache-tomcat-9.0/conf/server.xml

# Add Valve to allow for proxying (with nginx)
sed -i '' '/<\/Host>/i \
        <Valve className="org.apache.catalina.valves.RemoteIpValve"\
               internalProxies="127.0.0.1"\
               remoteIpHeader="x-forwarded-for"\
               remoteIpProxiesHeader="x-forwarded-by"\
               protocolHeader="x-forwarded-proto" \/>\
\
' /usr/local/apache-tomcat-9.0/conf/server.xml

# nginx.conf proxying section for reference:
# 
# location / {
#     proxy_pass http://HOSTNAME:8080;
#     proxy_buffering off;
#     proxy_http_version 1.1;
#     proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
#     proxy_set_header Upgrade $http_upgrade;
#     proxy_set_header Connection $http_connection;
#     client_max_body_size 1g;
#     access_log off;
# }

# Change root to /:
# https://dae.me/blog/2572/apache-guacamole-how-to-change-the-default-url-path-guacamole-to-something-else/
# Note some of these files may not exist before tomcat is run for the first time so you may see some errors
mv /usr/local/apache-tomcat-9.0/webapps/guacamole /usr/local/apache-tomcat-9.0/webapps/guacamole.BAK
mv /usr/local/apache-tomcat-9.0/webapps/ROOT /usr/local/apache-tomcat-9.0/webapps/ROOT.BAK
mv /usr/local/apache-tomcat-9.0/webapps/guacamole.war /usr/local/apache-tomcat-9.0/webapps/ROOT.war

# Add database connection and TOTP issuer
cat <<GUACPROPS >> /usr/local/etc/guacamole-client/guacamole.properties
mysql-hostname: localhost
mysql-port:     3306
mysql-database: guacamole_db
mysql-username: guacamole_user
mysql-password: $guacamole_password
GUACPROPS

service mysql-server start

# Create username, password and database and change root password
/usr/local/bin/mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${mysqlroot}';CREATE DATABASE guacamole_db;CREATE USER 'guacamole_user'@'localhost' IDENTIFIED BY '${guacamole_password}';GRANT SELECT,INSERT,UPDATE,DELETE ON guacamole_db.* TO 'guacamole_user'@'localhost';FLUSH PRIVILEGES;";

# Apply schema to the database
cat /tmp/guacamole-auth-jdbc-*/mysql/schema/*.sql | /usr/local/bin/mysql -u root -p"${mysqlroot}" guacamole_db

service mysql-server stop

# clean up /tmp
rm -rf /tmp/guacamole-auth-*

cat <<GUACSETUP >> /root/guac-setup
Guacamole setup completed on: $(date +%c).
The default user for the Admin Portal is "guacadmin" with password "guacadmin"
Admin Portal: http://{IP_address}}:8080
MySQL Username: root
MySQL Password: $mysqlroot
Guacamole DB Username: guacamole_user
Guacamole DB Password: $guacamole_password
GUACSETUP
