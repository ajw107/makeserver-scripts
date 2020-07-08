#!/bin/bash
set -u
trap {quit 255} EXIT

#errors
OK=0
NO_AUDIO_ERROR=1
ARRAY_SIZE_MISMATCH_ERROR=2
NO_ENGLISH_AUDIO=3
NO_TRACKS_TO_CONVERT_ERROR=0
INCORRECT_ARGUMENTS=4
FILE_DOES_NOT_EXIST_ERROR=5
EMPTY_FILE_ERROR=6
DIRECTORY_SPECIFIED_ERROR=7
MKV_MULTIPLEX_ERROR=8
DTS_CONVERSION_ERROR=9
DTS_EXTRACTION_ERROR=10
OLD_TEMP_REMOVE_ERROR=11
TEMP_REMOVE_ERROR=12
RENAME_NEW_ERROR=13
TRACKS_MISSING_ERROR=14
MISSING_CONVERTED_FILE=15
NO_VIDEO_ERROR=16
RENAME_OLD_ERROR=17
ERROR_FILE="$PWD/errors.txt"

#other constants
ENCODER="ffmpeg -hide_banner -stats"
CP="rsync -aP --no-perms --no-acls --no-xattrs --no-owner --no-group --no-times --no-super --human-readable"
MV="rsync --remove-source-files -P --no-perms --no-acls --no-xattrs --no-owner --no-group --no-times --no-super --human-readable"
RENAME="mv"
TRUE=1
FALSE=0
#we need to change the field seperator to a comma from a space (for things like MPEG AUDIO which
#should be one format, but appear as two) so save the old value so we can resotre it later
OIFS=$IFS
IFS='~'
ENGLISH_AUDIO="en"
UNDEFINED="und"
DTS_ID="DTS"
TRUEHD_ID="TrueHD"
DTS_EXT="dts"
TRUEHD_EXT="thd"
AC3_EXT="ac3"
AC3_SUFFIX="ac3.mkv"
STRIPPING_SUFFIX="stripping.mkv"
COMPRESSED_SUFFIX="no-compression.mkv"
RECOGNISED_AUDIO_FORMATS=( "$DTS_ID"~"AAC"~"AC-3"~"$TRUEHD_ID"~"Vorbis"~"MPEG Audio" )
AC3_BITRATE="640"
REMOVE_COMPRESSION="--compression -1:none"
MEDIAINFO_MKVTOOLNIX_CORRECTION_OFFSET=1
#TRACK_ORDER_SEPARATOR=","
TRACK_ORDER_SEPARATOR=" -map "
USAGE="USAGE: ./$0 \-f|--file \"<name and path of file to examine>\" [-s|--striponly] [-d|--debug]\n -s or --striponly will surpress conversion to ac3\n -d or --debug for extra debug output"
DEBUG_OUTPUT=$FALSE

#Generated files
CONVERTED_FILE="$PWD/converted.txt"
NOT_CONVERTED_FILE="$PWD/noconversion.txt"
BAD_FORMAT_FILE="$PWD/strangeFormat.txt"
TEMP_DIR="${TMPDIR:-$(dirname $(mktemp))/}"
#moved further down, so basic checking can be done first
FULLPATH=""
FILENAME=""
DIRNAME=""
FILE_EXT=""
FILENAME=""
WORKING_DIR=""

#variables
cmd=""
noOfRemovedTracks=0
compressed=$FALSE
stripping=$FALSE
i=0
allowConvert=$TRUE
keepOriginal=$FALSE

#functions
function debug_echo ()
{
    echo -e "DEBUG: $1: [$2]"
    return $TRUE
}

function secsToTime() {
 ((hrs=${1}/3600))
 ((mins=(${1}%3600)/60))
 ((secs=${1}%60))
 printf "%02d:%02d:%02d\n" $hrs $mins $secs
}

function quit ()
{
    #restore system variables
    IFS=$OIFS

    #clean up
#    local tempFilesCount=`ls "$DIRNAME"/temp-*.* 2> /dev/null | wc -l`
#    if [ "$tempFilesCount" != "0" ]
#    then
#        rm "$DIRNAME"/temp-*.*
#    fi
#    if [ -d "$WORKING_DIR" ]
#    then
#        rm -r "$WORKING_DIR"
#    fi

    if [ -e "$DIRNAME"/"$FILENAME-$AC3_SUFFIX" ]
    then
        rm "$DIRNAME"/"$FILENAME-$AC3_SUFFIX"
    fi

    if [ -e "$DIRNAME"/"$FILENAME-$STRIPPING_SUFFIX" ]
    then
        rm "$DIRNAME"/"$FILENAME-$STRIPPING_SUFFIX"
    fi

    case "$1" in
    $NO_AUDIO_ERROR)
        echo "Exiting with Error: [$1] - File contains no Audio"
        ;;
    $ARRAY_SIZE_MISMATCH_ERROR)
        echo "Exiting with Error: [$1] - Mediainfo did not return the same number of elements for each track"
        ;;
    $NO_ENGLISH_AUDIO)
        echo "Exiting with Error: [$1] - No English Audio Tracks Found"
        ;;
    $INCORRECT_ARGUMENTS)
        echo "Exiting with Error: [$1] - Incorrect Aurguments Supplied"
        ;;
    $FILE_DOES_NOT_EXIST_ERROR)
        echo "Exiting with Error: [$1] - The filename you supplied does no exist"
        ;;
    $EMPTY_FILE_ERROR)
        echo "Exiting with Error: [$1] - The filename you supplied is an empty file"
        ;;
    $DIRECTORY_SPECIFIED_ERROR)
        echo "Exiting with Error: [$1] - The filename you supplied is a directory, not a movie file"
        ;;
    $MKV_MULTIPLEX_ERROR)
        echo "Exiting with Error: [$1] - There was an error when seperating or combining the tracks"
        ;;
    $DTS_CONVERSION_ERROR)
        echo "Exiting with Error: [$1] - There was an error when converting the DTS Audio track to AC3"
        ;;
    $DTS_EXTRACTION_ERROR)
        echo "Exiting with Error: [$1] - There was an error when seperating the tracks"
        ;;
    $OLD_TEMP_REMOVE_ERROR)
        echo "Exiting with Error: [$1] - There was an error when removing the old temp file"
        ;;
    $TEMP_REMOVE_ERROR)
        echo "Exiting with Error: [$1] - There was an error when removing the working directory"
        ;;
    $RENAME_NEW_ERROR)
        echo "Exiting with Error: [$1] - There was an error when renaming the new file to the old filename"
        ;;
    $TRACKS_MISSING_ERROR)
        echo "Exiting with Error: [$1] - There appears to have been valid tracks not being included during the conversion"
        ;;
    $MISSING_CONVERTED_FILE)
        echo "Exiting with Error: [$1] - The converted file has somehow gone missing"
        ;;
    $NO_VIDEO_ERROR)
        echo "Exiting with Error: [$1] - No Video Streams Found"
        ;;
    $RENAME_OLD_ERROR)
        echo "Exiting with Error: [$1] - There was an error renaming the original file in an attempt to preserve it"
        ;;
    $OK)
        echo "Everything went fine!!!"
        ;;
    *)
        echo "Exiting with an UNKNOWN Error: [$1]"
        ;;
    esac

    #then exit
    exit $1
}

function isInArray ()
{
    local element
    if [ "$DEBUG_OUTPUT" == "$TRUE" ]
    then
        debug_echo "Array Contents" ${@:2}
        debug_echo "Want to find" $1
    fi

    for element in "${@:2}"
    do
        if [ "$DEBUG_OUTPUT" == "$TRUE" ]
        then
            debug_echo "Array element" $element
        fi
        if [ "$element" == "$1" ]
        then
            if [ "$DEBUG_OUTPUT" == "$TRUE" ]
            then
                echo "Match"
            fi
            return $FALSE
        fi
    done

    if [ "$DEBUG_OUTPUT" == "$TRUE" ]
    then
        echo "NO MATCH"
    fi
    return $TRUE
}

#parse arguments
if [ "$#" -lt "1" ]
then
    echo -e "$USAGE"
    quit $INCORRECT_ARGUMENTS
fi

while :; do
    case $1 in
        -h|-\?|--help)   # Basic usage
            echo -e "$USAGE"
            quit $OK
            ;;
        -f|--file)       # Takes an option argument; ensure it has been specified.
            if [ "$2" ]; then
                FULLPATH="$2"
                if [ "$DEBUG_OUTPUT" == "$TRUE" ]
                then
                    debug_echo "FULLPATH" $FULLPATH
                fi
                shift #as this option takes an argument so is really two arguments
            else
                echo -e "ERROR: No filename specified.  You supplied [$2] in command line [$@]"
                quit $INCORRECT_ARGUMENTS
            fi
            ;;
        --file=?*)
            FULLPATH=${1#*=} # Delete everything up to "=" and assigns the remainder.
            ;;
        --file=)         # Handles the case of an empty --file=
            echo -e "ERROR: No filename specied for --file.  You supplied [$1] in command line [$@], please make sure NO space follows the ="
            quit $INCORRECT_ARGUMENTS
            ;;
        -s|--striponly|--stripOnly)  #tell the script to not convert to ac3
            allowConvert=$FALSE
            ;;
        -d|--debug) #show debug output
            DEBUG_OUTPUT=$TRUE
            ;;
        -k|--keeporiginal|--keepOriginal) # don't remove the original file, just rename it
            keepOriginal=$TRUE
            ;;
#        -v|--verbose)
#            verbose=$((verbose + 1))  # Each -v adds 1 to verbosity.
#            ;;
        --)              # End of all options.
            shift
            break
            ;;
        -?*)
            echo -e "WARNING: Unknown option was ignored [$1]" >&2
            ;;
        *)               # Default case: No more options, so break out of the loop.
            break
    esac
    shift  # $2 become $1 $3 become $2, etc
done

if [ "$DEBUG_OUTPUT" == "$FALSE" ]
then
    ENCODER="${ENCODER} -loglevel 0"
fi

#check a filename has been given and it exists
if [ ! -f "$FULLPATH" ]
then
    echo -e "ERROR: [$FULLPATH] does not exist"
    quit $FILE_DOES_NOT_EXIST_ERROR
fi

if [ ! -s "$FULLPATH" ]
then
    echo -e "ERROR: [$FULLPATH] is an empty file"
    quit $EMPTY_FILE_ERROR
fi

if [ -d "$FULLPATH" ]
then
    echo -e "ERROR: [$FULLPATH] is a directory, you must specify a file"
    quit $DIRECTORY_SPECIFIED_ERROR
fi

FILENAME=`basename "$FULLPATH"`
if [ "$DEBUG_OUTPUT" == "$TRUE" ]
then
    debug_echo "FILENAME 1st pass" $FILENAME
fi
DIRNAME=`dirname "$FULLPATH"`
FILE_EXT="${FILENAME##*.}"
FILENAME="${FILENAME%.*}"
WORKING_DIR="${TEMP_DIR}convertDTS-${FILENAME}"
if [ "$DEBUG_OUTPUT" == "$TRUE" ]
then
    debug_echo "FILENAME final pass" $FILENAME
    debug_echo "FILE_EXT" $FILE_EXT
    debug_echo "DIRNAME" $DIRNAME
    debug_echo "TEMP_DIR" $TEMP_DIR
    debug_echo "WORKING_DIR" $WORKING_DIR
fi

#remove any old temp files, so don;t have any in your current directory as it will just wip all temp* files
#tempFilesCount=`ls "$DIRNAME/temp"*.* 2> /dev/null | wc -l`
#if [ "$tempFilesCount" != "0" ]
if [ -d "$WORKING_DIR" ]
then
    cmd="rm -r \"$WORKING_DIR\""
    if [ "$DEBUG_OUTPUT" == "$TRUE" ]
    then
        debug_echo "cmd" $cmd
    fi
    eval $cmd
    return=$?
    if [ "$return" != "0" ]
    then
        echo -e "[$FULLPATH] - Old Temp file deletion error [$return]" >> "$ERROR_FILE"
	echo "$cmd" >> "$ERROR_FILE"
        quit $OLD_TEMP_REMOVE_ERROR
    fi
fi
#and (re)create a clean working directory
cmd="mkdir -p \"$WORKING_DIR\""
if [ "$DEBUG_OUTPUT" == "$TRUE" ]
then
    debug_echo "make temp dir cmd" $cmd
fi
eval $cmd
return=$?
if [ "$return" != "0" ]
then
    echo -e "[$FULLPATH] - Working Directory creation error [$return]" >> "$ERROR_FILE"
    echo "$cmd" >> "$ERROR_FILE"
    quit $TEMP_REMOVE_ERROR
fi

noVideoStreams=`mediainfo "--Inform=General;%VideoCount%" "$FULLPATH"`
noAudioStreams=`mediainfo "--Inform=General;%AudioCount%" "$FULLPATH"`
noSubStreams=`mediainfo "--Inform=General;%TextCount%" "$FULLPATH"`
duration=$(mediainfo --Inform="General;%Duration/String3%" "$FULLPATH")
#duration=$(secsToTime $duration)

#find out of any tracks use header compression, we should remove this as it causes so many problems
compressed=`mkvinfo "$FULLPATH" | grep -A10 "+ Video track" | grep "Content compression" | tail -1 | sed 's/.*|/1/'`
#echo "compression [$compressed]"
if [ -z "$compressed" ]
then
    compressed=$FALSE
else
    compressed=$TRUE
fi
if [ "$DEBUG_OUTPUT" == "$TRUE" ]
then
    debug_echo "noVideoStreams" $noVideoStreams
    debug_echo "noAudioStreams" $noAudioStreams
    debug_echo "noSubStreams" $noSubStreams
    debug_echo "compressed" $compressed
    debug_echo "duration" $duration
fi

#media info just output nothing rather than a number, bad boy
if [ -z "$noVideoStreams" ]
then
    echo "[$FULLPATH] - No Video" >> "$ERROR_FILE"
    quit $NO_VIDEO_ERROR
fi
if [ -z "$noAudioStreams" ]
then
    echo "[$FULLPATH] - No Audio" >> "$ERROR_FILE"
    quit $NO_AUDIO_ERROR
fi
if [ -z "$noSubStreams" ]
then
    noSubStreams=0
fi
videoID=`mediainfo "--Inform=Video;%ID%~" "$FULLPATH"`
audioFormat=`mediainfo "--Inform=Audio;%Format%~" "$FULLPATH"`
audioID=`mediainfo "--Inform=Audio;%ID%~" "$FULLPATH"`
audioChannels=`mediainfo "--Inform=Audio;%Channel(s)%~" "$FULLPATH"`
audioLanguage=`mediainfo "--Inform=Audio;%Language%~" "$FULLPATH"`
subID=`mediainfo "--Inform=Text;%ID%~" "$FULLPATH"`
subLanguage=`mediainfo "--Inform=Text;%Language%~" "$FULLPATH"`
if [ "$DEBUG_OUTPUT" == "$TRUE" ]
then
    debug_echo "videoID" $videoID
    debug_echo "audioFormat" $audioFormat
    debug_echo "audioID" $audioID
    debug_echo "audioChannels" $audioChannels
    debug_echo "audioLanguage" $audioLanguage
    debug_echo "subID" $subID
    debug_echo "subLanguage" $subLanguage
fi

#tokenise video streams
#and convert from mediainfo (base 1) form to mkvmerge (base 0)
i=0
for item in $videoID
do
    let mkvMergeID=item-$MEDIAINFO_MKVTOOLNIX_CORRECTION_OFFSET
    videoDataID[$i]=$mkvMergeID
    if [ "$DEBUG_OUTPUT" == "$TRUE" ]
    then
        debug_echo "videoDataID[$i]" ${videoDataID[$i]}
    fi
    let i=$i+1
done
videoDataIDSize=$i
if [ "$DEBUG_OUTPUT" == "$TRUE" ]
then
    debug_echo "videoDataIDSize" $videoDataIDSize
fi
#tokenise audio streams
#and convert from mediainfo (base 1) form to mkvmerge (base 0)
#array format ID,lang,format,channels
i=0
for item in $audioID
do
    let mkvMergeID=item-$MEDIAINFO_MKVTOOLNIX_CORRECTION_OFFSET
    audioDataID[$i]=$mkvMergeID
    if [ "$DEBUG_OUTPUT" == "$TRUE" ]
    then
        debug_echo "audioDataID[$i]" ${audioDataID[$i]}
    fi
    let i=$i+1
done
audioDataIDSize=$i
if [ "$DEBUG_OUTPUT" == "$TRUE" ]
then
    debug_echo "audioDataIDSize" $audioDataIDSize
fi

i=0
for item in $audioLanguage
do
    #trim whitespace at the same time
    audioDataLanguage[$i]=`echo "$item" | sed 's/^[ \t\n\r\0\xOB]*//;s/[ \t\n\r\0\xOB]*$//'`
    if [ "$DEBUG_OUTPUT" == "$TRUE" ]
    then
        debug_echo "audioDataLanguage[$i]" ${audioDataLanguage[$i]}
    fi
    let i++
done
audioDataLanguageSize=$i
if [ "$DEBUG_OUTPUT" == "$TRUE" ]
then
    debug_echo "audioDataLanguageSize" $audioDataLanguageSize
fi

i=0
for item in $audioFormat
do
    audioDataFormat[$i]=$item
    if [ "$DEBUG_OUTPUT" == "$TRUE" ]
    then
        debug_echo "audioDataFormat[$i]" ${audioDataFormat[$i]}
    fi

    let i++
done
audioDataFormatSize=$i
if [ "$DEBUG_OUTPUT" == "$TRUE" ]
then
    debug_echo "audioDataFormatSize" $audioDataFormatSize
fi

i=0
for item in $audioChannels
do
    #compensate for multi-channel audio streams (like 7/6 Channel DTS streams)
    #if a / is found, take the next value
    if [ "$item" == "/" ]
    then
        #backtrack
        let i--
    else
        audioDataChannels[$i]=$item
        if [ "$DEBUG_OUTPUT" == "$TRUE" ]
        then
            debug_echo "audioDataChannels[$i]" ${audioDataChannels[$i]}
        fi
        let i++
    fi
done
audioDataChannelsSize=$i
if [ "$DEBUG_OUTPUT" == "$TRUE" ]
then
    debug_echo "audioDataChannelsSize" $audioDataChannelsSize
fi

#tokenise subtitle streams
#array format ID,lang
i=0
for item in $subID
do
    let mkvMergeID=item-$MEDIAINFO_MKVTOOLNIX_CORRECTION_OFFSET
    subDataID[$i]=$mkvMergeID
    if [ "$DEBUG_OUTPUT" == "$TRUE" ]
    then
        debug_echo "subDataID[$i]" ${subDataID[$i]}
    fi
    let i++
done
subDataIDSize=$i
if [ "$DEBUG_OUTPUT" == "$TRUE" ]
then
    debug_echo "subDataIDSize" $subDataIDSize
fi

i=0
for item in $subLanguage
do
    subDataLanguage[$i]=`echo "$item" | sed 's/^[ \t\n\r\0\xOB]*//;s/[ \t\n\r\0\xOB]*$//'`
    if [ "$DEBUG_OUTPUT" == "$TRUE" ]
    then
        debug_echo "subDataLanguage[$i]" ${subDataLanguage[$i]}
    fi
    let i++
done
subDataLanguageSize=$i
if [ "$DEBUG_OUTPUT" == "$TRUE" ]
then
    debug_echo "subDataLanguageSize" $subDataLanguageSize
fi

#check all arrays of same type are same size
if [ "${#audioDataID[@]}" -ne "${#audioDataLanguage[@]}" ] && [ "$noAudioStreams" != "1" ]
then
    echo "[$FULLPATH] - Audio ID [${#audioDataID[@]}] and Language [${#audioDataLanguage[@]}] have a different number of elements" >> "$ERROR_FILE"
    quit $ARRAY_SIZE_MISMATCH_ERROR
elif [ "$audioDataIDSize" -ne "$audioDataFormatSize" ]
then
    echo "[$FULLPATH] - Audio ID [$audioDataIDSize] and Format [$audioDataFormatSize] have a different number of elements" >> "$ERROR_FILE"
    quit $ARRAY_SIZE_MISMATCH_ERROR
elif [ "${#audioDataID[@]}" -ne "${#audioDataChannels[@]}" ]
then
    echo "[$FULLPATH] - Audio ID [${#audioDataID[@]}] and Channels [${#audioDataChannels[@]}] have a different number of elements" >> "$ERROR_FILE"
    quit $ARRAY_SIZE_MISMATCH_ERROR
elif [ "${#audioDataID[@]}" -ne "$noAudioStreams" ]
then
    echo "[$FULLPATH] - Audio ID [${#audioDataID[@]}] and Number of Streams [$noAudioStreams] have a different number of elements" >> "$ERROR_FILE"
    quit $ARRAY_SIZE_MISMATCH_ERROR
elif [ "${#videoDataID[@]}" -ne "$noVideoStreams" ]
then
    echo "[$FULLPATH] - Video ID [${#videoDataID[@]}] and Number of Streams [$noVideoStreams] have a different number of elements" >> "$ERROR_FILE"
    quit $ARRAY_SIZE_MISMATCH_ERROR
fi

if [ "${#subDataID[@]}" -ne "${#subDataLanguage[@]}" ] && [ "$noSubStreams" != "1" ]
then
    echo "[$FULLPATH] - Subtitle ID [${#subDataID[@]}] and Language [${#subDataLanguage[@]}] have a different number of elements" >> "$ERROR_FILE"
    quit $ARRAY_SIZE_MISMATCH_ERROR
elif [ "${#subDataID[@]}" -ne "$noSubStreams" ]
then
    echo "[$FULLPATH] - Subtitle ID [${#subDataID[@]}] and Number of Streams [$noSubStreams] have a different number of elements" >> "$ERROR_FILE"
    quit $ARRAY_SIZE_MISMATCH_ERROR
fi

# if no english audio streams add to error file
engAudio=0
# make sure we add the video track(s), note it may not be stream 0 and there maybe more than 1
for (( i=0; i<$noVideoStreams; i++ ))
do
    trackOrder="-map 0:${videoDataID[$i]} "
done
extractTracks=( "tracks" "\"$FULLPATH\"" )
tracksToConvert=0
audioToInclude="-a "
ffmpegAudio=""
echo -e "***********$FILENAME.$FILE_EXT***********"
echo -e "Audio [$noAudioStreams]:"
for (( i=0; i<$noAudioStreams; i++ ))
do
    echo -e "Audio info: $noAudioStreams (streams), ID: [${audioDataID[$i]}] Language: [${audioDataLanguage[$i]}] Format: ${audioDataFormat[$i]} Channels: ${audioDataChannels[$i]}"

    #find any files that have an uncommon format
if [ "$DEBUG_OUTPUT" == "$TRUE" ]
then
    debug_echo "Array" ${RECOGNISED_AUDIO_FORMATS[@]}
    debug_echo "Format" ${audioDataFormat[$i]}
    debug_echo "Array Returned" $(isInArray ${audioDataFormat[$i]} ${RECOGNISED_AUDIO_FORMATS[@]})
    debug_echo "False" $FALSE
    debug_echo "True" $TRUE
    audioRecognised=$(isInArray "${audioDataFormat[$i]}" "${RECOGNISED_AUDIO_FORMATS[@]}")
    debug_echo "Audio Recognised" $audioRecognised
    debug_echo "isInArray" "isInArray \"${audioDataFormat[$i]}\" \"${RECOGNISED_AUDIO_FORMATS[@]}\""
    audioRecognised=$(isInArray "${audioDataFormat[$i]}" "${RECOGNISED_AUDIO_FORMATS[@]}")
    debug_echo "Audio Recognised" $audioRecognised
fi

    if [ "$(isInArray ${audioDataFormat[$i]} ${RECOGNISED_AUDIO_FORMATS[@]})" == "$FALSE" ]
    then
        echo -e "[$FILENAME.$FILE_EXT]Audio info: $noAudioStreams stream(s), ID: [${audioDataID[$i]}] Language: [${audioDataLanguage[$i]}] Format: ${audioDataFormat[$i]} Channels: ${audioDataChannels[$i]}" >> $BAD_FORMAT_FILE
        if [ "$DEBUG_OUTPUT" == "$TRUE" ]
        then
            echo "Bad Format"
        fi
    else
        if [ "$DEBUG_OUTPUT" == "$TRUE" ]
        then
            echo "Known Format"
        fi
    fi

    # if any undefined audio or subs add to error file
    if [ "${audioDataLanguage[$i]}" == "" ] || [ "${audioDataLanguage[$i]}" == "$UNDEFINED" ]
    then
        echo "[$FULLPATH] - Undefined Audio Language" >> "$ERROR_FILE"
    fi

    #keep any non-dts english audio tracks
    if [ "${audioDataLanguage[$i]}" == "$ENGLISH_AUDIO" ] && [ "${audioDataFormat[$i]}" != "$DTS_ID" ] && [ "${audioDataFormat[$i]}" != "$TRUEHD_ID" ] && [ "$allowConvert" == "$TRUE" ]
    then
        #this bit makes sure we don't just keep converted audio tracks, but also the ones which don't
        #need converting, but are still in english
        #As a side effect if no tracks need converting we will also have a list for stripping, as no 
        #tracks that need converting will have been added
        let engAudio++
	#build command lines
	trackOrder="$trackOrder${TRACK_ORDER_SEPARATOR}0:${audioDataID[$i]}"
        echo -e "Keeping unaltered English audio track [${audioDataID[$i]}]"
        ffmpegAudio="$ffmpegAudio -c:a:$i copy"
	if [ "$audioToInclude" == "-a " ]
	then
	    audioToInclude="$audioToInclude${audioDataID[$i]}"
	else
	    audioToInclude="$audioToInclude,${audioDataID[$i]}"
	fi
    elif [ "${audioDataLanguage[$i]}" == "$ENGLISH_AUDIO" ] && [ "$allowConvert" == "$FALSE" ]
    then
        let engAudio++
        #build command lines
        trackOrder="$trackOrder${TRACK_ORDER_SEPARATOR}0:${audioDataID[$i]}"
        echo -e "Keeping unaltered English audio track [${audioDataID[$i]}]"
        ffmpegAudio="$ffmpegAudio -c:a:$i copy"
        if [ "$audioToInclude" == "-a " ]
        then
            audioToInclude="$audioToInclude${audioDataID[$i]}"
        else
            audioToInclude="$audioToInclude,${audioDataID[$i]}"
        fi
        echo -e "StripOnly Mode: Track being added unconverted [${audioDataFormat[$i]}] [${audioDataID[$i]}]"
    elif [ "${audioDataFormat[$i]}" == "$DTS_ID" ] && [ "${audioDataLanguage[$i]}" == "$ENGLISH_AUDIO" ] && [ "$allowConvert" == "$TRUE" ]
    then
        let engAudio++
        let tracksToConvert++

        #build extract commandline
	extractTracks[${#extractTracks[@]}]="${audioDataID[$i]}:\"$WORKING_DIR/temp-$tracksToConvert.$DTS_EXT\""
	#trackOrder="$trackOrder,$tracksToConvert:0"
        trackOrder="$trackOrder${TRACK_ORDER_SEPARATOR}0:${audioDataID[$i]}"
        echo -e "Converting English audio track [${audioDataID[$i]}]"
        ffmpegAudio="$ffmpegAudio -c:a:$i ac3 -b:a 600k"
        if [ "$DEBUG_OUTPUT" == "$TRUE" ]
        then
            echo "extractTracks: [$extractTracks]"
            echo "trackOrder: [$trackOrder]"
            echo "ffmpegAudio: [$ffmpegAudio]"
        fi
    elif [ "${audioDataFormat[$i]}" == "$TRUEHD_ID" ] && [ "${audioDataLanguage[$i]}" == "$ENGLISH_AUDIO" ] && [ "$allowConvert" == "$TRUE" ]
    then
        let engAudio++
	let tracksToConvert++

	#build extract commandline
	extractTracks[${#extractTracks[@]}]="${audioDataID[$i]}:\"$WORKING_DIR/temp-$tracksToConvert.$TRUEHD_EXT\""
	#trackOrder="$trackOrder,$tracksToConvert:0"
        trackOrder="$trackOrder${TRACK_ORDER_SEPARATOR}0:${audioDataID[$i]}"
        echo -e "Converting English audio track [${audioDataID[$i]}]"
        ffmpegAudio="$ffmpegAudio -c:a:$i ac3 -b:a 600k"
        if [ "$DEBUG_OUTPUT" == "$TRUE" ]
        then
            echo "extractTracks: [$extractTracks]"
            echo "trackOrder: [$trackOrder]"
            echo "ffmpegAudio: [$ffmpegAudio]"
        fi
    else
        #track won't be muxed into new file
        let noOfRemovedTracks++
        if [ "$DEBUG_OUTPUT" == "$TRUE" ]
        then
            echo "Removing Track $i"
            echo "noOfRemovedTracks: [$noOfRemovedTracks]"
        fi
    fi
done

#if no DTS, but still other language tracks (and an english one), we may as well strip the foreign ones
if ( [[ "$tracksToConvert" -eq "0" ]] && [[ "$((noAudioStreams-engAudio))" -ge "1" ]] ) || [ "$allowConvert" == "$FALSE" ]
then
    #we already have a list of tracks from above, as no tracks that need converting exist, and so where
    #never added to the list, there is no need to go back through them all again
    #all we need to see is if any tracks need to be removed, and if so signal stripping is required
    if [ "$noOfRemovedTracks" != "0" ]
    then
        stripping=$TRUE
        if [ "$DEBUG_OUTPUT" == "$TRUE" ]
        then
            echo "Stripping Mode On"
        fi
    fi
#    for (( i=0; i<$noAudioStreams; i++ ))
#    do
#        if [ "${audioDataLanguage[$i]}" == "$ENGLISH_AUDIO" ] || [ "${audioDataLanguage[$i]}" == "" ] || [ "${audioDataLanguage[$i]}" == "$UNDEFINED" ]
#	then
#	    let noOfRemovedTracks--
#	    #build command lines
#	    trackOrder="$trackOrder${TRACK_ORDER_SEPARATOR}0:${audioDataID[$i]}"
#           echo -e "STRIPPING: Keeping unaltered English audio track [${audioDataID[$i]}]"
#	    if [ "$audioToInclude" == "-a " ]
#	    then
#		audioToInclude="$audioToInclude${audioDataID[$i]}"
#	    else
#		audioToInclude="$audioToInclude,${audioDataID[$i]}"
#	    fi
#	    #echo -e "audioToInclude [$i]: $audioToInclude"
#	    stripping=$TRUE
#	fi
#    done
fi

if [ "$allowConvert" == "$FALSE" ]
then
    stripping=$TRUE
    tracksToConvert=0
    if [ "$DEBUG_OUTPUT" == "$TRUE" ]
    then
        echo "Strip Only Mode On"
    fi
fi

#remember no need to do this if stripping, as that keeps undefined audio lanbguages
if [ "$stripping" == "$FALSE" ] && [ "$engAudio" == "0" ] && [ "$noAudioStreams" == "1" ] && [ "${audioDataLanguage[0]}" == "" -o "${audioDataLanguage[0]}" == "$UNDEFINED" ]
then
    #some people are lazy and don't set the language, if only one language file, it's probably english
    echo "[$FULLPATH] - No Audio Language Set, but as only one stream assuming english" >> "$CONVERTED_FILE"
    audioDataLanguage[0]="$ENGLISH_AUDIO"
    let engAudio++
    let noOfRemovedTracks--

    if [ "${audioDataFormat[0]}" == "$DTS_ID" ] && [ "$allowConvert" == "$TRUE" ]
    then
        let tracksToConvert++

        #build extract commandline
        extractTracks[${#extractTracks[@]}]="${audioDataID[0]}:\"$WORKING_DIR/temp-$tracksToConvert.$DTS_EXT\""
        #trackOrder="$trackOrder,$tracksToConvert:0"
        trackOrder="$trackOrder${TRACK_ORDER_SEPARATOR}0:${audioDataID[0]}"
        echo -e "Assuming only track is English and converting audio track from DTS [${audioDataID[0]}]"
        ffmpegAudio="$ffmpegAudio -c:a:0 ac3 -b:a:0 600k"
        if [ "$DEBUG_OUTPUT" == "$TRUE" ]
        then
            echo "extractTracks: [$extractTracks]"
            echo "trackOrder: [$trackOrder]"
            echo "ffmpegAudio: [$ffmpegAudio]"
        fi
    elif [ "${audioDataFormat[0]}" == "$DTS_ID" ] && [ "$allowConvert" == "$FALSE" ]
    then
        echo -e "StripOnly Mode: DTS track being added unconverted [${audioDataFormat[0]}] [${audioDataID[$i]}]"
    elif [ "${audioDataFormat[0]}" == "$TRUEHD_ID" ] && [ "$allowConvert" == "$TRUE" ]
    then
        let tracksToConvert++

        #build extract commandline
        extractTracks[${#extractTracks[@]}]="${audioDataID[0]}:\"$WORKING_DIR/temp-$tracksToConvert.$TRUEHD_EXT\""
        #trackOrder="$trackOrder,$tracksToConvert:0"
        trackOrder="$trackOrder${TRACK_ORDER_SEPARATOR}0:${audioDataID[0]}"
        echo -e "Assuming only track is English and converting audio track from TRUE-HD [${audioDataID[0]}]"
        ffmpegAudio="$ffmpegAudio -c:a:0 ac3 -b:a:0 600k"
        if [ "$DEBUG_OUTPUT" == "$TRUE" ]
        then
            echo "extractTracks: [$extractTracks]"
            echo "trackOrder: [$trackOrder]"
            echo "ffmpegAudio: [$ffmpegAudio]"
        fi
    elif [ "${audioDataFormat[0]}" == "$TRUEHD_ID" ] && [ "$allowConvert" == "$FALSE" ]
    then
        echo -e "StripOnly Mode: TRUE-HD track being added unconverted [${audioDataFormat[0]}] [${audioDataID[$i]}]"
    else
        echo -e "Ignoring track already included in stripping [${audioDataFormat[0]}] [${audioDataID[$i]}]"
    fi
fi

if [ "$engAudio" -eq "0" ]
then
    echo "[$FULLPATH] - No English Audio" >> "$ERROR_FILE"
    quit $NO_ENGLISH_AUDIO
fi

if [ "$DEBUG_OUTPUT" == "$TRUE" ]
then
    debug_echo "audioToInclude" $audioToInclude
fi
if [ "$audioToInclude" == "-a " ]
then
    #no audio to include from original file
    audioToInclude="-A"
    #don't change ffmpeg audio command if conversion instructions are in it
    if [ "$ffmpegAudio" == "" ]
    then
        ffmpegAudio=" -an"
    fi
fi
if [ "$DEBUG_OUTPUT" == "$TRUE" ]
then
    debug_echo "audioToInclude" $audioToInclude
    debug_echo "ffmpegAudio" $ffmpegAudio
fi

echo -e "++++++++++++English audio streams: $engAudio"
echo -e "------------Foreign Language Audio Streams: $((noAudioStreams-engAudio))"

#process subtitles too
subToInclude="-s "
echo -e "Subs [$noSubStreams]:"
engSub=0
ffmpegSub=""
for (( i=0; i<$noSubStreams; i++ ))
do
    echo -e "Sub info: $noSubStreams stream(s), ID [${subDataID[$i]}] Language [${subDataLanguage[$i]}]"

    if [ "${subDataLanguage[$i]}" == "$ENGLISH_AUDIO" ]
    then
	#build command lines
	trackOrder="$trackOrder${TRACK_ORDER_SEPARATOR}0:${subDataID[$i]}"
        echo -e "Keeping English subtitle track [${subDataID[$i]}]"
        ffmpegSub="$ffmpegSub -c:s:$i copy"
	if [ "$subToInclude" == "-s " ]
	then
	    subToInclude="$subToInclude${subDataID[$i]}"
	else
	    subToInclude="$subToInclude,${subDataID[$i]}"
	fi

	let engSub++
        if [ "$DEBUG_OUTPUT" == "$TRUE" ]
        then
            debug_echo "trackOrder" $trackOrder
            debug_echo "ffmpegSub" $ffmpegSub 
            debug_echo "subsToInclude" $subsToInclude
            debug_echo "engSub" $engSub
        fi
    else
        #track will not be in the final mux
        let noOfRemovedTracks++
        stripping=$TRUE
        if [ "$DEBUG_OUTPUT" == "$TRUE" ]
        then
            debug_echo "noOfRemoved Tracks" $noOfRemovedTracks
            debug_echo "stripping" $stripping
        fi
    fi

    # if any undefined audio or subs add to error file
    if [ "${subDataLanguage[$i]}" == "" ] || [ "${subDataLanguage[$i]}" == "$UNDEFINED" ]
    then
        echo "[$FULLPATH] - Undefined Subtitle Language" >> "$ERROR_FILE"
    fi
done

if [ "$noSubStreams" -eq "1" ] && [ "${subDataLanguage[0]}" == "" -o "${subDataLanguage[0]}" == "$UNDEFINED" ]
then
    #some people are lazy and don't set the language, if only one language file, it's probably english
    echo "[$FULLPATH] - No Subtitle Language Set, but as only one stream assuming english" >> "$CONVERTED_FILE"

    subDataLanguage[0]="$ENGLISH_AUDIO"

    #build command lines
    trackOrder="$trackOrder${TRACK_ORDER_SEPARATOR}0:${subDataID[0]}"
    echo -e "Assuming subtitle track is English [${subDataLanguage[0]}] and keeping subtitle track [${subDataID[$0]}]"
    ffmpegSub=" -c:s:0 copy"
    if [ "$subToInclude" == "-s " ]
    then
	subToInclude="$subToInclude${subDataID[0]}"
    else
	subToInclude="$subToInclude,${subDataID[0]}"
    fi

    let engSub++
    let noOfRemovedTracks--
    stripping=$TRUE
    if [ "$DEBUG_OUTPUT" == "$TRUE" ]
    then
        debug_echo "trackOrder" $trackOrder
        debug_echo "ffmpegSub" $ffmpegSub
        debug_echo "subsToInclude" $subsToInclude
        debug_echo "engSub" $engSub
        debug_echo "noOfRemoved Tracks" $noOfRemovedTracks
        debug_echo "stripping" $stripping
   fi
fi

echo -e "------------Foreign Language Subtitle Streams: $((noSubStreams-engSub))"

#if no DTS, but still other language tracks (and an english one), we may as well strip the foreign ones
#if [ "$tracksToConvert" -eq "0" ] && [ "$((noSubStreams-engSub))" -ge "1" ]
#then
#    for (( i=0; i<$noSubStreams; i++ ))
#    do
#		if [ "${subDataLanguage[$i]}" == "$ENGLISH_AUDIO" ] || [ "${subDataLanguage[$i]}" == "" ] || [ "${subDataLanguage[$i]}" == "$UNDEFINED" ]
#		then
#			#build command lines
#			trackOrder="$trackOrder,0:${subDataID[$i]}"
#			if [ "$subToInclude" == "-s " ]
#			then
#				subToInclude="$subToInclude${subDataID[$i]}"
#			else
#				subToInclude="$subToInclude,${subDataID[$i]}"
#			fi
#
#			stripping=$TRUE
#		fi
#	done
#fi

if [ "$DEBUG_OUTPUT" == "$TRUE" ]
then
    debug_echo "subToInclude" $subToInclude
fi

if [ "$subToInclude" == "-s " ]
then
    #no subtitles to include from original file
    subToInclude="-S"
    ffmpegSub=" -sn"
    if [ "$DEBUG_OUTPUT" == "$TRUE" ]
    then
        echo "Not going to include any subs from original file"
    fi
fi

echo -e "%%%%%%%%%%Tracks to Convert: $tracksToConvert"
echo -e "%%%%%%%%%%Tracks to Remove: $noOfRemovedTracks"
echo -e "%%%%%%%%%%Tracks containing Compression: $compressed"

#if no audio and only stripping, don't
if [ "$audioToInclude" == "-A" ]
then
    echo -e "[$FULLPATH] - Cancelling stripping as it would mean no Audio stream" >> $CONVERTED_FILE
    stripping=$FALSE
fi

#if no stream to convert, exit
if [ "$tracksToConvert" -eq "0" ] && [ "$stripping" -eq "$FALSE" ] && [ "$compressed" -eq "$FALSE" ] && [ "$allowConvert" == "$TRUE" ]
then
    echo "[$FULLPATH] - No tracks need converting or stripping" >> noconvert.txt
    quit $NO_TRACKS_TO_CONVERT_ERROR
fi

# At present (2014/5) ffmpeg has a problem where it can not handle audio tracks by themselves if they
# do not have perfect timestamps (amazing how many don't), so will have to do the whole file at once 

#skip the extraction and conversion if file is just to be stripped or compression removed
#if [ "$tracksToConvert" -ge "1" ]
#then
    #extract dts audio streams
# if converting
#    cmd="mkvextract ${extractTracks[@]}"
#    echo -e "\nExecuting Command:\n$cmd\n"
#    eval $cmd
#    return=$?

#    if [ "$return" != "0" ]
#    then
#       echo -e "[$FULLPATH] - DTS extraction error [$return]" >> "$ERROR_FILE"
#       echo "$cmd" >> "$ERROR_FILE"
#       quit $DTS_EXTRACTION_ERROR
#    fi

    # convert each english audio stream
#    mergeAudioTracks=""
#    for (( i=1; i<=$tracksToConvert; i++ ))
#    do
#        if [ -e "$WORKING_DIR/temp-$i.$DTS_EXT" ]
#        then
#            cmd="$ENCODER -y -i \"$WORKING_DIR/temp-$i.$DTS_EXT\" -acodec ac3 -ab ${AC3_BITRATE}k -ar 48000 -async 48000 -ac 6 \"$WORKING_DIR/temp-$i.$AC3_EXT\""
#        elif [ -e "$WORKING_DIR/temp-$i.$TRUEHD_EXT" ]
#        then
#            cmd="$ENCODER -y -i \"$WORKING_DIR/temp-$i.$TRUEHD_EXT\" -acodec ac3 -ab ${AC3_BITRATE}k -ar 48000 -async 48000 -ac 6 \"$WORKING_DIR/temp-$i.$AC3_EXT\""
#        else
#            #what on earth has happened here, only two formats need converting
#            echo -e "[$FULLPATH] - Conversion error, can't find either a .dts or .thd file" >> "$ERROR_FILE"
#            quit $DTS_CONVERSION_ERROR
#        fi
#        echo -e "\nExecuting Command:\n$cmd\n"
#        eval $cmd
#        return=$?
#        if [ "$return" != "0" ]
#        then
#            echo -e "[$FULLPATH] - DTS conversion error [$return]" >> "$ERROR_FILE"
#	    echo "$cmd" >> "$ERROR_FILE"
#	    quit $DTS_CONVERSION_ERROR
#	fi
#	mergeAudioTracks="$mergeAudioTracks --languwage 0:$ENGLISH_AUDIO \"$WORKING_DIR/temp-$i.$AC3_EXT\""
#    done
#elif [ "$stripping" -eq "$TRUE" ]
if [ "$stripping" -eq "$TRUE" ]
then
    echo -e "STRIPPING: No conversion necessary"
elif [ "$compressed" -eq "$TRUE" ] && [ "$tracksToConvert" -eq "0" ]
then
     echo -e "Compressed Tracks Only: No conversion necessary"
fi

trackLanguage=""
for id in ${audioDataID[@]}
do
    trackLanguage="$trackLanguage --language $id:$ENGLISH_AUDIO"
done

if [ "$DEBUG_OUTPUT" == "$TRUE" ]
then
    debug_echo "trackLanguage" $trackLanguage
fi

for id in ${subDataID[@]}
do
   trackLanguage="$trackLanguage --language $id:$ENGLISH_AUDIO"
done

if [ "$DEBUG_OUTPUT" == "$TRUE" ]
then
    debug_echo "trackLanguage" $trackLanguage
fi

echo "Video Duration: ${duration}"

# remux with only video and then english new audio and subs
if [ "$tracksToConvert" -ge "1" ] && [ "$allowConvert" == "$TRUE" ]
then
    #not using mkvtools as ffmepg can't cope with just an audio file anymore in case it has unusual or
    #missing timestamps, in this case the whole file must be fed into ffmpeg
    if [ "$DEBUG_OUTPUT" == "$TRUE" ]
    then
        debug_echo "ffmpegAudio" $ffmpegAudio
        debug_echo "ffmpegSub" $ffmpegSub
    fi
    cmd="$ENCODER -fflags +genpts+igndts -y -threads auto -i \"$FULLPATH\" $trackOrder -c:v copy$ffmpegAudio$ffmpegSub \"$WORKING_DIR/$FILENAME-$AC3_SUFFIX\""
    #cmd="mkvmerge --track-order $trackOrder --default-language $ENGLISH_AUDIO -o \"$WORKING_DIR/$FILENAME-$AC3_SUFFIX\" $REMOVE_COMPRESSION $audioToInclude $subToInclude $trackLanguage \"$FULLPATH\" $mergeAudioTracks"
    echo -e "\nExecuting Command:\n$cmd\n"
    eval $cmd
    return=$?
    
    if [ "$return" != "0" ]
    then
	echo -e "[$FULLPATH] - MKV multiplex and convert error [$return]" >> "$ERROR_FILE"
	echo "$cmd" >> "$ERROR_FILE"
	quit $MKV_MULTIPLEX_ERROR
    fi
elif [ "$stripping" -eq "$TRUE" ] || [ "$allowConvert" == "$FALSE" ]
then
    #cmd="mkvmerge --track-order $trackOrder --default-language $ENGLISH_AUDIO -o \"$WORKING_DIR/$FILENAME-$STRIPPING_SUFFIX\" $REMOVE_COMPRESSION $audioToInclude $subToInclude $trackLanguage \"$FULLPATH\""
    cmd="$ENCODER -fflags +genpts+igndts -y -threads auto -i \"$FULLPATH\" $trackOrder -c:v copy$ffmpegAudio$ffmpegSub \"$WORKING_DIR/$FILENAME-$STRIPPING_SUFFIX\""
    echo -e "\nExecuting Command:\n$cmd\n"
    eval $cmd
    return=$?

    if [ "$return" != "0" ]
    then
	echo -e "[$FULLPATH] - Stripping Multiplex Error [$return]" >> "$ERROR_FILE"
	echo "$cmd" >> "$ERROR_FILE"
	quit $MKV_MULTIPLEX_ERROR
    fi
elif [ "$compressed" -ge "$TRUE" ]
then
    cmd="mkvmerge --default-language $ENGLISH_AUDIO -o \"$WORKING_DIR/$FILENAME-$COMPRESSED_SUFFIX\" $REMOVE_COMPRESSION \"$FULLPATH\""
    echo -e "\nExecuting Command:\n$cmd\n"
    eval $cmd
    return=$?

    if [ "$return" != "0" ]
    then
        echo -e "[$FULLPATH] - Compression Multiplex Error [$return]" >> "$ERROR_FILE"
        echo "$cmd" >> "$ERROR_FILE"
        quit $MKV_MULTIPLEX_ERROR
    fi
fi
#log convertion

#make sure converted file really exists and seems valid
if [ -f "$WORKING_DIR/$FILENAME-$AC3_SUFFIX" -a -s "$WORKING_DIR/$FILENAME-$AC3_SUFFIX" -a ! -d "$WORKING_DIR/$FILENAME-$AC3_SUFFIX" ] && [ "$tracksToConvert" -ge "1" ] 
then
    echo "[$FULLPATH] converted" >> converted.txt
    mediainfo "$WORKING_DIR/$FILENAME-$AC3_SUFFIX" >> converted.txt
    audioFound=`mediainfo "--Inform=General;%AudioCount%" "$WORKING_DIR/$FILENAME-$AC3_SUFFIX"`
    subsFound=`mediainfo "--Inform=General;%TextCount%" "$WORKING_DIR/$FILENAME-$AC3_SUFFIX"`
    if [ -z "$audioFound" ]
    then
        audioFound=0
    fi
    if [ -z "$subsFound" ]
    then
        subsFound=0
    fi

    if [ "$engAudio" != "$audioFound" ]
    then
        #we've not added all the english audio tracks back
        echo -e "[$FULLPATH] - All the English Audio tracks have not been added back" >> "$ERROR_FILE"
        echo -e "$engAudio english tracks found during processing, but only $audioFound are in the produced file" >> "$ERROR_FILE"
        quit $TRACKS_MISSING_ERROR
    fi

    if [ "$engSub" != "$subsFound" ]
    then
        #we've not added all the english sub tracks back
        echo -e "[$FULLPATH] - All the English Subtitle tracks have not been added back" >> "$ERROR_FILE"
        echo -e "$engSub english tracks found during processing, but only $subsFound are in the produced file" >> "$ERROR_FILE"
        quit $TRACKS_MISSING_ERROR
    fi

    #copy the converted file into the original movies directory, in preparation to swap
    #plus we have chance for one last check to make sure it copies over okay
    cmd="$CP \"$WORKING_DIR/$FILENAME-$AC3_SUFFIX\" \"$DIRNAME/$FILENAME-$AC3_SUFFIX\""
    echo -e "\nCopying Processed Movie back to original location..."
    if [ "$DEBUG_OUTPUT" == "$TRUE" ]
    then
        debug_echo "cmd" $cmd
    fi
    eval $cmd
    return=$?

    if [ "$return" != "0" ]
    then
        echo -e "[$FULLPATH] - Copying converted file to movie directory error  [$return]" >> "$ERROR_FILE"
        echo "$cmd" >> "$ERROR_FILE"
        quit $TEMP_REMOVE_ERROR
    fi

    #If we're here, everything is fine, delete the original in readiness for the temp file
    if [ "${keepOriginal}" == "$TRUE" ]
    then
        echo -e "Keeping Original file, renaming to [$FILENAME-original.$FILE_EXT]"
        cmd="$RENAME \"$FULLPATH\" \"$DIRNAME/$FILENAME-original.$FILE_EXT\""
        if [ "$DEBUG_OUTPUT" == "$TRUE" ]
        then
            debug_echo "cmd" $cmd
        fi
        eval $cmd
        return=$?
        if [ "$return" != "0" ]
        then
            echo -e "[$FULLPATH] - Original DTS File rename error [$return]" >> "$ERROR_FILE"
            echo "$cmd" >> "$ERROR_FILE"
            quit $RENAME_OLD_ERROR
        fi
    else
        cmd="rm \"$FULLPATH\""
        if [ "$DEBUG_OUTPUT" == "$TRUE" ]
        then
            debug_echo "cmd" $cmd
        fi
        eval $cmd
        return=$?
        if [ "$return" != "0" ]
        then
            echo -e "[$FULLPATH] - Original DTS File Deletion error [$return]" >> "$ERROR_FILE"
            echo "$cmd" >> "$ERROR_FILE"
            quit $TEMP_REMOVE_ERROR
        fi
    fi

    cmd="$RENAME \"$DIRNAME/$FILENAME-$AC3_SUFFIX\" \"$FULLPATH\""
    if [ "$DEBUG_OUTPUT" == "$TRUE" ]
    then
        debug_echo "cmd" $cmd
    fi
    eval $cmd
    return=$?

    if [ "$return" != "0" ]
    then
        echo -e "[$FULLPATH] - Replacing original file error [$return]" >> "$ERROR_FILE"
        echo "$cmd" >> "$ERROR_FILE"
        quit $RENAME_NEW_ERROR
    fi
elif [ -f "$WORKING_DIR/$FILENAME-$STRIPPING_SUFFIX" -a -s "$WORKING_DIR/$FILENAME-$STRIPPING_SUFFIX" -a ! -d "$WORKING_DIR/$FILENAME-$STRIPPING_SUFFIX" ] && [ "$stripping" == "$TRUE" ]
then
    echo "[$FULLPATH] converted" >> converted.txt
    mediainfo "$WORKING_DIR/$FILENAME-$STRIPPING_SUFFIX" >> converted.txt
    audioFound=`mediainfo "--Inform=General;%AudioCount%" "$WORKING_DIR/$FILENAME-$STRIPPING_SUFFIX"`
    subsFound=`mediainfo "--Inform=General;%TextCount%" "$WORKING_DIR/$FILENAME-$STRIPPING_SUFFIX"`
    if [ -z "$audioFound" ]
    then
        audioFound=0
    fi
    if [ -z "$subsFound" ]
    then
        subsFound=0
    fi

    if [ "$engAudio" != "$audioFound" ]
    then
        #we've not added all the english audio tracks back
        echo -e "[$FULLPATH] - All the English Audio tracks have not been added back" >> "$ERROR_FILE"
        echo -e "$engAudio english tracks found during processing, but only $audioFound are in the processed file" >> "$ERROR_FILE"
        quit $TRACKS_MISSING_ERROR
    fi

    if [ "$engSub" != "$subsFound" ]
    then
        #we've not added all the english sub tracks back
        echo -e "[$FULLPATH] - All the English Subtitle tracks have not been added back" >> "$ERROR_FILE"
        echo -e "$engSub english tracks found during processing, but only $subsFound are in the produced file" >> "$ERROR_FILE"
        quit $TRACKS_MISSING_ERROR
    fi

    #copy the converted file into the original movies directory, in preparation to swap
    #plus we have chance for one last check to make sure it copies over okay
    cmd="$CP \"$WORKING_DIR/$FILENAME-$STRIPPING_SUFFIX\" \"$DIRNAME/$FILENAME-$STRIPPING_SUFFIX\""
    echo -e "\nCopying Processed Movie back to original location..."
    if [ "$DEBUG_OUTPUT" == "$TRUE" ]
    then
        debug_echo "cmd" $cmd
    fi
    eval $cmd
    return=$?

    if [ "$return" != "0" ]
    then
        echo -e "[$FULLPATH] - Copying stripped file to movie directory error  [$return]" >> "$ERROR_FILE"
        echo "$cmd" >> "$ERROR_FILE"
        quit $TEMP_REMOVE_ERROR
    fi

    #If we're here, everything is fine, delete the original in readiness for the temp file
    if [ "${keepOriginal}" == "$TRUE" ]
    then
        echo -e "Keeping Original file, renaming to [$FILENAME-original.$FILE_EXT]"
        cmd="$RENAME \"$FULLPATH\" \"$DIRNAME/$FILENAME-original.$FILE_EXT\""
        if [ "$DEBUG_OUTPUT" == "$TRUE" ]
        then
            debug_echo "cmd" $cmd
        fi
        eval $cmd
        return=$?
        if [ "$return" != "0" ]
        then
            echo -e "[$FULLPATH] - Original File rename error [$return]" >> "$ERROR_FILE"
            echo "$cmd" >> "$ERROR_FILE"
            quit $RENAME_OLD_ERROR
        fi
    else
        cmd="rm \"$FULLPATH\""
        if [ "$DEBUG_OUTPUT" == "$TRUE" ]
        then
            debug_echo "cmd" $cmd
        fi
        eval $cmd
        return=$?

        if [ "$return" != "0" ]
        then
            echo -e "[$FULLPATH] - Original File Deletion error [$return]" >> "$ERROR_FILE"
	    echo "$cmd" >> "$ERROR_FILE"
            quit $TEMP_REMOVE_ERROR
        fi
    fi
    cmd="$RENAME \"$DIRNAME/$FILENAME-$STRIPPING_SUFFIX\" \"$FULLPATH\""
    if [ "$DEBUG_OUTPUT" == "$TRUE" ]
    then
        debug_echo "cmd" $cmd
    fi
    eval $cmd
    return=$?

    if [ "$return" != "0" ]
    then
        echo -e "[$FULLPATH] - Rename stripped file to original filename error [$return]" >> "$ERROR_FILE"
        echo "$cmd" >> "$ERROR_FILE"
        quit $RENAME_NEW_ERROR
    fi
elif [ -f "$WORKING_DIR/$FILENAME-$COMPRESSED_SUFFIX" -a -s "$WORKING_DIR/$FILENAME-$COMPRESSED_SUFFIX" -a ! -d "$WORKING_DIR/$FILENAME-$COMPRESSED_SUFFIX" ] && [ "$compressed" -ge "$TRUE" ]
then
    echo "[$FULLPATH] decompressed" >> converted.txt
    mediainfo "$WORKING_DIR/$FILENAME-$COMPRESSED_SUFFIX" >> converted.txt
    audioFound=`mediainfo "--Inform=General;%AudioCount%" "$WORKING_DIR/$FILENAME-$COMPRESSED_SUFFIX"`
    subsFound=`mediainfo "--Inform=General;%TextCount%" "$WORKING_DIR/$FILENAME-$COMPRESSED_SUFFIX"`
    if [ -z "$audioFound" ]
    then
        audioFound=0
    fi
    if [ -z "$subsFound" ]
    then
        subsFound=0
    fi

    if [ "$engAudio" != "$audioFound" ]
    then
        #we've not added all the english audio tracks back
        echo -e "[$FULLPATH] - All the English Audio tracks have not been added back" >> "$ERROR_FILE"
        echo -e "$engAudio english tracks found during processing, but only $audioFound are in the produced file" >> "$ERROR_FILE"
        quit $TRACKS_MISSING_ERROR
    fi

    if [ "$engSub" != "$subsFound" ]
    then
        #we've not added all the english sub tracks back
        echo -e "[$FULLPATH] - All the English Subtitle tracks have not been added back" >> "$ERROR_FILE"
        echo -e "$engSub english tracks found during processing, but only $subsFound are in the produced file" >> "$ERROR_FILE"
        quit $TRACKS_MISSING_ERROR
    fi

    #copy the converted file into the original movies directory, in preparation to swap
    #plus we have chance for one last check to make sure it copies over okay
    cmd="$CP \"$WORKING_DIR/$FILENAME-$COMPRESSED_SUFFIX\" \"$DIRNAME/$FILENAME-$COMPRESSED_SUFFIX\""
    echo -e "\nCopying Processed Movie back to original location..."
    if [ "$DEBUG_OUTPUT" == "$TRUE" ]
    then
        debug_echo "cmd" $cmd
    fi
    eval $cmd
    return=$?

    if [ "$return" != "0" ]
    then
        echo -e "[$FULLPATH] - Copying non-compressed file to movie directory error  [$return]" >> "$ERROR_FILE"
        echo "$cmd" >> "$ERROR_FILE"
        quit $TEMP_REMOVE_ERROR
    fi

    #If we're here, everything is fine, delete the original in readiness for the temp file
    if [ "${keepOriginal}" == "$TRUE" ]
    then
        echo -e "Keeping Original file, renaming to [$FILENAME-original.$FILE_EXT]"
        cmd="$RENAME \"$FULLPATH\" \"$DIRNAME/$FILENAME-original.$FILE_EXT\""
        if [ "$DEBUG_OUTPUT" == "$TRUE" ]
        then
            debug_echo "cmd" $cmd
        fi
        eval $cmd
        return=$?
        if [ "$return" != "0" ]
        then
            echo -e "[$FULLPATH] - Original Compressed File rename error [$return]" >> "$ERROR_FILE"
            echo "$cmd" >> "$ERROR_FILE"
            quit $RENAME_OLD_ERROR
        fi
    else
        cmd="rm \"$FULLPATH\""
        if [ "$DEBUG_OUTPUT" == "$TRUE" ]
        then
            debug_echo "cmd" $cmd
        fi
        eval $cmd
        return=$?

        if [ "$return" != "0" ]
        then
            echo -e "[$FULLPATH] - Original Compressed File Deletion error [$return]" >> "$ERROR_FILE"
            echo "$cmd" >> "$ERROR_FILE"
            quit $TEMP_REMOVE_ERROR
        fi
    fi
    cmd="$RENAME \"$DIRNAME/$FILENAME-$COMPRESSED_SUFFIX\" \"$FULLPATH\""
    if [ "$DEBUG_OUTPUT" == "$TRUE" ]
    then
        debug_echo "cmd" $cmd
    fi
    eval $cmd
    return=$?

    if [ "$return" != "0" ]
    then
        echo -e "[$FULLPATH] - Rename non-compressed file to original filename error [$return]" >> "$ERROR_FILE"
        echo "$cmd" >> "$ERROR_FILE"
        quit $RENAME_NEW_ERROR
    fi
else
    echo -e "[$FULLPATH] - the converted file seems to have gone missing" >> $ERROR_FILE
    quit $MISSING_CONVERTED_FILE
fi

#for (( i=1; i<=$tracksToConvert; i++ ))
#do
#    if [ -e "$DIRNAME/temp-$i.$DTS_EXT" ]
#    then
#        cmd="rm \"$DIRNAME/temp-$i.$DTS_EXT\""
#    else
#        cmd="rm \"$DIRNAME/temp-$i.$TRUEHD_EXT\""
#    fi
if [ -d "$WORKING_DIR" ]
then
    cmd="rm -r \"$WORKING_DIR\""
    if [ "$DEBUG_OUTPUT" == "$TRUE" ]
    then
        debug_echo "cmd" $cmd
    fi
    eval $cmd
    return=$?

    if [ "$return" != "0" ]
    then
        echo -e "[$FULLPATH] - Temp Files Deletion error [$return]" >> "$ERROR_FILE"
	echo "$cmd" >> "$ERROR_FILE"
        quit $TEMP_REMOVE_ERROR
    fi
fi

#    cmd="rm \"$DIRNAME/temp-$i.$AC3_EXT\""
#    eval $cmd
#    return=$?

#    if [ "$return" != "0" ]
#    then
#        echo -e "[$FULLPATH] - Temp Files Deletion error [$return]" >> "$ERROR_FILE"
#	echo "$cmd" >> "$ERROR_FILE"
#        quit $TEMP_REMOVE_ERROR
#    fi
#done
#All done, and everything went fine
quit 0
