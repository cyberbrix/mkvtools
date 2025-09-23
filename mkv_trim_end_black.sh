#!/bin/bash
# trims the video after the last detected sound. 

# Testing Bash. Requires 4+. Explicit validation, not just exit if less
if [ "${BASH_VERSINFO[0]}" -ge 4 ]
then
:
else
  echo "Need at least bash 4.0 to run this script."
  exit
fi

# check if ffmpeg installed
if ! type ffmpeg &> /dev/null
then
  echo "ffmpeg is not installed"
  exit 1
fi

# check if bc is installed
if ! type bc &> /dev/null
then
  echo "bc is not installed"
  #exit 1
fi


# Function to convert length to seconds
convertsecs() {

if [[ $1 =~ \. ]];
then
  wholesec=$(echo "${1}" | cut -f1 -d.)
  millisec=$(echo "${1}" | cut -f2 -d.)
else
  wholesec=$(echo "${1}" | cut -f1 -d.)
  millisec=0
fi

 ((h=wholesec/3600))
 ((m=(wholesec%3600)/60))
 ((s=wholesec%60))
 printf "%02d:%02d:%02d.$millisec\n" "$h" "$m" "$s"
}

#SHOWOUTPUT="YES"
DELETEOLD="NO"
ACTION="TRIM"
SecondsOfBlack=30
TotalSecondsSaved=0
TotalMBSaved=0

for z in "$@"
do
case $z in
    -p=*)
    DIR="${z#*=}"
    shift 
    ;;
    --test)
    ACTION="TEST"
    shift 
    ;;
    --trust)
    DELETEOLD="YES"
    shift 
    ;;
#    --s)
#    SHOWOUTPUT="NO"
#    shift 
#    ;;
    -s=*)
    SecondsToTrim="${z#*=}"
    shift 
    ;;

    --listall)
    ACTION="LISTALL"
    shift 
    ;;
   --list)
    ACTION="LIST"
    shift 
    ;;
    -b=*)
    SecondsOfBlack="${z#*=}"
    shift 
    ;;
    -h)
    function=help
    shift
    ;;
    --help)
    function=help
    shift
    ;;
esac
done


help_screen() {
    echo ""
    echo "    This script trim the end of MKV files when silence begins."
    echo "    You can list run this with the following options: --test, --trust, --s, --help, -h"
    echo ""
    echo "    Usage:"
    echo "   ./mkv_trim_end_black.sh -p=\"/path/to/dir/\" [--list]  [--trust]"
    echo ""
    echo "    Arguments:"
    echo "    -p=\"path  to directory or file\" - without a value, will use current directory"
#    echo "    --s - will not print output"
    echo "    --trust - will not create backups of the original file"
    echo "    --test - will simulate what the results would be"
    echo "    --listall - same as list, but includes files that wont be trimmed"
    echo "      NOTE: test and list cannot be used at the same time. Pick one"
    echo "    --list - creates a csv of all files and how much can be trimmed"
    echo "    -b=<integer> - (default 30) minumum seconds of silence the end of a file. If less than this amount, will not trim."
    echo "     <WARNING! - Making this time too should could delete legitimate video content without sound>"
    echo "    -s=<integer> - how many seconds to trim from the files, instead of detection. Not commmonly used."
    echo " "
exit
    }

if [  "$function" = "help" ]
then
help_screen
fi

# If no file/directory is provided, work in local directory
if [ "$DIR" = "" ]
then
  DIR="."
fi

# confirms a valid file or path, options to add then commands
if [[ -d "$DIR" ]]
then
  :
  #echo "Valid directory found"
elif [[ -f "$DIR" ]]
then
  :
  #echo "Valid file found"
else
  echo "$DIR is not a valid path"
  exit 1
fi

# If SecondsToTrim is populated, validate it as an integer
if [[ -n "${SecondsToTrim}" ]] && [[ ! $SecondsToTrim =~ ^[0-9]+$ ]]
then
  echo "$SecondsToTrim is set, but is not an integer. Exiting"
  exit 1
fi


# Make CSV Header
#if [ "$ACTION" == "LISTALL" ]
if [[ "$ACTION" == LIST* ]]
then
  echo "\"File\",\"Seconds\",\"Comment\""
fi

#echo "ACTION: $ACTION"

# Get all the MKV files in this dir and its subdirs
while IFS= read -r -d $'\0' filename
do
  # Check if file is MKV
  if  [[ "$(file -b "$filename")" != "Matroska data" ]]
  then
    if [ "$ACTION" == "LISTALL" ]
    then
      echo "\"$filename\",0,\"Not a valid MKV\""
    elif [ "$ACTION" == "LIST" ]
    then
      continue
    else 
      echo "\"$filename\" is not a valid MKV"
    fi
    continue
  fi

#  echo "processing $filename"
  ## Get basename for subtitle
  #filebasename=$(basename "${filename%.*}")
  filepath=$(dirname "${filename}")

  # name temp mkv file
  tempmkvfile="$filepath/$RANDOM.mkv"

  # Test if able to write to location
#  if touch "$tempmkvfile" &> /dev/null
#  then
#    rm "$tempmkvfile"
#  else
#    echo "can't write to $filepath. skipping $filename"
#    continue
#  fi
  
  if ! [[ -w "$filepath" ]]
  then
    if [ "$ACTION" == "LISTALL" ]
    then
      echo "\"$filename\",0,\"Not able to write to $filepath\""
    elif [ "$ACTION" == "LIST" ]
    then
      continue
    else
      echo "Can't write to $filepath. skipping $filename"
    fi
    continue
  fi

  # calculate length of video in seconds. Reset variable for each run.
  vidlength=
  vidlength=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$filename" | xargs printf "%.*f\n" "0")

  # Find 80% of time in, to start searching for silence/black
  eightypercent=
  eightypercent=$(($vidlength -  $vidlength / 5  ))
  #timetostartsearch=$(convertsecs $eightypercent)

  # Find length of last silence
  silenttimes=
  silenttimes=$(ffmpeg -nostdin -hide_banner -ss $eightypercent -i "$filename" -vn -af "silencedetect=n=-50dB:d=$SecondsOfBlack" -f null - 2>&1 | tail -n 1 |  grep "silence_end")
  
  # If no time to trim, move on
  if [[ -z "${silenttimes}" ]] && [[ -z "${SecondsToTrim}" ]]
  then
    if [ "$ACTION" == "LISTALL" ]
    then
      echo "\"$filename\",0,\"Nothing to trim\""
    elif [ "$ACTION" == "LIST" ]
    then
      continue
   # else
      #echo "0 seconds would be trimmed from $filename"
    fi
    continue
  fi

  # establish regex to identify when silence ends and silence duration
  timepattern=
  timepattern='silence_end: ([0-9]+\.[0-9]+) \| silence_duration: ([0-9]+\.[0-9]+)'

  [[ $silenttimes =~ $timepattern ]]
  # silenceend="${BASH_REMATCH[1]}"
  silenceduration="${BASH_REMATCH[2]}"

  # if SecondsToTrim has been populated, replace silence duration
  if [[ -n "${SecondsToTrim}" ]]
  then
    silenceduration=$SecondsToTrim
  fi

  # calculate video end time
  newvideoend=$(bc <<< "$vidlength-$silenceduration")

  # find the file size of the original file
  originalfilesize=
  originalfilesize=$(stat -c%s "$filename")

  # add silence to total silence in seconds
  TotalSecondsSaved=$(bc <<< "$TotalSecondsSaved + $silenceduration")

  if [ "$ACTION" == "TEST" ]
  then
    echo "$silenceduration seconds would be trimmed from $filename"
    continue  
  fi

  # if [ "$ACTION" == "LISTALL" ] || [ "$ACTION" == "LIST" ]
  if [[ "$ACTION" == LIST* ]]
  then
    echo "\"$filename\",$silenceduration,\"N/A\""
    continue
  fi


  # trim video, save as temp file
  if [ "$ACTION" == "TRIM" ]
  then
    ffmpegerror=$(ffmpeg -nostdin -hide_banner -loglevel error -xerror -ss 00:00:00 -to "$newvideoend" -i "$filename" -c copy "$tempmkvfile" 2>&1)
    ffmpegresult=$?
  fi 
 
  # check result of trimming, move on if error
  if [ "$ffmpegresult" -ne 0 ]
  then
    echo "ffmpeg errored on: $filename. Error: $ffmpegerror"
    continue
  fi

  # find the file size of the new file
  newfilesize=
  newfilesize=$(stat -c%s "$tempmkvfile")

  # calculate saved space
  fileMBsaved=
  fileMBsaved=$(bc <<< "scale=2; ($originalfilesize-$newfilesize) / 1048576")

  # update total size and time
  TotalMBSaved=$(bc <<< "scale=2; $TotalMBSaved + $fileMBsaved")

  # if trim succesful, and trust, delete original
  if [ "$ffmpegresult" -eq 0 ] && [ "$DELETEOLD" == "YES" ]
  then
    rm "$filename"
    sleep 1
    mv "$tempmkvfile" "$filename"
  fi

  # if trim succesful, and not trust, rename original
  if [ "$ffmpegresult" -eq 0 ] && [ "$DELETEOLD" == "NO" ]
  then
    mv "$filename" "$filename.old"
    sleep 1
    mv "$tempmkvfile" "$filename"
  fi

  echo "$filename - $silenceduration seconds & $fileMBsaved MB saved"
done < <(find "$DIR" -type f -name '*.mkv' -print0 2>/dev/null)

# only output if multiple files processed. total seconds saved wouldnt match to last silence duration
if [[ "$silenceduration" != "$TotalSecondsSaved" ]] && [ "$ACTION" != "LISTALL" ]
then
  echo -n "$TotalSecondsSaved seconds" 
  if [ "$ACTION" == "TRIM" ]
  then
    echo -n " & $TotalMBSaved MB"
  fi
  if [ "$ACTION" == "TEST" ]
  then
    echo -n " would be"
  fi
  if [ "$ACTION" == "LIST" ]
  then
    echo -n " would be"
  fi

  echo " trimmed from all files"
fi

exit 0
