#!/bin/bash

BADLINK=.badlink

if [ "$1" == "-c" ]
then
    filename=$2
    check="true"
    echo "Checking Link mode"
else
    filename=$1
    check="false"
    if [ "`basename "$filename" $BADLINK`" != "`basename "$filename"`" ]
    then
        #file is already marked as a bad link
        echo "File is already marked as a bad link, did you mean to use the check (-c) option?"
        exit 1
    fi
fi

if [ ! -f "$filename" ] && [ ! -L "$filename" ]
then
    echo "ERROR: File [$filename] does not exist"
    echo "USAGE: findLinks [-c] <filename>"
    echo "    -c   Check already marked link"
    echo "filename file to see if it is a link"
    echo "         if -c speciifed, must have an extention of $BADLINK"
    exit 1
fi

if [ "$check" == "true" ]
then
    if [ "`basename "$filename" $BADLINK`" == "`basename "$filename"`" ]
    then
        echo "ERROR: Check specified and file to check [$filename] does not have the $BADLINK extention"
        echo "USAGE: findLinks [-c] <filename>"
        echo "    -c   Check already marked link"
        echo "filename file to see if it is a link"
        echo "         if -c speciifed, must have an extention of $BADLINK"
        exit 1
    fi

    if [ "`head --bytes=4  "$filename"`" != "XSym" ]
    then
        newFilename="`dirname "$filename"`/`basename "$filename" $BADLINK`"
        mv "$filename" "$newFilename"
        echo "$filename NOT a link, recovered as $newFilename"
        exit 0
    fi
elif [ "`file -L --mime-type --brief "$filename"`" == "text/plain" ]
then
    #it is a link file that is being seen as a text file
    if [ "`head --bytes=4  "$filename"`" == "XSym" ]
    then
        mv "$filename" "$filename$BADLINK"
        echo "$filename renamed"
    fi
elif [ -L "$filename" ] && [ ! -e "$filename" ]
then
    #it is a link, but the file does not exist and to Windows it would like a text file
    mv "$filename" "$filename$BADLINK"
    echo "$filename renamed"
fi

