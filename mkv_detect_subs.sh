#!/bin/bash
# detect text, image and closed caption subs from each MKV file in the given directory
# requires  mkvmerge, mkvextract, and ffprobe (for CC)
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

# Check if mkvextract installed
if ! type mkvextract &> /dev/null
then
  echo "mkvextract is not installed"
  exit 1
fi


cccheckfail=0
# Check if ffprobe installed
if ! type ffprobe &> /dev/null
then
  echo "ffprobe is not installed"
  #exit 1
  cccheckfail=1
fi



# If no file/directory is given, work in local directory
if [ "$1" = "" ]; then
  DIR="."
else
  DIR="$1"
fi

# Establish variables and arrays

# Regex for mkvmerge output
mkvsubregex='Track ID ([0-9]{1,2}): subtitles \((.*)\)'

# Array for subtitle types
declare -A subtypes=( [SubRip/SRT]="srt" [SubStationAlpha]="ssa" [HDMV PGS]="sup" [WebVTT]="webvtt")

# Get all the MKV files in this dir and its subdirs
find "$DIR" -type f -name '*.mkv' -print0 | while IFS= read -r -d '' filename
do
  
  # Check if file is MKV
  if  [[ "$(file -b "$filename")" != "Matroska data" ]]
  then
    echo "\"filename\" is not a valid MKV"
    continue
  fi

  # Get basename for subtitle
  filebasename=` basename "${filename%.*}"`
  filepath=`dirname "${filename}"`
  
  # Reset subtitle count
  subcount=0  

  # Reset vobsubcount  
  vobsubcount=0

  # Reset CC sub count
  ccsubcount=0

  if [ $cccheckfail -eq 0 ]
  then
    ffprobe -hide_banner -select_streams v "$filename" 2>&1 | grep -q "Closed Captions" && ccsubcount=1
    #ffprobe -hide_banner -select_streams v "$filename" 2>&1 | grep -q "Closed Captions" || ffprobe -hide_banner -f lavfi -i movie="$filename"[out+subcc] 2>&1 | grep -q "eia_608"  && ccsubcount=1
  fi

  # Find out which tracks contain the subtitles
  while read subline  
  do
    ((subcount++))
    
    # Regex the number of the subtitle track and sub type
    [[ $subline =~ $mkvsubregex ]]
    tracknumber="${BASH_REMATCH[1]}"
    trackformat="${BASH_REMATCH[2]}"    

    # dealing with idx/sub files.
    if [ "$trackformat" = "VobSub" ]
    then

      # count vobsubs not as subs
      ((vobsubcount++))
      ((subcount--))
      continue
    fi

    ext="${subtypes[$trackformat]}"    
    
  done < <(mkvmerge -i "$filename" | grep 'subtitles')
  

  # If subs are found
  if [ $subcount -gt 0 ]
  then
    echo "$filename - $subcount text subtitles"
  fi

  if  [ $vobsubcount -gt 0 ]
  then
    echo "$filename - $vobsubcount image subtitles"
  fi

  if [ $ccsubcount -eq 1 ]
  then
    echo "$filename - has closed captions"
  fi

done
