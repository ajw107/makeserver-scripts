#!/usr/bin/env bash
#depencies:
# bash >4.4
# ls
# awk
# grep
# echo
# printf
# cat
# find
# wc
# sed
# cut
# basename
# dh
# tput
# lsblk
# column
# tail
# head
# *findmnt
# *smartctl
# *hddtemp
#entries with a * may not be installed by default on your distribution, the rest usually are, but always good to check

set -u
#trap "echo PROGRAM ERROR: a coding error occured!" ERR

######Import common functions and constants
commFuncFile="${HOME}/bin/commonfunctions"
if $(sudo test -e "${commFuncFile}")
then
    echo "Loading ${commFuncFile}..."
    . "${commFuncFile}"
fi

sudoCheck

######Initialise Variables
#grab sensitive values
secretsFile="${HOME}/secrets/$(basename --suffix=.sh "${BASH_SOURCE}")_secrets"
if $(sudo test -e "${secretsFile}")
then
    echo "Loading ${secretsFile}..."
    . "${secretsFile}"
fi

#USER CONFIGURABLE VARIABLES
declare -a DRIVE_CAGES=( "2" "4" "4" )
declare -a CAGE_NAMES=( "          ANTEC FAN" "${WHITE_BACKGROUND}${BLACK_TEXT}     WHITE EZDIY-FAB FAN       ${NORMAL_TEXT}" "${GREEN_BACKGROUND}${BLACK_TEXT}   VORTEX/GREEN EZDIY FAN     ${NORMAL_TEXT}" "${RED_BACKGROUND}${WHITE_TEXT}      RED EZDIY-FAB FAN        ${NORMAL_TEXT}" "${RED_BACKGROUND}${WHITE_TEXT}      RED EZDIY-FAB FAN      ${NORMAL_TEXT}" "${GREEN_BACKGROUND}${BLACK_TEXT}        GREEN EZDIY FAN        ${NORMAL_TEXT}" "            EMPTY             " "               LINDA           " "            EMPTY            " "${WHITE_BACKGROUND}${BLACK_TEXT}    WHITE EZDIY-FAB FAN       ${NORMAL_TEXT}" )

declare -i totalNumberOfPoolDrives=16
declare -i totalNumberOfRAIDDrives=${#ARRAY_SERIALS[@]}
declare -i totalNumberOfAllDrives=${#KNOWN_SERIALS[@]}
declare -r ignoreMountPoints=( "data" "parity" "individual_drives" )
declare -i NOTIFY=${TRUE}
declare -r MAX_DRIVE_TEMP=45
declare -r FULL_INFO=${FALSE}
declare -i DEBUG=${FALSE} #Originally set in commonfunctions
declare -r AMOUNT_OF_SERIAL_TO_SHOW_IN_TABLE=5
declare -r MIN_UPTIME=60
declare -r START_WAIT_TIME=10
declare -r RAID_FILESYSTEM_EXPECTED="ext4"
declare -i DRIVE_SPACE_THRESHOLD=90
declare -i CHECK_FILESYSTEM=${FALSE}
#END OF USER CONFIGURABLE VARIABLES

#DO NOT ALTER THESE
declare -r allDrivesLocation="/dev/disk/by-id"
declare -r allDrivesMatch="wwn-*"
declare -r allDrivesExclude="*part[0-9]*"
declare -r UNMOUNTED_DEVICE_MOUNTPOINT="/dev"
declare -A driveInfo=()
declare -i mountedDrives=0
declare -i hotDrives=0
#declare -r -i SUCCESS=0
#declare -r -i FAIL=-1
declare -i EXIT_STATUS=1
declare -r -i ERROR_TEXT=100
declare -r -i OK_TEXT=101
declare -r -i EMPHASISE_TEXT=102
declare -i raidError=${FALSE}
declare -r NO_MSG="No Message To Display"
declare videopoolHealthMsg="${NO_MSG}"
declare raidHealthMsg="${NO_MSG}"
declare raidDrivesMountedMsg="${NO_MSG}"
declare drivesPresentMsg="${NO_MSG}"
declare hotDrivesMsg="${NO_MSG}"
declare -r NO_ATA_VALUE_HBA="H"
declare -r NO_ATA_VALUE_SAS="S"
declare -r NO_ATA_VALUE="${ERROR_NORMAL_TEXT}${BLINK}⚠${NORMAL_TEXT}"
declare -i highestDriveTemp=0
declare highestTempMesg="${NO_MSG}"
declare -i drivesPresentStatus=${FALSE}
declare -i totalNumberOfArrayDrives=${#ARRAY_SERIALS[@]}
declare -i raidDrivesPresent=0
declare -r ataDataLabel="_ATA"
declare -r temperatureDataLabel="_TEMP"
declare -r driveLetterDataLabel="_DriveLetter"
declare -r driveTotalCapacityDataLabel="_SIZE"
declare -r driveUsedCapacityDataLabel="_USED"
declare -r driveFreeCapacityDataLabel="_FreeSize"
declare -r driveUsedPercentageDataLabel="_UsedPercent"
declare -r driveFileSystemDataLabel="_FS"
declare -r smartStatusDataLabel="_SmartHealth"
declare -r driveInterfaceDataLabel="_DriveInterface"
declare -r SMART_HEALTH_STATUS_TEXT="Health"
declare -r SMART_FAILED_SYMBOL="${ERROR_NORMAL_TEXT}${BLINK}✘${NORMAL_TEXT}"
declare -r SMART_OK_SYMBOL="${OK_NORMAL_TEXT}✔${NORMAL_TEXT}"
declare -r SMART_OK_1="PASSED"
declare -r SMART_OK_2="OK"
declare -i allDrivesSmart="${TRUE}"
declare -A poolInfo=()
declare -A raidInfo=()
declare dhInfo="${NO_MSG}"
declare poolSpaceMsg="${NO_MSG}"
declare raidSpaceMsg="${NO_MSG}"
declare raidFSMsg="${NO_MSG}"
declare -r FS_NO_VALUE="No value would make sense as it is a raid or btrfs member or is blank"
declare -r LINUX_RAID_FS_TYPE="linux_raid_member"
declare -r BTRFS_FS_TYPE="btrfs"
declare -r BLANK_FS_TYPE="Blank"
declare -r DRIVE_OFFLINE_FS_TYPE="Offline"
declare -r DRIVE_OFFLINE_TEXT="Drive Offline"
declare -r DRIVE_OFFLINE_ATA="Offline"
declare -r DRIVE_OFFLINE_TEMP="Offline"
declare -r DRIVE_OFFLINE_DRIVE_LETTER="Offline"
declare -r DRIVE_OFFLINE_CAPACITY="Offline"
declare -r DRIVE_OFFLINE_FREE_SPACE="Offline"
declare -r DRIVE_OFFLINE_USED_SPACE="Offline"
declare -r DRIVE_OFFLINE_USED_PERCENTAGE="Offline"
declare -r NO_SERIAL_NUMBER="NO SERIAL NUMBER"
declare -r NO_INTERFACE_TYPE="No Drive Interface Type"
declare -r SCSI_INTERFACE_TYPE="scsi"
declare -r SAS_INTERFACE_TYPE="sas"
declare -r UNKNOWN_SCSI_INTERFACE_TYPE="Unknown SCSI Interface Type"
declare -r SATA_INTERFACE_TYPE="ata"
declare -r SAT_INTERFACE_TYPE="sat"
declare -r TOUCHFILENAME="testdrives.touchfile"
declare -r PROG_NAME="TestDrives"
declare -r PROG_VER="1.0"
declare -r AUTHOR="Alex Wood"
declare -r AUTHOR_EMAIL="alex@alex-wood.org.uk"


# formatText <Text to print> <Type of formatting> <Invert and sometimes blink> <optional: surpress line endings>
function formatText ()
{
    local printCmd="printf '%s\n'"
    local messageText=${1}
    local typeOfFormatting=${2}
    local invertBlink=${3}
    local surpressNewLine=${4}

    if [ "${surpressNewLine}" == "${TRUE}" ]
        then
            printCmd="printf '%s'"
    fi
    if [ "${typeOfFormatting}" == "$ERROR_TEXT" ]
    then
        if [ "${invertBlink}" == "$TRUE" ]
        then
            eval "${printCmd} \"${NORMAL_TEXT}${ERROR_BLINK_TEXT}ERROR${ERROR_NORMAL_TEXT}${BOLD}: ${messageText}${NORMAL_TEXT}\""
             if [ "${NOTIFY}" == "${TRUE}" ]
             then
                 /home/alex/bin/pushover -T 'TheMatrix Disk Error!!!' -s persistent -m "${messageText}"
             fi
        else
            eval "${printCmd} \"${ERROR_NORMAL_TEXT}${messageText}${NORMAL_TEXT}\""
        fi
    elif [ "${typeOfFormatting}" == "$OK_TEXT" ]
    then
        if [ "${invertBlink}" == "$TRUE" ]
        then
            eval "${printCmd} \"${OK_BOLD_TEXT}${messageText}${NORMAL_TEXT}\""
        else
            eval "${printCmd} \"${OK_NORMAL_TEXT}${messageText}${NORMAL_TEXT}\""
        fi
    elif [ "${typeOfFormatting}" == "$EMPHASISE_TEXT" ]
    then
        if [ "${invertBlink}" == "$TRUE" ]
        then
            eval "${printCmd} \"${NORMAL_TEXT}${WHITE_BACKGROUND}${BLACK_TEXT}${BOLD}${messageText}${NORMAL_TEXT}\""
        else
            eval "${printCmd} \"${NORMAL_TEXT}${WHITE_TEXT}${UNDERLINE}${messageText}${NORMAL_TEXT}\""
        fi
    else
        eval "${printCmd} \"${NORMAL_TEXT}${messageText}\""
    fi
}

#gets the drive temperature driveTemp <drive device>
function driveTemp ()
{
    local temp=$(sudo smartctl --all ${1} | grep -i "Current Drive Temperature"| awk '{print $4}')
    if [ -z ${temp} ]
    then
        local temp=$(sudo smartctl --all ${1} | grep -i "Temperature_Celsius"| awk '{print $10}')
        if [ "${temp}" -gt "${highestDriveTemp}" ]
        then
            highestDriveTemp=${temp}
        fi
    fi
    echo "${temp}"
}

#only parameneter should be device id (e.g. sda)
#Returns: the ata#.00 of the drive
function getATA ()
{
    local driveLetter="${1}"
    local interfaceType="${2:-$(getDriveInterfaceType ${driveLetter})}"
    # save original IFS
    local OLDIFS="${IFS}"
    local Path
    local HostFull
    local HostMain
    local HostMid
    local HostSub
    local ID
    returnValue=""

    if [ "${interfaceType}" == "${SATA_INTERFACE_TYPE}" ]
    then
#        for i in $(ls -d /sys/block/sd*)
#        do
            ##/sys/block/sd* are links to ../devices/....
            ##this gets the link and uses it to build a path to the ata## folder
            #then pipes it into read to populate PATH (the path we've just created)
            #HOSTFULL a ##:#:# value and ID the drive letter
            readlink /sys/block/${driveLetter} |
                sed 's^\.\./devices^/sys/devices^ ;
                     s^/host[0-9]\{1,2\}/target^ ^ ;
                     s^/[0-9]\{1,2\}\(:[0-9]\)\{3\}/block/^ ^' \
            |
#            read Path HostFull ID
            while IFS=' ' read Path HostFull ID
            do
    #            debugEcho "PATH: [${Path}]"
    #            debugEcho "HostFull: [${HostFull}]"
                IFS=:
                local -a hostTemp=($HostFull)
    #            debugEcho "hostTemp: [${hostTemp[@]}]"
                if [ -v hostTemp ]
                then
                    if (( "${#hostTemp[@]}" > 0 ))
                    then
                        HostMain=${hostTemp[0]}
                    fi
                    if (( "${#hostTemp[@]}" > 1 ))
                    then
                        HostMid=${hostTemp[1]}
                    fi
                    if (( "${#hostTemp[@]}" > 2 ))
                    then
                        HostSub=${hostTemp[2]}
                    fi
                fi
#                debugEcho "HostMain: [${HostMain[*]}]"
#                debugEcho "HostMid: [${HostMid[*]}]"
#                debugEcho "HostSub: [${HostSub[*]}]"
#                debugEcho "ID: [${ID}]"
                if $(echo ${Path} | grep -q '/usb[0-9]*/')
                then
                    : #allows us to have no commands in this clause
    #                debugEcho "(Device $ID is not an ATA device, but a USB device [e. g. a pen drive])"
                elif $(echo ${Path} | grep -q '/expander-[0-9]')
                then
                     :
#                    debugEcho "ID: [${ID}]"
#                    if [ ! -z ${ID} ]
#                    then
    #                    ID=$(echo ${Path} | awk -F/ '{print $NF}')
#                        debugEcho "ID: [${ID}] Path: [${Path}]"

    #                    if [ "${ID}" == "${driveLetter}" ]
    #                    then
#                            echo "ATA on HBA"
    #                    fi
#                    else
                        #not an ATA on the expander, so probably a SAS on it
#                        if [ ! -z ${HostFull} ]
#                        then
#                            debugEcho "Device ${HostFull} is not an ATA device but a SAS device"
#                             echo "SAS"
#                        else
#                            ID=$(echo ${Path} | awk -F/ '{print $NF}')
#                            debugEcho "Device ${ID} is not an ATA device but a SAS device"
#                            echo "SAS"
#                        fi
#                    fi
                else
    #                debugEcho "ata$(< "${Path}/host${HostMain}/scsi_host/host${HostMain}/unique_id").${HostMid}${HostSub}"
    #                if [ ! -z ${ID} ]
    #                then
    #                   debugEcho "ID: [${ID}] DriveLetter: [${driveLetter}]"
    #                   if [ "${ID}" == "${driveLetter}" ]
   #                    then
#                           debugEcho "ata$(< "${Path}/host${HostMain}/scsi_host/host${HostMain}/unique_id").${HostMid}${HostSub}"
                            local ataFile=$(find "${Path}" -name unique_id)
                            local ataValue=$(cat "${ataFile}")
#                            debugEcho "${Path}"
#                            debugEcho "$(find ${Path} -name unique_id)"
#                            debugEcho "$(cat $(find ${Path} -name unique_id))"
                            retVal=$?
                            if (( ${retVal} != 0 ))
                            then
                                ataValue="${NO_ATA_VALUE}"
                            fi
                            if [ -z ${ataValue} ]
                            then
                                ataValue="${NO_ATA_VALUE}"
                            fi
                            echo "${ataValue}"
    #                    fi
#                    fi
                fi
            done
    elif [ "${interfaceType}" == "${SAT_INTERFACE_TYPE}" ]
    then
        echo "${NO_ATA_VALUE_HBA}"
    elif [ "${interfaceType}" == "${SAS_INTERFACE_TYPE}" ]
    then
        echo "${NO_ATA_VALUE_SAS}"
    else
        echo "${NO_ATA_VALUE}"
    fi

#   done
    # restore original IFS
    IFS="${OLDIFS}"
}

#pass the name of the associative array which is in the following format:
  #Use serial as the key for each drive in the array data structure
  #then add name of info to get full key/indecies:
    #<drive serial>${ataDataLabel} is ATA number
    #<drive serial>${driveLetterDataLabel} is drive letter in system i.e. sda
    #<drive serial>${temperatureDataLabel} is drive temperature
    #<drive serial>${driveTotalCapacityDataLabel} is total drive capacity
    #<drive serial>${driveUsedCapacityDataLabel} is used amount on non-raid drives
    #<drive serial>${driveFreeCapacityDataLabel} is free amount on non-raid drives
    #<drive serial>${driveUsedPercentageDataLabel} is used percent on non-raid drives
    #<drive serial>${driveFileSystemDataLabel} is the file system on the device for non-raid drives
    #<drive serial>${smartStatusDataLabel} is the general smart health of the drive as ${TRUE} or ${FALSE}
    #<drive serial>${driveInterfaceDataLabel} is the interface the drive connects to the computer on, such asSATA, SAT, SASD, SCSI
function drawDriveTemps ()
{
    local -n driveInfoArray=$1
    local cage_no=0
    local driveFSInfo="${NO_MSG}"
    local driveData="${NO_MSG}"
    for (( cage_row=1; cage_row<=${#DRIVE_CAGES[@]}; cage_row++ ))
    do
        local cage_sizes=""
        local tableData=""
        #loop first time to grab the headings and cage sizes
        for (( cage=1; cage<=${DRIVE_CAGES[((${cage_row}-1))]}; cage++ ))
        do
            local -n cage_array=DRIVE_CAGE${cage_row}_${cage}
            cage_sizes="${#cage_array[@]} ${cage_sizes}" # not all cages have the same number of drives in, find the one with the most
            if [ "${tableData}" != "" ]
            then
                tableData="${tableData},${BOLD}${CAGE_NAMES[((${cage_no}))]}${NORMAL_TEXT}" #whilst we're at it, grab the heading for this row of cages
            else
                tableData="${BOLD}${CAGE_NAMES[((${cage_no}))]}${NORMAL_TEXT}" #whilst we're at it, grab the heading for this row of cages
            fi
            let cage_no++
        done
        tableData="${tableData}\n" #new line for next row
        local max_cage_size_in_row=$(getMax ${cage_sizes})
        debugEcho "MAX: [${max_cage_size_in_row}] from [${cage_sizes}]"
        #we loop through drives first as the printTable functions print rows, not columns
        for (( drive=0; drive<${max_cage_size_in_row}; drive++ ))
        do
            for (( cage=1; cage<=${DRIVE_CAGES[((${cage_row}-1))]}; cage++ ))
            do
                local -n cage_array=DRIVE_CAGE${cage_row}_${cage}
                #some cages are not full, or have a different number of drives
                debugEcho "cage_array: [${#cage_array[@]}]  drive: [${drive}]"
                if (( ${#cage_array[@]} < ((${drive}+1)) ))
                then
                    if [[ "${tableData:(-2)}" == "\n" ]]
                    then
                        tableData="${tableData} "
                    else
                        tableData="${tableData}, "
                    fi
                    continue
                fi
                debugEcho "Cage Row: [${cage_row}] Cage: [${cage}] Drive: [${drive}]"
                #grab last 5 letters of serial
                local currentDriveSerial=${cage_array[${drive}]}
                local endSerial=${currentDriveSerial:(-${AMOUNT_OF_SERIAL_TO_SHOW_IN_TABLE})}
                #create the data
                debugEcho "Post Passed ARRAY Indices: [${!driveInfoArray[@]}]"
                debugEcho "Post Passed ARRAY Values: [${driveInfoArray[@]}]"
                debugEcho "currentDriveSerial: [${currentDriveSerial}]"
#                debugEcho "driveInfoArray[${currentDriveSerial}${temperatureDataLabel}]: [${driveInfoArray[${currentDriveSerial}${temperatureDataLabel}]}]"
                debugEcho "endSerial: [${endSerial}]"
                if [ "${driveInfoArray[${currentDriveSerial}${driveFileSystemDataLabel}]}" == "${DRIVE_OFFLINE_FS_TYPE}" ]
                then
                    driveFSInfo="${endSerial} ${DRIVE_OFFLINE_TEXT}"
                elif [ "${driveInfoArray[${currentDriveSerial}${driveFileSystemDataLabel}]}" == "${LINUX_RAID_FS_TYPE}" ]
                then
                    driveFSInfo="${driveInfoArray[${currentDriveSerial}${driveTotalCapacityDataLabel}]} RAID"
                elif [ "${driveInfoArray[${currentDriveSerial}${driveFileSystemDataLabel}]}" == "${BTRFS_FS_TYPE}" ]
                then
                    driveFSInfo="${driveInfoArray[${currentDriveSerial}${driveTotalCapacityDataLabel}]} BTRFS"
                elif [ "${driveInfoArray[${currentDriveSerial}${driveFileSystemDataLabel}]}" == "${BLANK_FS_TYPE}" ]
                then
                    driveFSInfo="${driveInfoArray[${currentDriveSerial}${driveTotalCapacityDataLabel}]} BLANK"
                else
                    #driveFSInfo="${driveInfoArray[${currentDriveSerial}${driveFreeCapacityDataLabel}]}/${driveInfoArray[${currentDriveSerial}${driveTotalCapacityDataLabel}]} ${driveInfoArray[${currentDriveSerial}${driveFileSystemDataLabel}]}"
                    driveFSInfo="${driveInfoArray[${currentDriveSerial}${driveTotalCapacityDataLabel}]}-${driveInfoArray[${currentDriveSerial}${driveUsedPercentageDataLabel}]}% ${driveInfoArray[${currentDriveSerial}${driveFileSystemDataLabel}]}"
                fi
                #don;t forget about blank drives, which won;t have any data with them
                if [ "${driveInfoArray[${currentDriveSerial}${driveFileSystemDataLabel}]}" == "${DRIVE_OFFLINE_FS_TYPE}" ]
                then
                    if [[ "${tableData:(-2)}" == "\n" ]]
                    then
                        tableData="${tableData}${ERROR_BLINK_TEXT} ${driveFSInfo} ${NORMAL_TEXT}"
                    else
                        tableData="${tableData},${ERROR_BLINK_TEXT} ${driveFSInfo} ${NORMAL_TEXT}"
                    fi
                else
                    local smartStatus="${SMART_FAILED_SYMBOL}"
                    if [ "${driveInfo[${currentDriveSerial}${smartStatusDataLabel}]}" == "${TRUE}" ]
                    then
                        smartStatus="${SMART_OK_SYMBOL}"
                    fi
                    #remove 'sd' from front of drive letter
                    driveData="${endSerial} ${smartStatus} ${driveInfoArray[${currentDriveSerial}${driveLetterDataLabel}]#sd} ${driveInfoArray[${currentDriveSerial}${ataDataLabel}]} ${driveFSInfo} ${driveInfoArray[${currentDriveSerial}${temperatureDataLabel}]}糖${NORMAL_TEXT}"
                    #${driveInfoArray[${currentDriveSerial}${driveUsedCapacityDataLabel}]} ${driveInfoArray[${currentDriveSerial}${driveFreeCapacityDataLabel}]}%
                    if [[ "${tableData:(-2)}" == "\n" ]]
                    then
                        if (( ${driveInfoArray[${currentDriveSerial}${temperatureDataLabel}]} < ${MAX_DRIVE_TEMP} ))
                        then
                            tableData="${tableData}${NORMAL_TEXT}${driveData}"
                        else
                            tableData="${tableData}${ERROR_BLINK_TEXT}${driveData}"
                        fi
                    else
                        if (( ${driveInfoArray[${currentDriveSerial}${temperatureDataLabel}]} >= ${MAX_DRIVE_TEMP} ))
                        then
                            tableData="${tableData},${ERROR_BLINK_TEXT}${driveData}"
                        else
                            tableData="${tableData},${NORMAL_TEXT}${driveData}"
                        fi
                    fi
                fi
                driveFSInfo="${NO_MSG}"
                driveData="${NO_MSG}"
            done
            tableData="${tableData}\n" #new line for next row
        done
        #draw a table for each row of cages
        debugEcho "TableData: [${tableData}]"
        printTable ',' "${tableData}"
    done
    #show the key
    formatText "KEY" ${OK_TEXT} ${TRUE} ${FALSE}
    formatText "Cell Values:" ${EMPHASISE_TEXT} ${TRUE} ${TRUE}
    printf " <Last ${AMOUNT_OF_SERIAL_TO_SHOW_IN_TABLE} Chars of Serial> <SMART Status [${SMART_OK_SYMBOL}]/[${SMART_FAILED_SYMBOL}]> <Letter (sdX)> <ATA Number> <Total Capacity-Space Used(%%)*> <FileSystem> <Temp>\n"
    printf "*Space used does not show in cases such as RAID, BTRFS or blank drives, where they would make no sense\n"
    formatText "ATA Value Key (when not a number):" ${EMPHASISE_TEXT} ${TRUE} ${TRUE}
    printf " '${NO_ATA_VALUE_HBA}': An ATA Drive on a HBA Card  '${NO_ATA_VALUE_SAS}': A SAS Drive  '${NO_ATA_VALUE}': Drive Interface Type and ATA value could not be determined\n"
}

#draws the status 'light' table
#Input is a list of parameters (type int) of status in the following format:
# <total number of pool drives> <number of pool drives actually mounted>
# <${TRUE} if all known drives are present ${FALSE} if not> <${TRUE} if Array is Healthy and ${FALSE} if degraded>
# <total number of Array drives> <number of Array drives actually present> <maximum temperature a drive should be>
# <temperature of hottest drive>  <Percantage of used space on pool> <Actual used space on pool> <Total space on pool>
# <percentage of used space on raid> <Actual used space on raid> <Total space on raid> <Highest used space percentage advised>
# <${TRUE} if nofiication are on ${FALSE} if off>  <${TRUE} if nofiication are on ${FALSE} if off>
# <${TRUE} if all drives have a healthy smart status, ${FALSE} if one or more does not>
function drawStatusTable()
{
    local tableData="${BOLD}Pool Drives${NORMAL_TEXT},${BOLD}Known Drives${NORMAL_TEXT},${BOLD}Array Status${NORMAL_TEXT},${BOLD}Array Drives${NORMAL_TEXT},${BOLD}SMART${NORMAL_TEXT},${BOLD}Hottest Drive${NORMAL_TEXT},${BOLD}Notify${NORMAL_TEXT},${BOLD}Pool Used${NORMAL_TEXT},${BOLD}Raid Used${NORMAL_TEXT}\n"
    local -i totalPoolDrives=${1}
    local -i mountedPoolDrives=${2}
    local -i knownDrives=${3}
    local -i arrayStatus=${4}
    local -i totalArrayDrives=${5}
    local -i presentArrayDrives=${6}
    local -i maximumDriveTemp=${7}
    local -i hottestDrive=${8}
    local -i poolSpacePercent=${9}
    local poolSpaceActual=${10}
    local poolSpaceTotal=${11}
    local -i raidSpacePercent=${12}
    local raidSpaceActual=${13}
    local raidSpaceTotal=${14}
    local -i spaceThreashold=${15}
    local -i notifyStatus=${16}
    local -i smartStatus=${17}

    #local errorText="${RED_BACKGROUND}${WHITE_TEXT}${BOLD}${BLINK}"
    #local okayText="${GREEN_BACKGROUND}${BLUE_TEXT}${BOLD}"

    if [ "${totalPoolDrives}" == "${mountedPoolDrives}" ]
    then
        tableData="${tableData}${OK_BOLD_TEXT}[${mountedPoolDrives}/${totalPoolDrives}]${NORMAL_TEXT},"
    else
        tableData="${tableData}${ERROR_BLINK_TEXT}[${mountedPoolDrives}/${totalPoolDrives}]${NORMAL_TEXT},"
    fi

    if [ "${knownDrives}" == "${TRUE}" ]
    then
        tableData="${tableData}${OK_BOLD_TEXT}All Present${NORMAL_TEXT},"
    else
        tableData="${tableData}${ERROR_BLINK_TEXT}Drives Missing${NORMAL_TEXT},"
    fi

    if [ "${arrayStatus}" == "${TRUE}" ]
    then
        tableData="${tableData}${OK_BOLD_TEXT}Healthy${NORMAL_TEXT},"
    else
        tableData="${tableData}${ERROR_BLINK_TEXT}Degraded${NORMAL_TEXT},"
    fi

    if [ "${totalArrayDrives}" == "${presentArrayDrives}" ]
    then
        tableData="${tableData}${OK_BOLD_TEXT}[${presentArrayDrives}/${totalArrayDrives}]${NORMAL_TEXT},"
    else
        tableData="${tableData}${ERROR_BLINK_TEXT}[${presentArrayDrives}/${totalArrayDrives}]${NORMAL_TEXT},"
    fi

    if [ "${smartStatus}" == "${TRUE}" ]
    then
        tableData="${tableData}${OK_BOLD_TEXT}Healthy${NORMAL_TEXT},"
    else
        tableData="${tableData}${ERROR_BLINK_TEXT}Failed${NORMAL_TEXT},"
    fi

    if (( ${hottestDrive} <= ${maximumDriveTemp} ))
    then
        tableData="${tableData}${OK_BOLD_TEXT}${hottestDrive}糖${NORMAL_TEXT},"
    else
        tableData="${tableData}${ERROR_BLINK_TEXT}${hottestDrive}糖${NORMAL_TEXT},"
    fi

    if [ "${notifyStatus}" == "${TRUE}" ]
    then
        tableData="${tableData}${OK_BOLD_TEXT}ON${NORMAL_TEXT},"
    else
        tableData="${tableData}${ERROR_BLINK_TEXT}OFF${NORMAL_TEXT},"
    fi

    if (( ${poolSpacePercent} <= ${spaceThreashold} ))
    then
        tableData="${tableData}${OK_BOLD_TEXT}${poolSpacePercent}% (${poolSpaceActual}/${poolSpaceTotal})${NORMAL_TEXT},"
    else
        tableData="${tableData}${ERROR_BLINK_TEXT}${poolSpacePercent}% (${poolSpaceActual}/${poolSpaceTotal})${NORMAL_TEXT},"
    fi

    if (( ${raidSpacePercent} <= ${spaceThreashold} ))
    then
        tableData="${tableData}${OK_BOLD_TEXT}${raidSpacePercent}% (${raidSpaceActual}/${raidSpaceTotal})${NORMAL_TEXT}"
    else
        tableData="${tableData}${ERROR_BLINK_TEXT}${raidSpacePercent}% (${raidSpaceActual}/${raidSpaceTotal})${NORMAL_TEXT}"
    fi

    printTable ',' "${tableData}"
}

#usage checkUptime <minimum time>
#returns = current uptime in seconds int
#          $? true if system has been up for more than <minimum time> seconds
function checkUptime ()
{
    local minTime=${1}
    local upTime=$(cat /proc/uptime | awk '{print $1;}')
    debugEcho "upTime float: [${upTime}]"
    #convert-ish to int
    upTime=$(printf "%.0f" ${upTime})
    echo ${upTime}

    local retValue=${FALSE}

    debugEcho "System has been on for [${upTime}] seconds, testing against [${minTime}] seconds"

    if [ "${upTime}" -ge "${minTime}" ]
    then
        retValue=${TRUE}
        debugEcho "System has been on for more than [${minTime}] seconds."
    fi
    return ${retValue}
}

#takes the mount point ddirectory as an argument
function checkMount()
{
    local mountPoint="${1}"
    local tempFile

    mountpoint "${mountPoint}" &> /dev/null
    retVal=$?
    if [ "${retVal}" != "0" ] && [ "${retVal}" != "1" ]
    then
        formatText "[${retVal}]: [${drivename}] is not mounted" ${ERROR_TEXT} ${TRUE} ${FALSE}
        grep "${mountPoint}" "${fstabLocation}"
        return ${ERROR_DEVICE_NOT_MOUNTED}
    elif [ "${retVal}" != "1" ]
    then
        readStatus=$(findmnt "${mountPoint}" | awk '{print $4}' | grep "ro,")
        if [ ! -z ${readStatus} ]
        then
            formatText "[${mountPoint}] is mounted READ-ONLY" ${ERROR_TEXT} ${TRUE} ${FALSE}
            findmnt "${mountPoint}"
        fi
        ls -al "${mountPoint}" &> /dev/null
        retVal=$?
        if [ "${retVal}" != "0" ]
        then
            formatText "[${retVal}]: [${mountPoint}] is not responding" ${ERROR_TEXT} ${TRUE} ${FALSE}
            grep "${mountPoint}" "${fstabLocation}"
            return ${ERROR_DRIVE_NOT_RESPONDING}
        fi
        tempFile=$(sudo mktemp -p "${mountPoint}")
        retVal=$?
        if [ "${retVal}" != "0" ]
        then
            formatText "[${retVal}]: [${mountPoint}] is not writable but is mounted writable" ${ERROR_TEXT} ${TRUE} ${FALSE}
            grep "${mountPoint}" "${fstabLocation}"
            sudo rm -f "${tempFile}"
            return ${ERROR_DRIVE_NOT_RESPONDING}
        fi
        findmnt | sudo dd conv=fdatasync oflag=direct status=none of="${tempFile}"
        if [ "${retVal}" != "0" ]
        then
            formatText "[${retVal}]: [${mountPoint}] is not writable but is mounted writable" ${ERROR_TEXT} ${TRUE} ${FALSE}
            grep "${mountPoint}" "${fstabLocation}"
            sudo rm -f "${tempFile}"
            return ${ERROR_DRIVE_NOT_RESPONDING}
        fi
        sudo rm -f "${tempFile}"
        if [ "${retVal}" != "0" ]
        then
            formatText "[${retVal}]: [${mountPoint}] is not writable but is mounted writable" ${ERROR_TEXT} ${TRUE} ${FALSE}
            grep "${mountPoint}" "${fstabLocation}"
            sudo rm -f "${tempFile}"
            return ${ERROR_DRIVE_NOT_RESPONDING}
        fi
    fi
    return ${SUCCESS}
}

#pass serial number and drive info aray name
#not temp is returned as an error code as stdout could be full of messages
function getDriveTemp()
{
    local serialNumber="${1}"
    local -n driveInfoArrayTemp=${2}

    local driveLetter="${driveInfoArrayTemp[${serialNumber}${driveLetterDataLabel}]}"
    local temp

#   temp=$(driveTemp "${driveLetter}")
    temp=$(sudo hddtemp "/dev/${driveLetter}" | awk '{print $NF}')
    temp=${temp/°C}
    [ ! -z "${temp}" ] && [ "${temp}" -eq "${temp}" ] 2>/dev/null #make sure it's not null and is a number
    if [ "$?" -eq "0" ]
    then
#        debugEcho "[${serialNumber}] [${driveLetter}] TEMP: [${temp}]"
#        debugEcho "Drive Temp: [${temp}]"
        if (( ${temp} > ${highestDriveTemp} ))
        then
            highestDriveTemp=${temp}
        fi
        if (( ${temp} >= ${MAX_DRIVE_TEMP} ))
        then
            if [ "${FULL_INFO}" == "${TRUE}" ]
            then
                if [ "${driveInfoArrayTemp["${serialNumber}${ataDataLabel}"]}" != "${NO_ATA_VALUE_HBA}" ] && [ "${driveInfoArrayTemp["${serialNumber}${ataDataLabel}"]}" != "${NO_ATA_VALUE_SAS}" ]
                then
                    formatText "WARNING: ATA Drive ${serialNumber} [/dev/${driveLetter}] ATA[${driveInfoArrayTemp["${serialNumber}${ataDataLabel}"]}] is too hot [${temp}糖]" ${ERROR_TEXT} ${FALSE} ${FALSE}
                else
                    formatText "WARNING: SAS Drive ${serialNumber} [/dev/${driveLetter}] is too hot [${temp}糖]" ${ERROR_TEXT} ${FALSE} ${FALSE}
                fi
            fi
            let hotDrives++
        else
            if [ "${FULL_INFO}" == "${TRUE}" ]
            then
                if [ "${driveInfoArrayTemp[${serialNumber}${ataDataLabel}]}" != "${NO_ATA_VALUE_HBA}" ] && [
"${driveInfoArrayTemp["${serialNumber}${ataDataLabel}"]}" != "${NO_ATA_VALUE_SAS}" ]
                then
                    formatText "ATA Drive ${serialNumber} [/dev/${driveLetter}] ATA[${driveInfoArrayTemp["${serialNumber}${ataDataLabel}"]}] is fine [${temp}糖]" ${OK_TEXT} ${FALSE} ${FALSE}
                else
                    formatText "SAS Drive ${serialNumber} [/dev/${driveLetter}] is fine [${temp}糖]" ${OK_TEXT} ${FALSE} ${FALSE}
                fi
            fi
        fi
    else
        #a bad temp was returned
        return ${ERROR_BAD_DRIVE_TEMP}
    fi
    return ${temp}
}

function getFSInfo()
{
    local serialNumber="${1}"
    local -n driveInfoArrayFS=${2}

    local driveLetter="${driveInfoArrayFS["${serialNumber}${driveLetterDataLabel}"]}"

    #Grab File System info, filtering out RAID, BTRFS and Blank disks which have only the total capacity
    #first test to see if a drive is mounted
    if [ "$(df --output="target" /dev/${driveLetter} | awk 'END{print $1}')" == "${UNMOUNTED_DEVICE_MOUNTPOINT}" ]
    then
        #if it is, try and mount each partition until one actually mounts (only mount read-only as only grabbing ifo from it)
        for partition in $(ls /dev/${driveLetter}*)
        do
            local tempMount=$(mktemp -d)
            sudo mount -o ro ${partition} "${tempMount}" &> /dev/null #it will return lots of errors until it finds a parittion it can mount
            retVal=$?
            if (( retVal != 0 ))
            then
                 continue
            fi
            dhInfo=$(df -h ${partition} | awk 'END{print $2,$3,$4,$5}')
            #echo -e "${dhInfo}"
            #read i
            sudo umount ${tempMount}
            rm -rf ${tempMount}
        done
    else
        #it's already mounted, just continue as normal
        dhInfo=$(df -h /dev/${driveLetter} | awk 'END{print $2,$3,$4,$5}')
    fi
    #the end result will be the LAST partition will be the one we get the info from

    #grab all filesystems on all partition of the drive, but only return the last one (have to choose one)
    #this allows drives with just one partition but forced to use sdX# to have a value.  As a side-effect
    #the raid array will be listed as a dependency, so filter out that
    local fileSystem=$(sudo lsblk --output="FSTYPE" --noheadings /dev/${driveLetter} | tr -d [:space:] | awk 'END{print $1}' )
    if [[ "${fileSystem}" == *"${LINUX_RAID_FS_TYPE}"* ]]
    then
        driveInfoArrayFS["${serialNumber}${driveFileSystemDataLabel}"]="${LINUX_RAID_FS_TYPE}"
    else
        driveInfoArrayFS["${serialNumber}${driveFileSystemDataLabel}"]="${fileSystem}"
    fi
    if [ "${driveInfoArrayFS["${serialNumber}${driveFileSystemDataLabel}"]}" == "" ]
    then
        driveInfoArrayFS["${serialNumber}${driveFileSystemDataLabel}"]=${BLANK_FS_TYPE}
    fi
    if [ "${driveInfoArrayFS["${serialNumber}${driveFileSystemDataLabel}"]}" != "${LINUX_RAID_FS_TYPE}" ] && [ "${driveInfoArrayFS["${serialNumber}${driveFileSystemDataLabel}"]}" != "${BTRFS_FS_TYPE}" ] && [ "${driveInfoArrayFS["${serialNumber}${driveFileSystemDataLabel}"]}" != "${BLANK_FS_TYPE}" ]
    then
        driveInfoArrayFS["${serialNumber}${driveTotalCapacityDataLabel}"]=$(awk '{print $1}' <<<${dhInfo})
        driveInfoArrayFS["${serialNumber}${driveUsedCapacityDataLabel}"]=$(awk '{print $2}' <<<${dhInfo})
        driveInfoArrayFS["${serialNumber}${driveFreeCapacityDataLabel}"]=$(awk '{print $3}' <<<${dhInfo})
        driveInfoArrayFS["${serialNumber}${driveUsedPercentageDataLabel}"]=$(awk '{print $4}' <<<${dhInfo} | cut --delimiter=% --fields=1)

        #if a disk check has been requested, do it here, as this disk should have a valid file system
        if [ "${CHECK_FILESYSTEM}" == "${TRUE}" ]
        then
            diskCheck ${driveLetter}
        fi
    else
        driveInfoArrayFS["${serialNumber}${driveTotalCapacityDataLabel}"]=$(lsblk --nodeps /dev/${driveLetter} | awk 'END{print $4}')
        driveInfoArrayFS["${serialNumber}${driveUsedCapacityDataLabel}"]="${FS_NO_VALUE}"
        driveInfoArrayFS["${serialNumber}${driveFreeCapacityDataLabel}"]="${FS_NO_VALUE}"
        driveInfoArrayFS["${serialNumber}${driveUsedPercentageDataLabel}"]="${FS_NO_VALUE}"
    fi
}

#pass the drive letter
function getDriveInterfaceType ()
{
    local driveLetter="${1}"

    #sat MUST come before scsi as a sat drive will also be identified as a scsi drive (it's on the same HBA after all)
    local -a deviceTypes=( "${SATA_INTERFACE_TYPE}" "${SAT_INTERFACE_TYPE}" "${SCSI_INTERFACE_TYPE}" )
    local driveInfo=""
    local interfaceType="${NO_INTERFACE_TYPE}"

    #grab smart info for the drive, smartctl will return an error if we
    #select the wrong device type, giving us a way to identify the device type
    for type in ${deviceTypes[*]}
    do
#        debugEcho "type: [${type}]"
        driveInfo="$(sudo smartctl -d ${type} -i /dev/${driveLetter})"
        #only break the cycle if we find the type, signified by no error from smartctl
        retVal=$?
        if (( ${retVal} == 0 ))
        then
            #got the right type
            interfaceType="${type}"
#            debugEcho "type: [${interfaceType}]"
            break
        fi
    done

    ##double check if scsi type is SAS
    if [ "${interfaceType}" == "${SCSI_INTERFACE_TYPE}" ]
    then
        ##remember smartctl will output it in uppercase
        if [ "$(echo "${driveInfo}" | grep "Transport protocol:" | awk -F: '{print $2}'| tr -d [:space:] | cut -c -3)" == "${SAS_INTERFACE_TYPE^^}" ]
        then
            interfaceType="${SAS_INTERFACE_TYPE}"
        else
            interfaceType="${UNKNOWN_SCSI_INTERFACE_TYPE}"
        fi
    fi
    echo "${interfaceType}"
}

#pass the drive letter
function getSmartStatus
{
    local driveLetter="${1}"

    #get SMART health status
#    smartHealth=$(sudo smartctl -H /dev/${driveLetter} | tail -2 | head -1 | awk 'END {print $NF}')
    smartHealth=$(sudo smartctl -H /dev/${driveLetter} | grep -i "${SMART_HEALTH_STATUS_TEXT}" | awk 'END {print $NF}')
    if [ "${smartHealth}" == "${SMART_OK_1}" ] || [ "${smartHealth}" == "${SMART_OK_2}" ]
    then
        echo "${TRUE}"
    else
        echo "${FALSE}"
        allDrivesSmart="${FALSE}"
    fi

}

#pass in the drive path (path to device)
function getDriveLetter()
{
    local diskID="${1}"

    ls -al ${diskID} | awk '{print $NF}' | awk -F/ '{print $NF}'
}

#pass in the drive path (path to device) and name of array to populate with info
#no idea why, but even though the array is passed by reference, the values set in
#the array only have a scope of the function itself, and so the array remains unmodified
#outside the function, whereas getFSInfo does the same thing and the array holds on 
#to the new values outside it's function
function getSerial()
{
    local diskID="${1}"
#    local -n driveInfoArraySerial=${2}

    local info
    local scsiSerial
    local serialNumber="${NO_SERIAL_NUMBER}"

#    info=`udevadm info --query=all --name=${diskID} | grep SERIAL`
###  got a better and more realiable way of getting the serial number
###    serialNumber=`udevadm info --query=all --name=${diskID} | grep SCSI_IDENT_SERIAL`
###    serialNumber=${serialNumber#*=}
     serialNumber="$(sudo sginfo -s ${diskID} | grep "Serial" | awk -F "'" '{ print $((NF-1)) }' | tr -d ' ')"


#    echo "diskID: ${diskID}"
#    echo "info: ${info}"
#    printf "diskID: %s" "${diskID}"
#    printf "info: %s" "${info}"
#    scsiSerial=`echo $info | grep -o [^\ ]*SCSI[^\ ]*`
#    echo "scsiSerial: ${scsiSerial}"
    #populate drive info
    #first we have to use different methods to get serial number for SAS or ATA drives
    #also SAS drives don't have an ATA number, only ATA drives have this

#####what joy, as of ubuntu 19.04 udev now reports all drives as having a scsi serial number
#####so all of this wouldn't work properly anyway

#    if [ ! -z ${scsiSerial} ]
#    then
#        serialNumber=${scsiSerial#*=}
#        debugEcho "SCSI serialNumber: [${serialNumber}]"
##        if [ ! -z "${serialNumber}" ]
##        then
##            driveInfoArraySerial["${serialNumber}${driveLetterDataLabel}"]=$(getDriveLetter "${diskID}")
##            driveInfoArraySerial["${serialNumber}${ataDataLabel}"]="${NO_ATA_VALUE_SAS}"
##        fi
#    else
#        serialNumber=`echo $info | grep -o [^\ ]*SERIAL=[^\ ]*`
#        serialNumber=${serialNumber#*=}
#        debugEcho "ATA serialNumber: [${serialNumber}]"
##        if [ ! -z "${serialNumber}" ]
##        then
##            driveInfoArraySerial["${serialNumber}${driveLetterDataLabel}"]=$(getDriveLetter "${diskID}")
##            driveInfoArraySerial["${serialNumber}${ataDataLabel}"]=$(getATA ${driveInfoArray["${serialNumber}${driveLetterDataLabel}"]})
##        fi
#    fi
    if [ ! -z "${serialNumber}" ]
    then
##        if [ "${driveInfoArraySerial[${serialNumber}${ataDataLabel}]}" == "" ]
##        then
##            driveInfoArraySerial[${serialNumber}${ataDataLabel}]="${NO_ATA_VALUE_HBA}"
##        fi
        echo "${serialNumber}"
    else
        echo "${NO_SERIAL_NUMBER}"
    fi
#    debugEcho "ata: [${driveInfoArraySerial["${serialNumber}${ataDataLabel}"]}]"
#    printf "getSerial driveinfoarrayserial\n"
#    for i in "${!driveInfoArraySerial[@]}"
#    do
#        stdbuf -o0 printf "key  : %s\n" "$i"
#        stdbuf -o0 printf "value: %s\n" "${driveInfoArraySerial[$i]}"
#    done
}

#pass in the drive path (path to device) and name of array to populate with info
function getDriveInfo
{
    local diskID="${1}"
#    stdbuf -o0 printf "Array name: %s\n" "${2}"
    local -n driveInfoArray=${2}

    local serialNumber

    serialNumber=$(getSerial "${diskID}" "driveInfoArray")
#    stdbuf -o0 printf "Array size: %d\n" ${#driveInfoArray[@]}
#    exit
#    read -p "size ${#driveInfo[@]}" i
    if [ -v serialNumber ]
    then
#        debugEcho "serial: [${serialNumber}]"
#        printf "getDriveInfo (pre-smart) driveinfoarray\n"
#        for i in "${!driveInfoArray[@]}"
#        do
#            stdbuf -o0 printf "key  : %s\n" "$i"
#            stdbuf -o0 printf "value: %s\n" "${driveInfoArray[$i]}"
#        done
#        debugEcho "array parsing done"
        driveInfoArray["${serialNumber}${driveLetterDataLabel}"]=$(getDriveLetter "${diskID}")
        driveInfoArray["${serialNumber}${driveInterfaceDataLabel}"]=$(getDriveInterfaceType "${driveInfoArray["${serialNumber}${driveLetterDataLabel}"]}")
        driveInfoArray["${serialNumber}${ataDataLabel}"]=$(getATA "${driveInfoArray["${serialNumber}${driveLetterDataLabel}"]}")
#        debugEcho "letter: [${driveInfoArray["${serialNumber}${driveLetterDataLabel}"]}]"
#        debugEcho "ata: [${driveInfoArray["${serialNumber}${ataDataLabel}"]}]"
        driveInfoArray[${serialNumber}${smartStatusDataLabel}]=$(getSmartStatus "${driveInfoArray["${serialNumber}${driveLetterDataLabel}"]}")
        getFSInfo "${serialNumber}" "driveInfoArray"
        getDriveTemp "${serialNumber}" "driveInfoArray"
        retVal=$?
        if (( ${retVal} != ${ERROR_BAD_DRIVE_TEMP} ))
        then
            driveInfoArray[${serialNumber}${temperatureDataLabel}]=${retVal}
        fi
    else
        serialNumber="${NO_SERIAL_NUMBER}"
    fi
    echo "${serialNumber}"
#    printf "getDriveInfo (end) driveinfoarray\n"
#    for i in "${!driveInfoArray[@]}"
#    do
#        stdbuf -o0 printf "key  : %s\n" "$i"
#        stdbuf -o0 printf "value: %s\n" "${driveInfoArray[$i]}"
#    done
}

#gets the Filesystem information for the whole Pool/RAID.  Pass the pool/raidInfo array name, the mount point and pool/raid message String variable name
function getBlockFSInfo()
{
    local -n blockInfoArray=${1}
    local blockMountPoint="${2}"
    local -n blockSpaceMsgVar=${3}
    local deviceType="${4}"

    local msg
    local msgStart
    local dhInfo

    dhInfo=$(df -Th ${blockMountPoint} | awk 'END{print $2,$3,$4,$5,$6}')
#    debugEcho "dhInfo: [${dhInfo}]"
    blockInfoArray["${driveTotalCapacityDataLabel}"]=$(awk '{print $2}' <<<${dhInfo})
    blockInfoArray["${driveUsedCapacityDataLabel}"]=$(awk '{print $3}' <<<${dhInfo})
    blockInfoArray["${driveFreeCapacityDataLabel}"]=$(awk '{print $4}' <<<${dhInfo})
    blockInfoArray["${driveUsedPercentageDataLabel}"]=$(awk '{print $5}' <<<${dhInfo} | cut --delimiter=% --fields=1)
    blockInfoArray["${driveFileSystemDataLabel}"]=$(awk '{print $1}' <<<${dhInfo})

    for x in "${!blockInfoArray[@]}"
    do
        debugEcho "[%q]=%q\n" "$x" "${blockInfoArray[$x]}"
    done

    msg=": Filesystem [${blockInfoArray[${driveFileSystemDataLabel}]}], Total Capacity [${blockInfoArray[${driveTotalCapacityDataLabel}]}], "
    #echo "pre space threashold check msg: [${msg}]"
    if (( ${blockInfoArray["${driveUsedPercentageDataLabel}"]} <= ${DRIVE_SPACE_THRESHOLD} ))
    then
        msgStart="${OK_BOLD_TEXT}${deviceType} ${blockMountPoint}${NORMAL_TEXT}"
        #echo "post space threashold check msgStart: [${msgStart}]"
        msg="${msgStart}${msg}Used [${blockInfoArray[${driveUsedPercentageDataLabel}]}%%], Free [${blockInfoArray[${driveFreeCapacityDataLabel}]}]"
        #echo "post start applied msg: [${msg}]"
        msg="${msg}${NORMAL_TEXT}\n"
        blockSpaceMsgVar="${msg}"
        #echo "post end applied msg: [${msg}]"
        printf "${msg}"
    else
        msgStart="${ERROR_BLINK_TEXT}${deviceType} ${blockMountPoint}${NORMAL_TEXT}"
        msg="${msgStart}${msg}${ERROR_BLINK_TEXT}Used [${blockInfoArray[${driveUsedPercentageDataLabel}]}%% (>${DRIVE_SPACE_THRESHOLD}%%)]${NORMAL_TEXT}, Free [${blockInfoArray[${driveFreeCapacityDataLabel}]}]"
        msg="${msg}${NORMAL_TEXT}\n"
        blockSpaceMsgVar="${msg}"
        printf "${msg}"
    fi
}

function diskCheck ()
{
    local driveLetter=$1
    warnText "Checking Filesystem on Drive [${driveLetter}]"
    sudo umount -f /dev/${driveLetter}
    retVal=$?
    if (( ${retVal} != 0 ))
    then
        warnText "Unable to unmount ${driveLetter} with exit code [${retVal}]"
        #exit ${ERROR_FSCK_FAILED}
    fi
    sudo fsck -fvy /dev/${driveLetter}
    retVal=$?
    if (( ${retVal} != 0 ))
    then
        warnText "FileSystem Check failed with exit code [${retVal}]"
        #exit ${ERROR_FSCK_FAILED}
    fi
    sudo mount /dev/${driveLetter}
    retVal=$?
    if (( ${retVal} != 0 ))
    then
        warnText "Unable to re-mount ${driveLetter} after filesystem check with exit code [${retVal}]"
        #exit ${ERROR_FSCK_FAILED}
    fi
}

infoText "MAIN CODE START [${PROG_NAME} v${PROG_VER} by ${AUTHOR} (${AUTHOR_EMAIL})]" ${INFO_TEXT_MISC_NO_DOTS}
sudoCheck
sysUpTime=$(checkUptime ${MIN_UPTIME})
retValue=$?
oldNotify=${NOTIFY}
NOTIFY=${FALSE}
while [ ${retValue} == ${FALSE} ]
do
    infoText "System has been up for ${sysUpTime}s, not ${MIN_UPTIME}s waiting ${START_WAIT_TIME} secs" ${INFO_TEXT_MISC}
    sleep ${START_WAIT_TIME}s
    sysUpTime=$(checkUptime ${MIN_UPTIME})
    retValue=$?
done
NOTIFY=${oldNotify}

formatText "SnapRAID/Merger Drives" ${EMPHASISE_TEXT} ${FALSE} ${FALSE}

infoText "Checking all Pool Mountpoints" ${INFO_TEXT_MISC}
for dirs in $(find "${poolDrivesRootMountPoint}" -xdev -type d)
do
    drivename=$(basename "${dirs}")
    debugEcho "drivename: [${drivename}]"
    debugEcho "ignoreMountPoints: ${ignoreMountPoints[*]}"
    $(isInArray "${drivename}" "ignoreMountPoints" >/dev/null)
    retVal=$?
    #only process drives NOT in the ignoredMountPoint list
    if [ "${retVal}" != "${SUCCESS}" ]
    then
        printf '\r%b' "${CLEAR_LINE}"
        printf "${dirs}"
        checkMount "${dirs}"
        retValue=$?
        if (( ${retValue} == ${SUCCESS} ))
        then
            let mountedDrives++
            printf "${OK_NORMAL_TEXT}✔${NORMAL_TEXT} "
        else
            printf "${ERROR_NORMAL_TEXT}$(basename ${disk})⚠${NORMAL_TEXT}\n"
            formatText "There is a problem with mount point [${dirs}]." ${ERROR_TEXT} ${TRUE} ${FALSE}
        fi
    fi
done
printf "\n"
if [ "${mountedDrives}" == "${totalNumberOfPoolDrives}" ]
then
    formatText "[${mountedDrives}/${totalNumberOfPoolDrives}] Pool drives mounted" ${OK_TEXT} ${FALSE} ${FALSE}
    videopoolHealthMsg="${OK_BOLD_TEXT}[${mountedDrives}/${totalNumberOfPoolDrives}] Pool drives mounted${NORMAL_TEXT}"
    EXIT_STATUS=0
else
    formatText "[${ERROR_NORMAL_TEXT}${mountedDrives}${OK_NORMAL_TEXT}/${totalNumberOfPoolDrives}] Pool drives mounted" ${OK_TEXT} ${FALSE} ${FALSE}
    videopoolHealthMsg="${ERROR_BLINK_TEXT}[${mountedDrives}/${totalNumberOfPoolDrives}] Pool drives mounted${NORMAL_TEXT}"
    EXIT_STATUS=1
fi

infoText "Checking All Drives" ${INFO_TEXT_MISC}
#check all known drive serials are present
for disk in $(find ${allDrivesLocation} -maxdepth 1 -iname "${allDrivesMatch}" -not -name "${allDrivesExclude}")
do
    #Use serial as the key for each drive in the driveInfo data structure
    #then add name of info to get full key/indecies:
    #<drive serial>${ataDataLabel} is ATA number
    #<drive serial>${driveLetterDataLabel} is drive letter in system i.e. sda
    #<drive serial>${temperatureDataLabel} is drive temperature
    #<drive serial>${driveTotalCapacityDataLabel} is total drive capacity
    #<drive serial>${driveUsedCapacityDataLabel} is used amount on non-raid drives
    #<drive serial>${driveFreeCapacityDataLabel} is free amount on non-raid drives
    #<drive serial>${driveUsedPercentageDataLabel} is used percent on non-raid drives
    #<drive serial>${driveFileSystemDataLabel} is the file system on the device for non-raid drives
    #<drive serial>${smartStatusDataLabel} is the general smart health of the drive as ${TRUE} or ${FALSE}
    #<drive serial>${driveInterfaceDataLabel} is the interface the drive connects to the computer on, such asSATA, SAT, SASD, SCSI

    #grab the info for the drives
#    driveSerial=$(getDriveInfo "${disk}" "driveInfo")

    #I'd love to use the function above, but for some reason the scope of the array is the function, so
    #the drive info is not available to the rest of the code.  It maybe that there's no details in the array yet,
    #but you'd think that they would allow that
    #Anyway, messy code now, instead if a nice function call
    driveSerial=$(getSerial "${disk}") # "driveInfo")
    if [ -v driveSerial ]
    then
        driveInfo["${driveSerial}${driveLetterDataLabel}"]=$(getDriveLetter "${disk}")
        echo -n "${driveInfo["${driveSerial}${driveLetterDataLabel}"]}"
        driveInfo["${driveSerial}${driveInterfaceDataLabel}"]=$(getDriveInterfaceType "${driveInfo["${driveSerial}${driveLetterDataLabel}"]}")
        driveInfo["${driveSerial}${ataDataLabel}"]=$(getATA "${driveInfo["${driveSerial}${driveLetterDataLabel}"]}" "${driveInfo["${driveSerial}${driveInterfaceDataLabel}"]}")
        driveInfo[${driveSerial}${smartStatusDataLabel}]=$(getSmartStatus "${driveInfo["${driveSerial}${driveLetterDataLabel}"]}")
        #the only reason I can see as to why this works and the name reference in the getDriveInfo fails
        #is because the array now has some data in it.  i did try using declare -A driveInfo=() to at
        #least initialise it, but it really does seem to need something in there, and just adding 
        #anything would cause problems later
        getFSInfo "${driveSerial}" "driveInfo"
        getDriveTemp "${driveSerial}" "driveInfo"
        retVal=$?
        if (( ${retVal} != ${ERROR_BAD_DRIVE_TEMP} ))
        then
            driveInfo[${driveSerial}${temperatureDataLabel}]=${retVal}
        fi

        
        removeFromArray "${driveSerial}" "KNOWN_SERIALS"
        debugEcho "ADDED: [${driveSerial}] [${driveInfo["${driveSerial}${driveLetterDataLabel}"]}] [${driveInfo["${driveSerial}${ataDataLabel}"]}]"
        echo -n "${OK_NORMAL_TEXT}✔${NORMAL_TEXT} "
    else
        driveSerial="${NO_SERIAL_NUMBER}"
        echo -n "${ERROR_NORMAL_TEXT}$(basename ${disk})⚠${NORMAL_TEXT} "
    fi
done
echo -en "\n"

if [ "${#KNOWN_SERIALS[@]}" != "0" ]
then
    formatText "******DRIVES ARE MISSING******" ${ERROR_TEXT} ${FALSE} ${FALSE}
    drivesPresentMsg="${ERROR_BLINK_TEXT}DRIVES ARE MISSING${NORMAL_TEXT}"
    drivesPresentStatus=${FALSE}
    for driveSerial in ${KNOWN_SERIALS[@]}
    do
        formatText "Drive [${driveSerial}] is missing" ${ERROR_TEXT} ${TRUE} ${FALSE}
        #and fill in driveinfo with fake offline data so the table knows to display Offline message
        driveInfo["${driveSerial}${ataDataLabel}"]="${DRIVE_OFFLINE_ATA}"
        driveInfo["${driveSerial}${driveLetterDataLabel}"]="${DRIVE_OFFLINE_DRIVE_LETTER}"
        driveInfo["${driveSerial}${temperatureDataLabel}"]="${DRIVE_OFFLINE_TEMP}"
        driveInfo["${driveSerial}${driveTotalCapacityDataLabel}"]="${DRIVE_OFFLINE_CAPACITY}"
        driveInfo["${driveSerial}${driveUsedCapacityDataLabel}"]="${DRIVE_OFFLINE_USED_SPACE}"
        driveInfo["${driveSerial}${driveFreeCapacityDataLabel}"]="${DRIVE_OFFLINE_FREE_SPACE}"
        driveInfo["${driveSerial}${driveUsedPercentageDataLabel}"]="${DRIVE_OFFLINE_USED_PERCENTAGE}"
        driveInfo["${driveSerial}${driveFileSystemDataLabel}"]="${DRIVE_OFFLINE_FS_TYPE}"
    done
else
    formatText "All known drives are present" ${OK_TEXT} ${FALSE} ${FALSE}
    drivesPresentMsg="${OK_BOLD_TEXT}All known drives are present${NORMAL_TEXT}"
    drivesPresentStatus=${TRUE}
    EXIT_STATUS=0
fi

if [ "${hotDrives}" != "0" ]
then
    formatText "[${hotDrives}/${totalNumberOfAllDrives}] are running over ${MAX_DRIVE_TEMP}糖" ${ERROR_TEXT} ${TRUE} ${FALSE}
    hotDrivesMsg="${ERROR_BLINK_TEXT}[${hotDrives}/${totalNumberOfAllDrives}] drives are running over ${MAX_DRIVE_TEMP}糖${NORMAL_TEXT}"
    formatText "The Hottest Drive is ${highestDriveTemp}糖" ${ERROR_TEXT} ${TRUE} ${FALSE}
    highestTempMesg="${ERROR_BLINK_TEXT}The Hottest Drive is ${highestDriveTemp}糖${NORMAL_TEXT}"
    if [ "${EXIT_STATUS}" == "0" ]
    then
        EXIT_STATUS=10
    else
        EXIT_STATUS=11
    fi
else
    highestTempMesg="${OK_BOLD_TEXT}The Hottest Drive is ${highestDriveTemp}糖${NORMAL_TEXT}"
fi

getBlockFSInfo "poolInfo" "${POOL_MOUNTPOINT}" "poolSpaceMsg" "Pool"

#######RAID Drives
formatText "mdRAID Status" ${EMPHASISE_TEXT} ${FALSE} ${FALSE}
checkMount "${RAID_MOUNTPOINT}"
retValue=$?
if (( ${retValue} != ${SUCCESS} ))
then
    formatText "[${retVal}] RAID Array ${mdraidDevice} error at ${RAID_MOUNTPOINT}" ${ERROR_TEXT} ${TRUE} ${FALSE}
    raidHealthMsg="${ERROR_BLINK_TEXT}[${retVal}] RAID Array ${mdraidDevice} error at ${RAID_MOUNTPOINT}${NORMAL_TEXT}"
    grep "${mdraidDevice}" "${fstabLocation}"
    raidError=${TRUE}
fi

sudo mdadm --misc --detail --test "${mdraidDevice}" &> /dev/null
retVal=$?
if [ "${retVal}" != "0" ]
then
    formatText "The mdraid Array has reported an error [${retVal}]" ${ERROR_TEXT} ${TRUE} ${FALSE}
    raidHealthMsg="${raidHealthMsg} ${ERROR_BLINK_TEXT}The mdraid Array has reported an error [${retVal}]${NORMAL_TEXT}"
    sudo mdadm --misc --detail --test "${mdraidDevice}"
    raidError=${TRUE}
else
    formatText "The Array reports as healthy" ${OK_TEXT} ${FALSE} ${FALSE}
    raidHealthMsg="${raidHealthMsg} ${OK_BOLD_TEXT}The Array reports as healthy${NORMAL_TEXT}"
fi

#debugEcho "Checking if all raid disks are present..."
for disk in `ls /dev/disk/by-id/wwn-*`
do
    if [ "$(lsblk --nodeps -f "${disk}" | awk 'END{print $2}')" == "${LINUX_RAID_FS_TYPE}" ]
    then
#        info=`udevadm info --query=all --name=$disk | grep SERIAL`
#        scsiSerial=`echo $info | grep -o [^\ ]*SCSI[^\ ]*`
#        if [ ! -z $scsiSerial ]
#        then
#            driveSerial=${scsiSerial#*=}
#        else
#            serial=`echo $info | grep -o [^\ ]*SERIAL=[^\ ]*`
#            driveSerial=${serial#*=}
#        fi
        driveSerial=$(getSerial "${disk}")
        debugEcho "Drive Serial: ${driveSerial}"
        if [ ! -z driveSerial ]
        then
            removeFromArray "${driveSerial}" "ARRAY_SERIALS"
            debugEcho "Removing ${driveSerial}"
        fi
    fi
done

if [ "${#ARRAY_SERIALS[@]}" != "0" ]
then
    formatText "******ARRAY DRIVES ARE MISSING******" ${ERROR_TEXT} ${FALSE} ${FALSE}
    raidDrivesMountedMsg="${ERROR_BLINK_TEXT}ARRAY DRIVES ARE MISSING${NORMAL_TEXT}"
    let raidDrivesPresent=${totalNumberOfArrayDrives}-${#ARRAY_SERIALS[@]}
    for driveSerial in ${ARRAY_SERIALS[@]}
    do
        formatText "Drive [${driveSerial}] is missing" ${ERROR_TEXT} ${TRUE} ${FALSE}
    done
    raidError=${TRUE}
else
    formatText "All known array drives are present" ${OK_TEXT} ${FALSE} ${FALSE}
    raidDrivesMountedMsg="${OK_BOLD_TEXT}All known array drives are present${NORMAL_TEXT}"
    raidDrivesPresent=totalNumberOfArrayDrives
fi

getBlockFSInfo "raidInfo" "${RAID_MOUNTPOINT}" "raidSpaceMsg" "Raid"

if [ "${raidInfo["${driveFileSystemDataLabel}"]}" != "${RAID_FILESYSTEM_EXPECTED}" ]
then
    formatText "RAID Filesystem is ${driveFileSystemDataLabel} instead of ${RAID_FILESYSTEM_EXPECTED}.  This could indicate a badly assembled array." ${ERROR_TEXT} ${TRUE} ${FALSE}
    raidFSMsg="${ERROR_BLINK_TEXT}RAID Filesystem is ${driveFileSystemDataLabel} instead of ${RAID_FILESYSTEM_EXPECTED}.  This could indicate a badly assembled array.${NORMAL_TEXT}"
    raidError=${TRUE}
fi

cat /proc/mdstat
infoText "List of all Raid Drives available on system (if not all drives are listed a power cycle may be required)" ${INFO_TEXT_MISC_NO_DOTS}
lsblk -f | grep "${LINUX_RAID_FS_TYPE}"

if [ "${videopoolHealthMsg}" != "${NO_MSG}" ]
then
    debugEcho "${videopoolHealthMsg}"
fi
if [ "${drivesPresentMsg}" != "${NO_MSG}" ]
then
    debugEcho "${drivesPresentMsg}"
fi
if [ "${raidHealthMsg}" != "${NO_MSG}" ]
then
    debugEcho "${raidHealthMsg}"
fi
if [ "${raidDrivesMountedMsg}" != "${NO_MSG}" ]
then
    debugEcho "${raidDrivesMountedMsg}"
fi
if [ "${NOTIFY}" == "${TRUE}" ]
then
    debugEcho "${OK_BOLD_TEXT}Notify is ON${NORMAL_TEXT}"
else
    debugEcho "${ERROR_BLINK_TEXT}Notify is OFF${NORMAL_TEXT}"
fi
if [ "${highestTempMesg}" != "${NO_MSG}" ]
then
    debugEcho "${highestTempMesg}"
fi
if [ "${poolSpaceMsg}" != "${NO_MSG}" ]
then
    printf "${poolSpaceMsg}"
fi
if [ "${raidSpaceMsg}" != "${NO_MSG}" ]
then
    printf "${raidSpaceMsg}"
fi
if [ "${raidFSMsg}" != "${NO_MSG}" ]
then
    debugEcho "${raidFSMsg}"
fi

#Input is a list of parameters (type int) of status in the following format:
# <total number of pool drives> <number of pool drives actually mounted>
# <${TRUE} if all known drives are present ${FALSE} if not> <${TRUE} if Array is Healthy and ${FALSE} if degraded>
# <total number of Array drives> <number of Array drives actually present> <maximum temperature a drive should be>
# <temperature of hottest drive>  <Percantage of used space on pool> <Actual used space on pool> <Total space on pool>
# <percentage of used space on raid> <Actual used space on raid> <Total space on raid> <Highest used space percentage advised>
# <${TRUE} if nofiication are on ${FALSE} if off>  <${TRUE} if nofiication are on ${FALSE} if off>
# <${TRUE} if all drives have a healthy smart status, ${FALSE} if one or more does not>
if [ "${raidError}" == "${TRUE}" ]
then
    drawStatusTable ${totalNumberOfPoolDrives} ${mountedDrives} ${drivesPresentStatus} ${FALSE} ${totalNumberOfArrayDrives} ${raidDrivesPresent} ${MAX_DRIVE_TEMP} ${highestDriveTemp} ${poolInfo["${driveUsedPercentageDataLabel}"]} ${poolInfo["${driveUsedCapacityDataLabel}"]} ${poolInfo["${driveTotalCapacityDataLabel}"]} ${raidInfo["${driveUsedPercentageDataLabel}"]} ${raidInfo["${driveUsedCapacityDataLabel}"]} ${raidInfo["${driveTotalCapacityDataLabel}"]} ${DRIVE_SPACE_THRESHOLD} ${NOTIFY} ${allDrivesSmart}
else
    drawStatusTable ${totalNumberOfPoolDrives} ${mountedDrives} ${drivesPresentStatus} ${TRUE} ${totalNumberOfArrayDrives} ${raidDrivesPresent} ${MAX_DRIVE_TEMP} ${highestDriveTemp} ${poolInfo["${driveUsedPercentageDataLabel}"]} ${poolInfo["${driveUsedCapacityDataLabel}"]} ${poolInfo["${driveTotalCapacityDataLabel}"]} ${raidInfo["${driveUsedPercentageDataLabel}"]} ${raidInfo["${driveUsedCapacityDataLabel}"]} ${raidInfo["${driveTotalCapacityDataLabel}"]} ${DRIVE_SPACE_THRESHOLD} ${NOTIFY} ${allDrivesSmart}
fi
#debugEcho "Prepass DriveInfo Indicies: [${!driveInfo[@]}]"
#debugEcho "Prepass DriveInfo Values: [${driveInfo[@]}]"
drawDriveTemps driveInfo

if [ "${hotDrivesMsg}" != "${NO_MSG}" ]
then
    echo "${hotDrivesMsg}"
fi

if [ "${raidError}" == "${TRUE}" ]
then
    echo "${ERROR_BLINK_TEXT}RAID ERROR${NORMAL_TEXT}"
    echo "If you need to rebuild the array after one or more drives disconnects temporarily try:"
    echo "  umounraid"
    echo "  sudo mdadm /dev/md0 --manage --stop"
    echo "  sudo mdadm --examine /dev/sd[jlop] | egrep 'Event|/dev/sd'"
    echo "to see the event counts and note any drive that is way off.  Then issue:"
    echo "  sudo mdadm /dev/md0 --assemble --force /dev/sdj /dev/sdl /dev/sdo /dev/sdp"
    formatText "BUT miss out any drives who's event counts are too different" ${EMPHASISE_TEXT} ${TRUE} ${TRUE}
    echo " then --re-add it later once sync'd"
    case ${EXIT_STATUS} in
    0)
         EXIT_STATUS=100 #Only RAID had an Error
         ;;
    1)
         EXIT_STATUS=101 #RAID had error and drives did not mount in videopool
         ;;
    10)
         EXIT_STATUS=110 #RAID had errors and drives are over heating
         ;;
    11)
         EXIT_STATUS=111 #Everyhting went wrong, over heating drives, RAID had errors and video pool drives did njot mount
         ;;
    *)
         EXIT_STATUS=221 #We didn't recognise the Error Code form earlier errors, full warning
         ;;
    esac
fi
exit ${EXIT_STATUS}
