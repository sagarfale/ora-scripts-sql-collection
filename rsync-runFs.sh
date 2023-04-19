#!/bin/ksh

#####################################################################################################################################
# Synchronize directories
#####################################################################################################################################
# History:
#------------------------------------------------------------------------------------------------------------------------------------
#YYYY-MM-DD:Author:Text
#------------------------------------------------------------------------------------------------------------------------------------
#script to rsync EBS file system to DR
#####################################################################################################################################


####################
## Global variables
####################

EXEC_DATE=$(date +"%Y%m%d_%H%M%S")
APP_NAME="EBS"
CLIENT_NAME="MGRC"

WORK_DIR=$(dirname $0)
TEMP_DIR="${WORK_DIR}/temp"
SCP_LOG="${WORK_DIR}/logs/rsync.${EXEC_DATE}.log"
TEMP_FILE="${TEMP_DIR}/rsync_part"
EXCPT_FILE="${TEMP_DIR}/rsync_excpt.log"

SOURCE_HOST=$(hostname -f)
TARGET_HOST=""
TARGET_USER=""

MAIL_BODY="${TEMP_DIR}/email.tmp"
MAIL_LIST=""
MAIL_SUBJECT="${CLIENT_NAME} // DR Synchronization report // Hosts: ${SOURCE_HOST}->${TARGET_HOST} - Date: ${EXEC_DATE} - Status: OUTCOME"
MAIL_SGNTR="${WORK_DIR}/ITC_SD.sg"

STATUS=0
LIMITED_OUTPUT=0

####################
## Functions
####################

##
## Confirm another instance of the process is not already running
##
##   Usage: check_already_active
##
check_already_active()
{
  L_USER_ID="$(whoami)"; export L_USER_ID
  L_PRG_NAME="$(basename $0 .sh)"; export L_PRG_NAME
  L_PROC_ID="$$"; export L_PROC_ID
  L_PPROC_ID=`ps -ef | awk '$2==ENVIRON["L_PROC_ID"] {print $3}'`; export L_PPROC_ID

  L_ACTIVE_CNT=`ps -ef | egrep -v "tail|vim" | awk '
    BEGIN {
      procid=ENVIRON["L_PROC_ID"];
      pprocid=ENVIRON["L_PPROC_ID"];
      ptext=ENVIRON["L_PRG_NAME"];
      preccnt=0;
      pmatchcnt=0;
      while (getline && preccnt<5000) {
        ++preccnt;
        if ($0 ~ ptext && $2 != procid && $2 != pprocid && $3 != procid && $3 != pprocid ) {
          ++pmatchcnt;
        }
      }
    } END {
      print pmatchcnt
    }'
  `
  if [ $? -eq 0 ]
  then
    if [ ${L_ACTIVE_CNT:-1} -gt 0 ]
    then
      printf "\nERROR: Another instance of the process found in memory...Aborting...\n\n"
      return 1
    fi
  else
    printf "\nERROR: A problem was found while trying to identify already running processes...Aborting...\n\n"
    return 1
  fi

  return 0
}


####################
## Main
####################

#Preserve Standard output
exec 7<&0

#Redirects Standard output
exec 1<&-
exec 1>"${SCP_LOG}"

#Redirects Standard error
exec 2>&1

check_already_active
if [ $? -eq 0 ]
then
  ## Test login just in case
  ##ssh -p 873 -t  -o PasswordAuthentication=no -o RSAAuthentication=yes -l ${TARGET_USER} ${TARGET_HOST}  date "bash --noprofile"  1>/dev/null 2>&1
  ssh -p 22  -t -o PasswordAuthentication=no -o RSAAuthentication=yes -l ${TARGET_USER} ${TARGET_HOST}  hostname 1>/dev/null 2>&1
  if [ $? -ne 0 ]
  then
    printf "\nERROR: Unable to connect to destination. Please verify Server and User information...Aborting...\n\n"
    exit 1
  fi

  cat /dev/null > ${EXCPT_FILE} 2>/dev/null
  if [ $? -ne 0 ]
  then
    printf "\nERROR: Unable to generate temporary file <%s>...Aborting...\n\n" ${EXCPT_FILE}
    exit 1
  fi

  . /home/applmgr/EBSapps.env run 2>/dev/null
  if [ $? -ne 0 ]
  then
    printf "\nERROR: Unable to load Apps environment...Aborting...\n\n"
    exit 1
  fi

  # -v: Verbose
  # -a: Archive mode
  # -l: Copy symlinks as symlinks
  # -r: Recursive
  # -p: Preserve permissions
  # -E: Preserve Executability
  # -X: Preserve extended attributes
  # -t: Preserve time modification times
  # -O: This tells rsync to omit directories when it is preserving modification times (see --times).
  # -z: Compress file data during the transfer
  # -e: Remote shell to use
  # -i: Output a change-summary for all updates
  # -h: Output numbers in a human-readable format
  # --inplace: update destination files in-place
  # --append-verify: This  works just like the --append option, but the existing data on the receiving side is included
  #                  in the full-file checksum verification step, which will cause a file to be resent if the final
  #                  verification step fails (rsync uses a normal, non-appending --inplace transfer for the resend).
  # --files-from: Read list of source-file names from FILE
  # --delete|--del: Delete extraneous files from dest dirs
  # --delete-during: Receiver deletes during xfer, not before
  # --backup: With this option, preexisting destination files are renamed as each file is transferred or deleted.
  # --backup-dir=DIR: In combination with the --backup option, this tells rsync to store all backups in the specified
  #                   directory on the receiving side.  This can be used for incremental backups.
  # --list-only: List the files instead of copying them
  # -n|--dry-run: This  makes  rsync  perform  a  trial run that doesn’t make any changes (and produces mostly the same
  #                 output as a real run)
  # --bwlimit=KBPS: Limit I/O bandwidth; KBytes per second
  # --timeout=TIMEOUT: This option allows you to set a maximum I/O timeout in seconds. If no data is transferred for
  #                    the specified time then rsync will exit. The default is 0, which means no timeout.
  # --stats: Extended transfer stats
  # --log-file=FILE: This option causes rsync to log what it is doing to a file.
  # --progress: Show progress during transfer (Do not use on batch mode. It generates huge output)

  echo "####################################################"
  echo "## Synchronization process started (`date`)"
  echo "####################################################"

  ### RUN_BASE
  echo " "
  echo "#---------------------------------------------------"
  echo "# RUN_BASE (`date`)"
  echo "#---------------------------------------------------"
  set -x
  #--delete \
  #--delete-during \
  /usr/bin/rsync \
  -avlhrptzXOi \
  -e "ssh -t -p 22 -o 'ProxyCommand ssh -q -W %h:%p ${TARGET_USER}@${TARGET_HOST}'" \
  --stats \
  --block-size=131072 \
  --exclude ${INST_TOP}/appltmp \
  --exclude ${INST_TOP}/temp \
  --exclude ${INST_TOP}/logs/appl/rgf \
  --exclude ${INST_TOP}/logs/ora/10.1.2/forms/em*.rti \
  --exclude ${INST_TOP}/logs/ora/10.1.2/reports/cache \
  ${RUN_BASE}/ \
  ${TARGET_USER}@${TARGET_HOST}:${RUN_BASE} \
  --rsync-path=/usr/bin/rsync 2> ${TEMP_FILE}.runbase
  set +x

  ### NE_BASE
  echo " "
  echo "#---------------------------------------------------"
  echo "# FS_NE (`date`)"
  echo "#---------------------------------------------------"
  set -x
  #--delete \
  #--delete-during \
  /usr/bin/rsync \
  -avlhrptzXOi \
  -e "ssh -t -p 22 -o 'ProxyCommand ssh -q -W %h:%p ${TARGET_USER}@${TARGET_HOST}'" \
  --stats \
  --block-size=131072 \
  ${NE_BASE}/ \
  ${TARGET_USER}@${TARGET_HOST}:${NE_BASE} \
  --rsync-path=/usr/bin/rsync 2> ${TEMP_FILE}.nebase
  set +x

  ###  APPLCSF
  echo " "
  echo "#---------------------------------------------------"
  echo "# APPLCSF (`date`)"
  echo "#---------------------------------------------------"
  set -x
  /usr/bin/rsync \
  -avlhrptzXOi \
  -e "ssh -t -p 22 -o 'ProxyCommand ssh -q -W %h:%p ${TARGET_USER}@${TARGET_HOST}'" \
  --stats \
  --block-size=131072 \
  --delete \
  --delete-during \
  ${APPLCSF}/ \
  ${TARGET_USER}@${TARGET_HOST}:${APPLCSF} \
  --rsync-path=/usr/bin/rsync 2> ${TEMP_FILE}.applcsf
  set +x

  #cat ${TEMP_FILE}.* > ${EXCPT_FILE}
  for FILE_NAME in `ls ${TEMP_FILE}.* 2>/dev/null`
  do
    if [ -s ${FILE_NAME} ]
    then
      LINE_COUNT=`wc -l ${FILE_NAME} | awk '{print $1}'`
      echo "#-------------------------------------"
      echo "# ${FILE_NAME}"
      echo "#-------------------------------------"
      if [ ${LINE_COUNT:-999} -gt 100 ]
      then
        head -15 ${FILE_NAME} >> ${EXCPT_FILE}
        echo " "  >> ${EXCPT_FILE}
        echo "."  >> ${EXCPT_FILE}
        echo "."  >> ${EXCPT_FILE}
        echo "."  >> ${EXCPT_FILE}
        echo " "  >> ${EXCPT_FILE}
        tail -15 ${FILE_NAME} >> ${EXCPT_FILE}
        echo " "  >> ${EXCPT_FILE}
        LIMITED_OUTPUT=1
      else
        cat ${FILE_NAME} >> ${EXCPT_FILE}
      fi
    fi
  done
else
  STATUS=1
fi


echo " "
echo "####################################################"
echo "## Synchronization process completed (`date`)"
echo "####################################################"
echo " "

## Restore stdout
exec 1>&7

## Send Email
if [ ${STATUS} -eq 0 ]
then
  if [ -s ${EXCPT_FILE} ]
  then
    #SUBJECT="${CLIENT_NAME} // Rsync // ${SOURCE_HOST} to ${TARGET_HOST} (${APP_NAME}) completed with WARNINGS! (${EXEC_DATE})"
    MAIL_SUBJECT=`echo ${MAIL_SUBJECT} | sed -e "s/OUTCOME/WARNING/"`
    MAIL_TEXT="Some files were not updated. Please see the exceptions below."
  else
    #SUBJECT="${CLIENT_NAME} // Rsync // ${SOURCE_HOST} to ${TARGET_HOST} (${APP_NAME}) completed successfully! (${EXEC_DATE})"
    MAIL_SUBJECT=`echo ${MAIL_SUBJECT} | sed -e "s/OUTCOME/SUCCESS/"`
    MAIL_TEXT="The synchronization process completed successfully. No action required."
  fi
else
  #SUBJECT="${CLIENT_NAME} // Rsync // ${SOURCE_HOST} to ${TARGET_HOST} (${APP_NAME}) has been SKIPPED! (${EXEC_DATE})"
  MAIL_SUBJECT=`echo ${MAIL_SUBJECT} | sed -e "s/OUTCOME/SKIPPED/"`
  MAIL_TEXT="Process is already active...Aborting..."
fi

#sed -i "1i Subject: $SUBJECT" ${MAIL_BODY}
echo "Subject: $MAIL_SUBJECT" > ${MAIL_BODY}
echo " " >> ${MAIL_BODY}
echo "Hello, " >> ${MAIL_BODY}
echo " " >> ${MAIL_BODY}

echo "${MAIL_TEXT}" >> ${MAIL_BODY}
echo " " >> ${MAIL_BODY}
echo " " >> ${MAIL_BODY}

if [ -s ${EXCPT_FILE} ]
then
  if [ ${LIMITED_OUTPUT:-1} -ne 0 ]
  then
    cat <<_EOF_
***NOTE: Please notice that output was restricted due to its size. For full listing, please see output file.

_EOF_
  fi

  echo "######################################################" >> ${MAIL_BODY}
  echo "## Exceptions - BEGIN" >> ${MAIL_BODY}
  echo "######################################################" >> ${MAIL_BODY}
  cat ${EXCPT_FILE} >> ${MAIL_BODY}
  echo "######################################################" >> ${MAIL_BODY}
  echo "## Exceptions - END" >> ${MAIL_BODY}
  echo "######################################################" >> ${MAIL_BODY}
  echo " " >> ${MAIL_BODY}
  echo " " >> ${MAIL_BODY}
fi

#echo "######################################################" >> ${MAIL_BODY}
#echo "## Synchronization Output - BEGIN" >> ${MAIL_BODY}
#echo "######################################################" >> ${MAIL_BODY}
#cat ${SCP_LOG} >> ${MAIL_BODY}
#echo "######################################################" >> ${MAIL_BODY}
#echo "## Synchronization Output - END" >> ${MAIL_BODY}
#echo "######################################################" >> ${MAIL_BODY}
#echo " " >> ${MAIL_BODY}
#echo " " >> ${MAIL_BODY}

echo "Regards. " >> ${MAIL_BODY}
echo " " >> ${MAIL_BODY}
cat ${MAIL_SGNTR} >> ${MAIL_BODY}

/usr/sbin/sendmail -v "${MAIL_LIST}" < ${MAIL_BODY}

## Clean up process files
rm -f ${MAIL_BODY} ${TEMP_FILE}.*

## Exit
exit 0
