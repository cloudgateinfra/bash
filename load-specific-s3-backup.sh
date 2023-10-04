!/bin/bash

# script for dev/qa environments only
# aws rds used for prod servers

# Usage: ./load-customer-db-test.sh [-h] [-s] [-c] <customer instance> <QA (local) instance>
# -s is optional and will save a backup of the QA instance locally if included
# -c is optional and will convert the newly imported database to utf8 if included

#IT LOADS A CUSTOMER DATABASE INTO THE LOCAL MYSQL SERVER USING THE CUSTOMER'S LATEST BACKUP ON S3
#REQUIRES THAT THE S3CMD BE ON THE PATH & CONFIGURED.


showHelp() {
cat << EOF
  Usage:            ./load-customer-db-test.sh [-c] [-s] <customer instance> <QA (local) instance>
  Alternate Usage:  ./load-customer-db-test.sh [-crs] <customer instance> <QA (local) instance>
  Alternate Usage:  ./load-customer-db-test.sh [-h] <customer instance> <QA (local) instance>
  Alternate Usage:  ./load-customer-db-test.sh <customer instance> <QA (local) instance>

    - h     Display this help and exit.
    - c     Convert the newly imported database to utf8.
    - r     Don't restart the Flex 5 Cluster.
    - s     Save a local copy of the current database before dropping it and importing the customer data.
    - b     Enable S3 backup of QA instance prior to importing customer data.
    - w     Which S3 backup you would like to choose via backup name.

EOF
}

NUM_OF_ARGS=$#

if [ $NUM_OF_ARGS -lt 2 ]
  then
    echo "Invalid number of arguments..."
    showHelp
    exit 1
fi

source ~/.profile

LAST_TWO_ELEMENTS="${@: -2}"
LAST_TWO_ELEMENTS_ARR=(${LAST_TWO_ELEMENTS// / })

CUSTOMER_INSTANCE=${LAST_TWO_ELEMENTS_ARR[0]}
QA_INSTANCE=${LAST_TWO_ELEMENTS_ARR[1]}

echo "customer instance: $CUSTOMER_INSTANCE"
echo "qa instance: $QA_INSTANCE"

DB_USER=root
DB_PASS=frs060511
SAVE_FLAG=false
CONVERT_FLAG=false
RESTART_FLAG=true
BACKUP_FLAG=false
WHICHBACKUP_FLAG=false

APACHE_DIR_1='/esb/APACHE-'$QA_INSTANCE
APACHE_DIR_2='/esb/APACHE/'$QA_INSTANCE'-base'

BACKUP_SCRIPT='/esb/scripts/'$QA_INSTANCE'-backup.sh'

while getopts ":hcrsbw" opt; do
  case $opt in
    h)
        showHelp
        exit 0
        ;;
    c)  CONVERT_FLAG=true
        ;;
    r)  RESTART_FLAG=false
        ;;
    s)  SAVE_FLAG=true
        ;;
    b)  BACKUP_FLAG=true
        ;;
    w)  WHICHBACKUP_FLAG=true
        ;;
    *)
        showHelp >&2
        exit 1
        ;;
  esac
done

loadCustomerDB () {

	CUSTOMER_NAME=$1
	DB_USER=$2
	DB_PW=$3
	QA_NAME=$4

	if [ -z "$CUSTOMER_NAME" ]; then
	   echo "No customer name... defaulting to qatemplate"
	   CUSTOMER_NAME="qatemplate"
	fi

	if [ -z "$DB_USER" ]; then
	   DB_USER="root"
	fi

	if [ -z "$DB_PW" ]; then
	   DB_PW="fruitloops"
	fi

	echo "Going to load database for "$CUSTOMER_NAME"..."

	rm -rfd ~/load-db-work

	mkdir ~/load-db-work

	cd ~/load-db-work

  DATE=$(s3cmd ls s3://test/customer-data/$CUSTOMER_NAME/ | sort -n | tail -n 1 | awk '{print $1}')
  S3_BACKUP=`s3cmd ls s3://test/customer-data/$CUSTOMER_NAME/ | grep $DATE | awk '{print $4}'`

  S3_BACKUP_PATH=$S3_BACKUP

  # if flag is true input the exact backup via S3 URI and checks if exists; if false exits
  # if not true default backup is run as normal and load function proceeds
  if [ "$WHICHBACKUP_FLAG" = true ]
    then
      read -p "Enter Backup i.e. testdebug-backup-February-01-2021.tar.gz:" WHICH_BACKUP
    S3_WHICHBACKUP_CHECK=$(s3cmd ls s3://test/customer-data/$CUSTOMER_INSTANCE/$WHICH_BACKUP | wc -l)
      if (($S3_WHICHBACKUP_CHECK > 0));
        then
          echo $S3_WHICHBACKUP_CHECK S3 backup for $CUSTOMER_INSTANCE found. Download will begin.
          s3cmd get s3://test/customer-data/$CUSTOMER_INSTANCE/$WHICH_BACKUP
      else
        echo No S3 backup for $CUSTOMER_INSTANCE found, exiting.
        exit 1
      fi
  else
    echo "S3 BACKUP PATH: "$S3_BACKUP_PATH
    s3cmd get $S3_BACKUP_PATH
  fi

	BACKUP_FILE=$(find $CUSTOMER_NAME*)

	tar -xvf $BACKUP_FILE

	cd esb/backup-work/$CUSTOMER_NAME/

	MYSQL_DUMP_FILE="$CUSTOMER_NAME.mysql"

	# Rename the old dbuser to the new one for things like triggers, procedures and views.
	# The backticks are necessary to prevent superstrings from being effected.  Ex. osa is a substring of closable but also a customer instance name.
  sed -i "10,\$s|\`$CUSTOMER_INSTANCE\`|\`$QA_INSTANCE\`|g" "$MYSQL_DUMP_FILE"
  sed -i "10,\$s|'$CUSTOMER_INSTANCE'|'$QA_INSTANCE'|g" "$MYSQL_DUMP_FILE"
  sed -i "s|https://$CUSTOMER_INSTANCE\.test.com|https://$QA_INSTANCE\.test.com|g" "$MYSQL_DUMP_FILE"


	#dump current DB
	echo "Dropping database..."
	mysqladmin -u$DB_USER -p$DB_PW -f drop $QA_NAME

	#create new DB
	echo "Creating database..."

	if [ "$CONVERT_FLAG" = true ]
	  then
      mysql -u$DB_USER -p$DB_PW -e "create database $QA_NAME character set utf8mb4 collate utf8mb4_unicode_ci;"

	    echo "Starting utf8 conversion..."

	    sed -i 's/DEFAULT CHARACTER SET latin1/DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci/g' "$MYSQL_DUMP_FILE"

      sed -i 's/DEFAULT CHARSET=latin1/DEFAULT CHARSET=utf8mb4 COLLATE utf8mb4_unicode_ci ROW_FORMAT=DYNAMIC/g' "$MYSQL_DUMP_FILE"

      sed -i 's/CHARSET latin1/CHARSET utf8mb4/g' "$MYSQL_DUMP_FILE"

      sed -i 's/charset latin1/CHARSET utf8mb4/g' "$MYSQL_DUMP_FILE"

      echo "Finished utf8 conversion"
  else
    	# Determine whether we are using latin1 or utf8
    	head -100 $CUSTOMER_NAME.mysql > tmp-search-encoding.txt
	    case $(grep -F "DEFAULT CHARSET=utf8mb4" "tmp-search-encoding.txt" >/dev/null; echo $?) in
        0)
          # if found
          mysql -u$DB_USER -p$DB_PW -e "create database $QA_NAME character set utf8mb4 collate utf8mb4_unicode_ci;"
          ;;
        1)
          # if not found
          mysql -u$DB_USER -p$DB_PW -e "create database $QA_NAME character set latin1 collate latin1_swedish_ci;"
          ;;
        *)
          # if an error occurred
          echo "An error occurred while searching for the default character set, please check the backup."
          ;;
      esac
      rm tmp-search-encoding.txt
	fi

	#load new DB
	echo "Loading database..."
	pv $CUSTOMER_NAME.mysql | mysql -u$DB_USER -p$DB_PW $QA_NAME

	# disable the mail setting and all automated functions
	echo "Disabling mail..."
	mail_settings_results=$(mysql -u$DB_USER -p$DB_PW -e "SELECT COUNT(*) FROM $QA_NAME.rh_mail_settings WHERE is_email_enabled = 1;")
	if [[ "$mail_settings_results" == *"0"* ]]
	then
	  mysql -u$DB_USER -p$DB_PW -e "INSERT INTO $QA_NAME.rh_mail_settings (email_provider, host_name, user_name, password, port, is_authenticate, is_use_tls, is_email_enabled, id) VALUES ('sendgrid', NULL, NULL, NULL, 587, 1, 1, 0, (SELECT UUID()));"
	else
	  mysql -u$DB_USER -p$DB_PW -e "UPDATE $QA_NAME.rh_mail_settings SET is_email_enabled = 0 WHERE is_email_enabled = 1;"
	fi

	echo "Disabling Automated Functions..."
	mysql -u$DB_USER -p$DB_PW -e "UPDATE $QA_NAME.st_biz_scheduled_task SET enabled = 0 WHERE enabled = 1;"

	echo "Successfully loaded database "$QA_NAME" with "$CUSTOMER_NAME" data."
}

scheduleDowntime() {
  hrs=0
  mins=30
  echo "Scheduling downtime of $mins minutes for all services on host $(hostname)."
  /esb/scripts/schedule_downtime.sh "$hrs" "$mins" $(hostname)
}

#Check if valid qa instance to install to
if [ -d "$APACHE_DIR_1" ]
  then
      APACHE_DIR=$APACHE_DIR_1
      APACHE_SH=$APACHE_DIR_1'/bin/APACHE.sh'
      APACHE_CONFIG=$APACHE_DIR_1'/etc/APACHE.xml'
      APACHE_SED='XML'
fi

if [ -d "$APACHE_DIR_2" ]
  then
      APACHE_DIR=$APACHE_DIR_2
      APACHE_SH='/esb/APACHE/bin/APACHE-'$QA_INSTANCE'.sh'
      APACHE_CONFIG=$APACHE_DIR_2'/start.ini'
      APACHE_SED='INI'
fi

# if not a valid instance quit. TO DO: MAKE THIS A LIST OF VALID QA INSTANCES IN CASE THIS GETS OUT INTO THE WILD
if [ ! -d "$APACHE_DIR" ]
  then
    echo Invalid QA Instance name.  Please supply a valid QA Instance.  Passed in QA instance name: $QA_INSTANCE
    exit 1
  fi

echo Found QA Instance $QA_INSTANCE proceeding.  Using $APACHE_DIR as base.

if [ "$SAVE_FLAG" = true ]
  then
    DATE_NOW=$(date +"%m_%d_%Y_%H%M%S")
    DEFAULT_DB_SAVE_LOC="/esb/backups/$QA_INSTANCE/manual_backups/"

    DB_NAME=$QA_INSTANCE

    read -p "Enter the location where you would like to save the database $DB_NAME backup [$DEFAULT_DB_SAVE_LOC]: " DB_SAVE_LOC
    DB_SAVE_LOC=${DB_SAVE_LOC:-$DEFAULT_DB_SAVE_LOC}

    mkdir -p "$DB_SAVE_LOC"

    DB_SAVE_FL="$DB_NAME-$DATE_NOW.sql"
    DB_SAVE_LOC_AND_FL="$DB_SAVE_LOC$DB_SAVE_FL"

    mysqldump -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" --hex-blob --routines --single-transaction --quick --lock-tables=false | pv --progress --size 25g > "$DB_SAVE_LOC_AND_FL"

    cd "$DB_SAVE_LOC" && tar -czf "$DB_NAME-$DATE_NOW.tar.gz" "$DB_SAVE_FL" --remove-files
fi

# Check if backup for customer instance exists, exit if it does not exist
S3_BACKUP_CHECK=$(s3cmd ls s3://test/customer-data/$CUSTOMER_INSTANCE/ | wc -l)
if (($S3_BACKUP_CHECK > 0));
then
  echo $S3_BACKUP_CHECK S3 backups for $CUSTOMER_INSTANCE found, proceeding.
else
  echo No S3 backup for $CUSTOMER_INSTANCE exists, exiting.
  exit 1
fi

# Check if backup script exists, if it does then check if customer and qa instance are the same, skip backup if they
#   are the same since backup would overwrite newest backup and the script would load its own backup.
#   terminal outputs 'tar: Removing leading `/' from member names' when using full path.
if [ -e $BACKUP_SCRIPT ]
then
  if [ $CUSTOMER_INSTANCE != $QA_INSTANCE ]
  then
    if [ "$BACKUP_FLAG" = true ]
      then
	      echo Backing up $QA_INSTANCE
	      ("$BACKUP_SCRIPT")
	    else
	      echo Skipping S3 backup of $QA_INSTANCE
	    fi
	else
	  echo Customer Instance and QA Instance are the same, skipping backup and proceeding.
	fi
else
	echo Backup script $BACKUP_SCRIPT does not exist, exiting.
	exit 1
fi

# if it's not a vagrant, schedule downtime for host and all instances on host to keep Nagios from lighting up (mostly for Ops)
if id "vagrant" &>/dev/null; then
    echo "vagrant user found, not scheduling Nagios downtime"
else
    scheduleDowntime
fi

echo Stopping $QA_INSTANCE APACHE...
systemctl stop APACHE-$QA_INSTANCE.service

# if lucene is present remove it
if [ -d "$APACHE_DIR/lucene" ]
  then
    echo Removing lucene directory $APACHE_DIR
    rm -r $APACHE_DIR/lucene
fi
# Call loadCustomerDB loads customer data into qa instance database.
loadCustomerDB $CUSTOMER_INSTANCE $DB_USER $DB_PASS $QA_INSTANCE

# Restart APACHE
echo Retarting $QA_INSTANCE APACHE...
systemctl restart APACHE-$QA_INSTANCE.service

# Restart the test instances if the RESTART_FLAG is true
if [ "$RESTART_FLAG" = true ]
  then
    echo Restarting all test instances...
    fpm5-all restart
fi
