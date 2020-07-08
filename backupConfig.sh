#!/bin/bash
set -u
#Backup given directories

#check correct number of arguments given
if [ "$#" -ne "6" ]
then
    echo -e "Not enough arguments\nUSAGE: ./$0 \"<list of directories to BACKUP (double quoted i.e. \"\'a\' \'b\' \'c\'\")>\" \"<list of directories to EXCLUDE (double quoted)>\" \"<directory to place first backup>\" \"<directory to place second backup>\" <period directory: 15min, hour, day, week, month> <delete backups older than this number of days (hours for 15mins and hours period)>\n You supplied ${#} arguments:"
    i=1
    for args in "${@}"
    do
      echo "ARG ${i}: [${args}]"
      let i++
    done
    exit 1
fi
declare -r precmd="eval"
declare -a toBackup #=( ${1//\'} )
declare -a toExclude #=( ${2/\'} )
eval "toBackup=($1)"
eval "toExclude=($2)"
declare destinationDirectory1=$3
declare destinationDirectory2=$4
declare period=$5
declare -i removeBackups=$6
declare -i retVal=0
declare -i exitStatus=0
declare excludeCmd=""

declare -r TIME=`date +%Y-%m-%d_%H-%M`
declare -r FILENAME="backup-${TIME}.tar.gz"        # Template for backup filename
declare -r DESTDIR="${destinationDirectory1}/${period}"  # Where to put backup files
declare -r DESTDIR2="${destinationDirectory2}/${period}" #where a copy of the backup will go
declare -r ERROR_INVALID_PERIOD=2
declare -r ERROR_SOURCE_DIRECTORY_DOES_NOT_EXIST=3
declare -r ERROR_SOURCE_IS_NOT_DIRECTORY=4
declare -r ERROR_CREATING_DEST1=5
declare -r ERROR_DEST1_NOT_DIRECTORY=6
declare -r ERROR_TAR_CREATION_FAILED=7
declare -r ERROR_CREATING_DEST2=8
declare -r ERROR_DEST2_NOT_DIRECTORY=9
declare -r ERROR_DEST2_COPY_FAILED=10
declare -r ERROR_BACKUP_REMOVAL_FAILED=11

if [ "${period}" != "15min" ] && [ "${period}" != "hour" ] && [ "${period}" != "day" ] && [ "${period}" != "week" ] && [ "${period}" != "month" ]
then
    echo -e "Incorrect period given [${period}]\nPlease use one of: 15min, hour, day, week, month. Defaulting to day.\nYou supplied: [$@]"
    period="day"
    exitStatus=${ERROR_INVALID_PERIOD}
fi

i=0
for directory in "${toBackup[@]}"
do
    if [ ! -e "${directory}" ]
    then
        echo -e "[${directory}] does not exist"
        unset toBackup[$i]
        #gaps in the array mess up indexing, remove them
        toBackup=( "${toBackup[@]}" )
        exitStatus=${ERROR_SOURCE_DIRECTORY_DOES_NOT_EXIST}
    else
        if [ ! -d "${directory}" ]
        then
            echo -e "[${directory}] is not a directory"
            ls -ald "${directory}"
            unset toBackup[$i]
            #gaps in the array mess up indexing, remove them
            toBackup=( "${toBackup[@]}" )
            exitStatus=${ERROR_SOURCE_IS_NOT_DIRECTORY}
        fi
    fi
    let i++
done

for directory in "${toExclude[@]}"
do
    excludeCmd="${excludeCmd} --exclude='${directory}'"
done

for directory in "${toBackup[@]}"
do
    if [ ! -e "${DESTDIR}" ]
    then
        ${precmd} sudo /bin/mkdir -p \"${DESTDIR}\"
        retVal=$?
        if [ "${retVal}" != "0" ]
        then
            echo "ERROR: Creating first destination directory [${DESTDIR}] with Error Code [${retVal}]"
            exit ${ERROR_CREATING_DEST1}
        fi
    else
        if [ ! -d "${DESTDIR}" ]
        then
            echo "ERROR: First Destination Directory is not a directory [${DESTDIR}]"
            ls -ald "${DESTDIR}"
            exit ${ERROR_DEST1_NOT_DIRECTORY}
        fi
    fi
#changed
    baseDir=$(basename "${directory}")
    ${precmd} "/bin/tar ${excludeCmd} -cpvzf" "\"${DESTDIR}/${baseDir}-${FILENAME}\" \"${directory}\"" \>"\"${DESTDIR}/${baseDir}-${FILENAME}.log\"" "2>&1"
    retVal=$?
    if [ "${retVal}" != "0" ] && [ "${retVal}" != "1" ] #an error code of 1 just means that files changed on disk which archiving, not really an error
    then
        echo "ERROR: TAR Failed to backup directory [${directory}] with error code [${retVal}].  Continuing, but consult log at [${DESTDIR}/${baseDir}-${FILENAME}.log]"
        exitStatus=${ERROR_TAR_CREATION_FAILED}
    fi

    if [ ! -e "${DESTDIR2}" ]
    then
        ${precmd} /bin/mkdir -p \"${DESTDIR2}\"
        retVal=$?
        if [ "${retVal}" != "0" ]
        then
            echo "ERROR: Creating second destination directory [${DESTDIR2}].  Error code [${retVal}]"
            exit ${ERROR_CREATING_DEST2}
        fi
    else
        if [ ! -d "${DESTDIR2}" ]
        then
            echo "ERROR: Second Destination Directory is not a directory [${DESTDIR2}]"
            ls -ald "${DESTDIR2}"
            exit ${ERROR_DEST2_NOT_DIRECTORY}
        fi
    fi
#changed
    ${precmd} rsync --size-only --inplace -a \"${DESTDIR}/${baseDir}-${FILENAME}\" \"${DESTDIR2}/${baseDir}-${FILENAME}\"
    retVal=$?
    if [ "${retVal}" != "0" ]
    then
        echo "ERROR: Failed to copy backup of directory [${directory}] to second backup location [${DESTDIR2}/${baseDir}-${FILENAME}] with Error Code [${retVal}].  Backup will continue, but please refer to any erro messages above."
        exitStatus=${ERROR_DEST2_COPY_FAILED}
    fi
done

if [ "${period}" == "15min" ] || [ "${period}" == "hour" ]
then
    let hours=${removeBackups}\*60
    ${precmd} /usr/bin/find \"${DESTDIR}\" -type f -name \"*.tar.gz\" -mmin +${hours} -exec \"rm -fr {};\"
    ${precmd} /usr/bin/find \"${DESTDIR2}\" -type f -name \"*.tar.gz\" -mmin +${hours} -exec \"rm -fr {};\"
    ${precmd} /usr/bin/find \"${DESTDIR}\" -type f -name \"*.log\" -mmin +${hours} -exec \"rm -fr {};\"
    ${precmd} /usr/bin/find \"${DESTDIR2}\" -type f -name \"*.log\" -mmin +${hours} -exec \"rm -fr {};\"
else
#changed
    ${precmd} /usr/bin/find \"${DESTDIR}\" -type f -name \"*.tar.gz\" -mtime +${removeBackups} -exec "rm -fr '{}' \\;"
    ${precmd} /usr/bin/find \"${DESTDIR2}\" -type f -name \"*.tar.gz\" -mtime +${removeBackups} -exec "rm -fr '{}' \\;"
    ${precmd} /usr/bin/find \"${DESTDIR}\" -type f -name \"*.log\" -mtime +${removeBackups} -exec "rm -fr '{}' \\;"
    ${precmd} /usr/bin/find \"${DESTDIR2}\" -type f -name \"*.log\" -mtime +${removeBackups} -exec "rm -fr '{}' \\;"
fi

exit ${exitStatus}
