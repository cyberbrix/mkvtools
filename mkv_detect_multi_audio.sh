#!/bin/bash
# detect if there are multiple audio tracks. 
# silent output if only 1 audio track found
# requires  mkvmerge, jq [optional]
# bash 4+

trap "exit" INT


# Testing Bash. Requires 4+. Explicit validation, not just exit if less
if [ "${BASH_VERSINFO[0]}" -ge 4 ]
then
:
else
  echo "Need at least bash 4.0 to run this script."
  exit 1
fi

# Check if mkvmerge installed
if ! type mkvmerge &> /dev/null
then
  echo "mkvmerge is not installed"
  exit 1
fi

# If no file/directory is given, work in local directory
if [ "$1" = "" ]; then
  DIR="."
else
  DIR="$1"
fi

# Get all the MKV files in this dir and its subdirs
find "$DIR" -type f -name '*.mkv' -print0 | while IFS= read -r -d '' mkvfile
do

  audiotracks=`mkvmerge -i "$mkvfile" | grep -cE "Track ID [0-9]*: audio"`
  #output="$mkvfile"

  # Check if it has more than one audio track
  if [ $audiotracks == 1 ]
  then
    #echo "$mkvfile - 1 audio track found"
    continue
  fi


  # Check if JQ installed
  if ! type jq &> /dev/null
  then
    echo "$mkvfile - $audiotracks audio tracks found"
    continue
  else
    echo "$mkvfile"
    mkvmerge -J "$mkvfile" | jq -r '.tracks[] | select(.type=="audio") | "\(.id), \(.codec),\(.properties.language),\(.properties.track_name)"'
  fi
done
