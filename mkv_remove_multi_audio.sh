#!/bin/bash
# remove any extra audio tracks. 
# requires  mkvmerge, mkvextract
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

  # Get track info
   mkvfileinfo=$(mkvmerge -J "$mkvfile")

  # Extract audio track information
  audioinfo=$(echo "$mkvfileinfo" | jq -c '.tracks[] | select(.type=="audio")')

  # count the audio tracks
  audiotrackcount=$(echo "$audioinfo" | wc -l)
  
  if [ "$audiotrackcount" -le 1 ]
  then
    continue
  fi

  echo "Which audio track to keep for: $mkvfile"
  echo "Track, Codec, Language, Name" 
  mkvmerge -J "$mkvfile" | jq -r '.tracks[] | select(.type=="audio") | "\(.id), \(.codec),\(.properties.language),\(.properties.track_name)"'

  echo  
  read -p  "Enter the number of the audio track you want to KEEP: " tracktokeep < /dev/tty
  
  # Get basename for subtitle
  filebasename=$(basename "${mkvfile%.*}")
  filepath=$(dirname "${mkvfile}")

  # Creates MKK with selected audio
  mkvmerge -o "$filepath/tmp.mkv" -q -a $tracktokeep "$mkvfile"
  mkvresultcode=$?

  if [ $mkvresultcode -ne 0 ]
  then
    echo "Error: mkvmerge failed:  $mkvfile"
    continue
  fi


  # Appling permissions from original file
  chmod --reference="$mkvfile"  "$filepath/tmp.mkv"

  # Renaming files
  mv "$mkvfile" "$mkvfile.orig"
  mv "$filepath/tmp.mkv" "$mkvfile"

  # Delete original file
  rm "$mkvfile.orig"

  echo "completed $mkvfile"

done
