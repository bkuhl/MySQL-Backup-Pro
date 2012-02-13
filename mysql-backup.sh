#!/bin/bash
# MySQL database backup (databases in separate files) with daily, weekly and monthly rotation
# Added to GitHub by Ben Kuhl - https://github.com/bkuhl/MySQL-Backup
# - Version 1.0
#
# Sebastian Flippence (http://seb.flippence.net) originally based on code from: Ameir Abdeldayem (http://www.ameir.net)
# You are free to modify and distribute this code,
# so long as you keep the authors name and URL in it.
# By default it will search for the config file in the same directory as this script, otherwise you can choose it (e.g. ./mysqlbackup.sh /path/to/mysqlbackup.conf)
# Read the config file
if [ "$1" = "" ]; then
	CONFIG_FILE="`dirname $0`/mysql-backup.conf"
else
	CONFIG_FILE="$1"
fi
 
if [ -f "$CONFIG_FILE" ]; then
	echo "Loading config file ($CONFIG_FILE)"
	. $CONFIG_FILE
else
	echo "Config file not found ($CONFIG_FILE)"
	exit 1
fi
 
# Setup some command defaults (can be overriden by the config)
MYSQL=${MYSQL:-`which mysql`}
MYSQLDUMP=${MYSQLDUMP:-`which mysqldump`}
PHP=${PHP:-`which php`}
 
# Date format that is appended to filename
DATE=`date +'%Y-%m-%d'`

# Setup paths
ARCHIVE_PATH="${BACKDIR}/${ARCHIVE_PATH}"

ORGBACKDIR="${BACKDIR}"
BACKDIR="${BACKDIR}/${LATEST_PATH}/${DATE}"

function checkMysqlUp() {
	$MYSQL -N -h $HOST --user=$USER --password=$PASS -e status
}
trap checkMysqlUp 0
 
function error() {
  local PARENT_LINENO="$1"
  local MESSAGE="$2"
  local CODE="${3:-1}"
  if [[ -n "$MESSAGE" ]] ; then
    echo "Error on or near line ${PARENT_LINENO}: ${MESSAGE}; exiting with status ${CODE}"
  else
    echo "Error on or near line ${PARENT_LINENO}; exiting with status ${CODE}"
  fi
  exit "${CODE}"
}
trap 'error ${LINENO}' ERR
 
# Check backup directory exists
# if not, create it
if  [ -e $BACKDIR ]; then
	echo "Backup directory exists (${BACKDIR})"
else
	mkdir -p $BACKDIR
	echo "Created backup directory (${BACKDIR})"
fi
 
if  [ $DUMPALL = "y" ]; then
	echo "Creating list of databases on: ${HOST}..."
 
	$MYSQL -N -h $HOST --user=$USER --password=$PASS -e "show databases;" > ${BACKDIR}/dbs_on_${SERVER}.txt
 
	# redefine list of databases to be backed up
	DBS=`sed -e ':a;N;$!ba;s/\n/ /g' -e 's/Database //g' ${BACKDIR}/dbs_on_${SERVER}.txt`
fi
 
echo "Backing up MySQL databases..."
 
for database in $DBS; do
	echo "    - ${database}..."
 
	$MYSQLDUMP --host=$HOST --user=$USER --password=$PASS --default-character-set=utf8 --skip-set-charset --routines --disable-keys --force --single-transaction --allow-keywords $database > ${BACKDIR}/${SERVER}-MySQL-backup-$database-${DATE}.sql
 
	bzip2 -f ${BACKDIR}/${SERVER}-MySQL-backup-$database-${DATE}.sql
done
 
if  [ $DUMPALL = "y" ]; then
	rm ${BACKDIR}/dbs_on_${SERVER}.txt
fi
 
if [ $MOVETAR = "y" ]; then
echo "Moving sql.bz2 files to tar"
	for file in `ls ${BACKDIR}/*.bz2`; do
		tar -rf ${BACKDIR}/${SERVER}-MySQL-backup-${DATE}.tar $file
		rm $file
	done
	EXT="tar"
else
	EXT="sql.bz2"
fi
 
# If you have the mail program 'mutt' installed on
# your server, this script will have mutt attach the backup
# and send it to the email addresses in $EMAILS
 
if  [ $MAIL = "y" ] && [ $EMAILSENDON = $EMAILTODAY  ]; then
	BODY="MySQL backup is ready"
	ATTACH=`for file in ${BACKDIR}/*${DATE}.${EXT}; do echo -n "-a ${file} ";  done`
 
	echo "${BODY}" | mutt -s "${SUBJECT}" $ATTACH $EMAILS
 
	echo -e "MySQL backup has been emailed"
fi
 
if  [ $FTP = "y" ]; then
	echo "Initiating FTP connection..."
	cd $BACKDIR
	ATTACH=`for file in ${BACKDIR}/*${DATE}.${EXT}; do echo -n -e "put ${file}\n"; done`
 
	ftp -nv <<EOF
open $FTPHOST
user $FTPUSER $FTPPASS
cd $FTPDIR
$ATTACH
quit
EOF
	echo -e  "FTP transfer complete"
fi
 
if  [ $ROTATE = "y" ]; then
	echo "Performing backup rotation..."	
 
	# Convert the number of weeks and months to days
	MAX_WEEKS=$(($MAX_WEEKS * 7))
	MAX_MONTHS=$(($MAX_MONTHS * 31))
 
	# Daily backups
	if [ ! -d $ARCHIVE_PATH/$DAILY_PATH/$DATE ] && [ "$MAX_DAYS" -gt "0" ]; then
		mkdir -p $ARCHIVE_PATH/$DAILY_PATH/$DATE
		# Copy files into archive dir 
		find $BACKDIR -name "*.$EXT" -exec cp {} $ARCHIVE_PATH/$DAILY_PATH/$DATE/. \;
	fi
 
	# Delete old daily backups
	if [ -d $ARCHIVE_PATH/$DAILY_PATH ]; then
		find $ARCHIVE_PATH/$DAILY_PATH/ -maxdepth 1 -type d ! -name $DAILY_PATH -mtime +$MAX_DAYS -exec rm -Rf {} \;
 
		if [ "$MAX_DAYS" -lt "1" ]; then
			rm -Rf $ARCHIVE_PATH/$DAILY_PATH/
		fi		
	fi
 
	# Weekly backups
	WEEK_NO=`$PHP -r 'echo ceil(date("j", time())/7);'`
	DATE_WEEK="`date +'%Y-%m-'`$WEEK_NO"
 
	if [ ! -d $ARCHIVE_PATH/$WEEKLY_PATH/$DATE_WEEK ] && [ "$MAX_WEEKS" -gt "0" ]; then
		mkdir -p $ARCHIVE_PATH/$WEEKLY_PATH/$DATE_WEEK
		# Copy files into archive dir 
		find $BACKDIR -name "*.$EXT" -exec cp {} $ARCHIVE_PATH/$WEEKLY_PATH/$DATE_WEEK/. \;
	fi
 
	# Delete old weekly backups
	if [ -d $ARCHIVE_PATH/$WEEKLY_PATH ]; then
		find $ARCHIVE_PATH/$WEEKLY_PATH/ -maxdepth 1 -type d ! -name $WEEKLY_PATH -mtime +$MAX_WEEKS -exec rm -Rf {} \;
 
		if [ "$MAX_WEEKS" -lt "1" ]; then
			rm -Rf $ARCHIVE_PATH/$WEEKLY_PATH/
		fi		
	fi
 
	# Monthly backups
	DATE_MONTH=`date +'%Y-%m'`
 
	if [ ! -d $ARCHIVE_PATH/$MONTHLY_PATH/$DATE_MONTH ] && [ "$MAX_MONTHS" -gt "0" ]; then
		mkdir -p $ARCHIVE_PATH/$MONTHLY_PATH/$DATE_MONTH
		# Copy files into archive dir 
		find $BACKDIR -name "*.$EXT" -exec cp {} $ARCHIVE_PATH/$MONTHLY_PATH/$DATE_MONTH/. \;
	fi
 
	# Delete old monthly backups
	if [ -d $ARCHIVE_PATH/$MONTHLY_PATH ]; then
		find $ARCHIVE_PATH/$MONTHLY_PATH/ -maxdepth 1 -type d ! -name $MONTHLY_PATH -mtime +$MAX_MONTHS -exec rm -Rf {} \;
 
		if [ "$MAX_MONTHS" -lt "1" ]; then
			rm -Rf $ARCHIVE_PATH/$MONTHLY_PATH/
		fi		
	fi
 
 
	# Delete old backups in latest folder (-mtime +0 is 24 hours or older)
	find $ORGBACKDIR/$LATEST_PATH/ -maxdepth 1 -type d ! -name $LATEST_PATH -mtime +0 -exec rm -Rf {} \;
 
	echo "Backups rotation complete"
fi
 
echo "MySQL backup is complete"
