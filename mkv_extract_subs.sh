#!/bin/bash
# Extract subtitles from each MKV file in the given directory
# requires mkvtoolnix - mkvmerge, mkvextract
# ffmpeg, ffprobe for closed captions
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

# Check if ffprobe installed
if ! type ffprobe &> /dev/null
then
  echo "ffprobe is not installed"
  ffprobecheck=1
fi

# Check if ffmpeg installed
if type ffmpeg &> /dev/null
then
  if (! ffmpeg -nostdin -hide_banner -bsfs | grep -iq 'filter_units')
  then
    ffmpegfiltercheck=1
  fi
else
  ffmpegcheck=1
fi


# If no file/directory is given, work in local directory
if [ "$1" = "" ]; then
  DIR="."
else
  DIR="$1"
fi

# Establish variables and arrays

# Regex for mkvmerge output
#mkvsubregex='Track ID ([0-9]{1,2}): subtitles \((.*)\)'
# Regex for ffprobe mkvmerge output
#mkvsubregex=' +?Stream #[0-9]:([0-9]{1,2})\((.*)\): Subtitle: (.*)'
mkvsubregex=' +?Stream #[0-9]:([0-9]{1,2})(\((.*)\))?: Subtitle: ([^[:space:]]+)'

# Array for subtitle types
declare -A subtypes=(  [subrip]="srt" [ass]="ass" [WebVTT]="vtt" [hdmv_pgs_subtitle]="sup" )

# Get all the MKV files in this dir and its subdirs
find "$DIR" -type f -name '*.mkv' -print0 | while IFS= read -r -d '' filename
do
  
  # Check if file is MKV
  if  [[ "$(file -b "$filename")" != "Matroska data" ]]
  then
    echo "\"$filename\" is not a valid MKV"
    continue
  fi

  #echo "processing $filename"
  # Get basename for subtitle
  filebasename=$(basename "${filename%.*}")
  filepath=$(dirname "${filename}")
  
  # Reset subtitle count
  subcount=0  

  # Reset vobsubcount  
  vobsubcount=0

  # Reset Unknown/Error Count
  unknowncount=0

  # Reset sub tracks for removal
  #removesubtrack=""

  # Find out which tracks contain the subtitles
  while read -r subline
  do
    ((subcount++))

    # Regex the number of the subtitle track and sub type
    if [[ $subline =~ $mkvsubregex ]]
#    tracknumber="${BASH_REMATCH[1]}"
#    trackformat="${BASH_REMATCH[2]}"

    # ffprobe Regex the track info
    then
      tracknumber="${BASH_REMATCH[1]}"
      tracklanguage="${BASH_REMATCH[3]}"
      trackformat="${BASH_REMATCH[4]}"
      trackextra="${BASH_REMATCH[5]}"
    else
      ((unknowncount++))
      ((subcount--))
      continue
    fi

    # Check if accepted language
    # eng - English
    # en - English
    # mul - multiple languages
    # und - unknown

    declare -a AllowedLang=("eng" "en" "mul" "und")

    # Set blank language as undetermined
    if [ -z "$tracklanguage" ]
    then
      tracklanguage="und"
    fi


    # Skip if not acceptable language
    if [[ ${AllowedLang[*]} =~ (^|[[:space:]])"$tracklanguage"($|[[:space:]]) ]]
    then
      :
    else
      ((subcount--))
      continue
    fi

   # check if forced track
    if [ "${trackextra,,}" = "*forced*" ]
    then
      trackforced=1
    fi
    # dealing with idx/sub/sup files.
    if [[ "$trackformat" == dvd_subtitle* ]]
    #if [[ "$trackformat" == "VobSub" ]]
    then
      # mkvextract removes the file extension, so adding it back to compensate.
      mkvextract -q tracks "$filename" $tracknumber:"$filepath/$filebasename-$tracknumber.mkv"
      if [ ! -f "$filepath/$filebasename.sub" ] && [ ! -f "$filepath/$filebasename.idx" ]
      then
        mv "$filepath/$filebasename-$tracknumber.sub" "$filepath/$filebasename.sub"
        mv "$filepath/$filebasename-$tracknumber.idx" "$filepath/$filebasename.idx"
      else
        mv "$filepath/$filebasename-$tracknumber.sub" "$filepath/$filebasename.$tracknumber.sub"
        mv "$filepath/$filebasename-$tracknumber.idx" "$filepath/$filebasename.$tracknumber.idx"
      fi

      # count vobsubs not as subs
      ((vobsubcount++))
      ((subcount--))
      continue
    fi
    if [[ "$trackformat" == "hdmv_pgs_subtitle," ]]
    then
      mkvextract -q tracks "$filename" $tracknumber:"$filepath/$filebasename-$tracknumber.sup"

      # count sup not as subs
      ((vobsubcount++))
      ((subcount--))
      continue
    fi

    ext="${subtypes[$trackformat]}"

    # Extract track to .tmp file
    mkvextract -q tracks "$filename" $tracknumber:"$filepath/$filebasename.$ext.tmp"

    # Get file size
    subfilesize=$(stat -c%s "$filepath/$filebasename.$ext.tmp")

    # If unknown language test English words. Sets eng or en as passing English test
    if [[ "$tracklanguage" == "und" || "$tracklanguage" == "mul"  ]]
    then
      TotalWords=$(wc -w < "$filepath/$filebasename".$ext.tmp)
      EnglishCommonWords=$(grep -Eo -i '\b(the|and|is|in|to|of|that|it|for|on|with|as|at|by|from|this|be|or|an)\b' "$filepath/$filebasename".$ext.tmp | wc -l)
      EnglishPercent=$(( 100 * EnglishCommonWords / (TotalWords == 0 ? 1 : TotalWords) ))
      langtest=$(grep -icE ' you | with | and | that ' "$filepath/$filebasename".$ext.tmp)
    else
      langtest=11
      EnglishPercent=50
    fi

    # Check if subtitle passes our language filter (10 or more matches)
    #if [ $langtest -ge 10 ]
    #echo "$filepath/$filebasename.$ext.tmp Stopwords: $EnglishCommonWords / $TotalWords words = $EnglishPercent%"

    if [ $EnglishPercent -ge 10 ]
    then
      fileext="en.$ext"

      # Add checking for SDH - will not always detect properly in not srt files
      sdhtest=$(grep -icE '[[(].*?[])]' "$filepath/$filebasename".$ext.tmp)
	  if [ $sdhtest -ge 10 ]
      then
        fileext="en.sdh.$ext"
      fi

      # check if under 10KB, likely indicator of forced subs
      if [[ $subfilesize -le 10240 || $trackforced -eq 1  ]]
      then
        fileext="en.forced.$ext"
      fi

      # Confirm english sub doesn't exist. add track number if it does
      if [ -f "$filepath/$filebasename.$fileext" ]
      then
        fileext="$tracknumber.en.$ext"
      fi
    else
      # Not English. Add a number to the filename
      fileext="$tracknumber.und.$ext"
    fi

    #Insert command to rename file to determined file name
    mv "$filepath/$filebasename.$ext.tmp" "$filepath/$filebasename.$fileext"

    # Convert SSA to srt if ffmpeg installed
    if [[ "$trackformat" == "ass" ]] && [ -z "$ffmpegcheck" ]
    then
      # find new file ext, update variables
      oldfileext=$fileext
      fileext=${oldfileext//ass/srt}
      ext="srt"
      
	  # Confirm english sub doesn't exist. add track number if it does
      if [ -f "$filepath/$filebasename.$fileext" ]
      then
        fileext="$tracknumber.$fileext"
      fi
	  
	  # convert ssa to srt
      ffmpeg -nostdin -hide_banner -loglevel warning -abort_on empty_output -i "$filepath/$filebasename.$oldfileext" -codec:s text "$filepath/$filebasename.$fileext"
      # if no errors, delete the ssa
      if [ $? -eq 0 ]
      then
        rm "$filepath/$filebasename.$oldfileext"
      else
        rm "$filepath/$filebasename.$fileext"
      fi
    fi

    # Identify as image based, not text
    if [[ "$trackformat" == "hdmv_pgs_subtitle" ]]
    then
      ((vobsubcount++))
      ((subcount--))
    fi
 done < <(ffprobe "$filename" |& grep Stream | grep -i 'subtitle')


  # Processing if subs are found
  if [[ $subcount -gt 0  ||  $vobsubcount -gt 0 ]]
  then
    if [ $subcount -gt 0 ]
    then
      echo "$filename - $subcount text subtitles found"
    fi

    if [ $vobsubcount -gt 0 ]
    then
      echo "$filename - $vobsubcount image subtitles found - no language checks"
    fi

    # Creates MKV without subtitles
    mkvmerge -o "$filepath/tmp.mkv" -q -S "$filename"

    # Appling permissions from original file
    chmod --reference="$filename"  "$filepath/tmp.mkv"

    # Renaming files
    mv "$filename" "$filename.orig"
    mv "$filepath/tmp.mkv" "$filename"
    # Delete original file
    rm "$filename.orig"

    # sorts through each file extension. 
    for i in $(find "$filepath" -type f -not -name "*.mkv" -name "$filebasename.*"| sed 's|.*\.||' | sort -u)
    do 
      #If SDH  file is only English sub, remove SDH from file name. Will not clobber
      if [ -f "$filepath/$filebasename.en.sdh.$i" ] && [ ! -f "$filepath/$filebasename.en.$i" ]
      then
        mv "$filepath/$filebasename.en.sdh.$i" "$filepath/$filebasename.en.$i"
      fi
    done
  fi 


  # Continue if ffprobe missing
  if [ -n "$ffprobecheck" ]
  then
    echo "failed probe check"
    continue
  fi

  # check for CC
  if (ffprobe -hide_banner -select_streams v "$filename" 2>&1 | grep -q "Closed Captions")
    then
       if [ -n "$ffmpegcheck" ]
       then
         echo "$filename - ffmpeg not installed, closed captions not extracted."
         continue
       fi
      ffmpeg -nostdin -hide_banner -loglevel quiet -f lavfi -i "movie=$filepath/$filebasename.mkv[out0+subcc]" -map s "$filepath/$filebasename.cc.srt" 
      #ffmpeg -nostdin -hide_banner -loglevel warning -f lavfi -i "movie=$filename[out0+subcc]" -map s "$filepath/$filebasename.cc.srt"
      if [ $? -ne 0 ]
      then
        echo "$filename - ffmpeg had an issue extracting closed captions."
        continue
      fi
    if [ -n "$ffmpegfiltercheck" ]
    then
      echo "$filename - ffmpeg missing 'filter_units' bitstream filter. Check version. CC remain in file."
      continue
    fi
    
    randtemp=$RANDOM
    ffmpeg -nostdin -hide_banner -loglevel warning  -i "$filename" -codec copy -bsf:v 'filter_units=remove_types=6' "$filepath/tmp-$randtemp.mkv"
    if [ $? -ne 0 ]
    then
      echo "$filename - ffmpeg had an issue removing closed captions. 'tmp-$randtemp.mkv' may need to be manually deleted"
      continue
    fi
    # Applying permissions from original file
    chmod --reference="$filename" "$filepath/tmp-$randtemp.mkv"

    mv "$filename" "$filename.old" && mv "$filepath/tmp-$randtemp.mkv" "$filename" && echo "$filename - closed captions extracted" || echo "$filename - file rename issue. Check $filepath"
    if [ $? -eq 0 ]
    then
      rm "$filename.old"
    fi
  fi

done
