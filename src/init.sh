#!/bin/bash
#
# Init script
#
###########################################################

# Thanks to http://stackoverflow.com/a/10467453
function sedeasy {
  sed -i "s/$(echo $1 | sed -e 's/\([[\/.*]\|\]\)/\\&/g')/$(echo $2 | sed -e 's/[\/&]/\\&/g')/g" $3
}

if [ -z "$API_KEY" ]; then
  # Generate a random API Key everytime so only this Docker knowns it, not everybody
  API_KEY=`dbus-uuidgen`
fi

# Path where DBs will be stored
POWERDNS_DB_PATH="$DATA_DIR/powerdns"
POWERDNSGUI_DB_PATH="$DATA_DIR/powerdnsgui"

# Create directory if they does not exist
mkdir -p $POWERDNS_DB_PATH
mkdir -p $POWERDNSGUI_DB_PATH

# Update PowerDNS Server config file
sedeasy "api-key=API_KEY" "api-key=$API_KEY" /etc/pdns/pdns.conf
sedeasy "gsqlite3-database=DATABASE_PATH" "gsqlite3-database=$POWERDNS_DB_PATH/db" /etc/pdns/pdns.conf

# Add custom DNS entries
sedeasy ";CUSTOM_DNS" ";$CUSTOM_DNS" /etc/pdns/recursor.conf

# Update PowerDNS Admin GUI configuration file
sedeasy "PDNS_API_KEY = 'PDNS_API_KEY'" "PDNS_API_KEY = '$API_KEY'" /usr/share/webapps/powerdns-admin/config.py
sedeasy "SQLALCHEMY_DATABASE_URI = 'SQLALCHEMY_DATABASE_URI'" "SQLALCHEMY_DATABASE_URI = 'sqlite:///$POWERDNSGUI_DB_PATH/db'" /usr/share/webapps/powerdns-admin/config.py

# Create SQLite database for PowerDNS if it's doesn't exist
if ! [ -f "$POWERDNS_DB_PATH/db" ]; then
  sqlite3 $POWERDNS_DB_PATH/db < /usr/share/doc/pdns/schema.sqlite3.sql
fi

# Create SQLite database for PowerDNS Admin if it's doesn't exist
cd /usr/share/webapps/powerdns-admin
if ! [ -f "$POWERDNSGUI_DB_PATH/db" ]; then
  flask db init --directory ./migrations
  flask db migrate -m "Init DB" --directory ./migrations
  flask db upgrade --directory ./migrations
else
  set +e
  flask db migrate -m "Upgrade BD Schema" --directory ./migrations
  flask db upgrade --directory ./migrations
  set -e
fi
cd ~

# Fix permissions
find $DATA_DIR -type d -exec chmod 775 {} \;
find $DATA_DIR -type f -exec chmod 664 {} \;
chown -R nobody:nobody $DATA_DIR

if [ $ENABLE_ADBLOCK = true ]; then
  # Run at least the first time
  /root/updateHosts.sh

  # Initialize the cronjob to update hosts, if feature is enabled
  cronFile=/tmp/buildcron
  printf "SHELL=/bin/bash" > $cronFile
  printf "\n$CRONTAB_TIME /usr/bin/flock -n /tmp/lock.hosts /root/updateHosts.sh\n" >> $cronFile
  crontab $cronFile
  rm $cronFile
fi

# Start supervisor
/usr/bin/supervisord -c /etc/supervisord.conf
