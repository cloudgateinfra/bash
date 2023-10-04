#!/bin/bash

AWS_ACCESS_KEY_ID="$1"
AWS_SECRET_ACCESS_KEY="$2"
AWS_DEFAULT_REGION="$3"
MYSQL_PWD="$4"
MYSQL_USER="$5"
MYSQL_DB="$6"
DUMP_FILE_NAME="$7"

DUMP_FOLDER=$(basename "$DUMP_FILE_NAME" .tar.gz)

sudo apt-get update
sudo apt-get install -y awscli mysql-client

aws s3 cp "s3://prod-db-dump/$DUMP_FILE_NAME" "/tmp/$DUMP_FILE_NAME"

mkdir -p "/tmp/$DUMP_FOLDER"
tar -xvzf "/tmp/$DUMP_FILE_NAME" --strip-components=1 -C "/tmp/$DUMP_FOLDER/"
echo "Contents of /tmp/:"
ls -al /tmp/

echo "Contents of /tmp/$DUMP_FOLDER/:"
ls -al "/tmp/$DUMP_FOLDER/"

# Choose one SQL file
SQL_FILE=$(find /tmp/ -maxdepth 1 -type f -name '*.sql' | head -1)
echo "Selected SQL File: $SQL_FILE"
echo "DEBUG: All SQL Files:"
find /tmp/ -maxdepth 1 -type f -name '*.sql'

# Check and alert if the SQL file does not exist
echo "SQL_FILE is: $SQL_FILE"

if [[ -z "$SQL_FILE" ]]; then
    echo "Error: SQL filename is empty!"
    exit 1
fi

if [[ ! -f "$SQL_FILE" ]]; then
    echo "Error: SQL file not found!"
    exit 1
fi

# Restore the database using the selected SQL file
cat "$SQL_FILE" | MYSQL_PWD=$MYSQL_PWD mysql -h terraform-20230809200001.ct06mdy.us-west-2.rds.amazonaws.com -P 3306 -u $MYSQL_USER $MYSQL_DB
