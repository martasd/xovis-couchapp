#!/bin/bash

# Deploys XOvis app on a RHEL-based schoolserver. Requires internet connection.
# Usage: deploy_xovis.sh DEPLOYMENT_NAME SRC_DB_HOST [CLONE_DEST]
# Parameters:
#   DEPLOYMENT_NAME, the name of the deployment site
#   SRC_DB_HOST, the url (including the port) of the source Couch database
#   CLONE_DEST, path to where stats repository is cloned (/opt by default)

DEPS="python-pip curl git"
DEPLOYMENT=$1
USER=admin
PASS=admin
CREDENTIALS=$USER:$PASS
XOVIS_HOST_SRC=$2
XOVIS_HOST_TARGET_INIT=127.0.0.1:5984
XOVIS_HOST_TARGET=http://$CREDENTIALS@$XOVIS_HOST_TARGET_INIT
DB_NAME=xovis
DB_URL=$XOVIS_HOST_TARGET_INIT/$DB_NAME
INSERT_STATS_REPO=https://github.com/martasd/xo-stats.git

if [ $# -gt 2 ]
then
	CLONE_DEST=$3
else
	CLONE_DEST=/opt
fi

yum install -y $DEPS couchdb 
echo "Installed Couch with all its dependencies."

sed -i 's/^\(bind_address\s*=\s*\).*$/\10\.0\.0\.0/' /etc/couchdb/default.ini
echo "Made couch application accessible from other hosts."

service couchdb start
chkconfig --add couchdb
chkconfig couchdb on
echo "Couch configured to start on boot"

DB_CREATED=$(curl -X PUT $DB_URL)
ADMIN_ADDED=$(curl -X PUT $XOVIS_HOST_TARGET_INIT/_config/admins/$USER -d "\"$PASS\"")
if [ "$DB_CREATED" == '{"ok":true}' ] && [ "$ADMIN_ADDED" == '']
then
    echo "Created a Couch db $DB_NAME and added $USER to admins. Relax.:)"
else
    echo "Db creation $DB_NAME failed or user $USER was not added as admin."
    exit 1
fi

DB_REPLICATED=$(curl $XOVIS_HOST_TARGET/_replicate -H 'Content-Type: application/json' -d "{ \"source\": \"$XOVIS_HOST_SRC/$DB_NAME\", \"target\": \"$DB_NAME\" }")
if [[ "$DB_REPLICATED" == "\"ok\":true" ]]
then
    echo "Successfully replicated XOvis Couch App to $XOVIS_HOST_TARGET/$DB_NAME."
else
    echo "Replication failed."
    exit 1
fi 

mkdir -p $CLONE_DEST
cd $CLONE_DEST
git clone $INSERT_STATS_REPO
cd xo-stats
pip install -r requirements.txt
echo "Copied the latest version of stats script into $CLONE_DEST."

echo "At the deployment site:"
echo "First, copy back user backup data to the server after updating it:"
echo "rsync -rH <path-to-backup> /library/users"
echo "Then, run the following command at the deployment site to insert existing\
data into the database assuming you haven't changed default var values:"
echo "./process_journal_stats.py dbinsert $DB_NAME --deployment $DEPLOYMENT"

echo "To manage Couch using browser dashboard go to: $XOVIS_HOST_TARGET/_utils"
