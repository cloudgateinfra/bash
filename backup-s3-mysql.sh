#!/bin/bash
set -o errexit
# replace yourpath with your desired path
BACKUP_WORK=/yourpath/backup-work/testuser
BACKUP_TARGET=/yourpath/backups/testuser
DB_USER=testuser
CUSTOMER_NAME=testuser

# newpasswordhere = mysql password
mysqldump --hex-blob  --max_allowed_packet=1G --routines -u $DB_USER --password=newpasswordhere $DB_USER > $BACKUP_WORK/$CUSTOMER_NAME.mysql


NOW=$(date +"%B-%d-%Y")

FILE_NAME="$CUSTOMER_NAME-backup-"$NOW".tar.gz"

FULL_PATH=$BACKUP_TARGET"/"$FILE_NAME

tar cfzv $FULL_PATH $BACKUP_WORK/*

rm -rfd $BACKUP_WORK/*

s3cmd --config ~/.s3cfg put $FULL_PATH s3://data/$CUSTOMER_NAME/$FILE_NAME
