#!/bin/bash
# cleans metadata from MKV files. Also prints when files have multiple audio or video language files
# Only cleans first audio and first video file track titles
# removes all attachments

# Testing Bash. Requires 4+. Explicit validation, not just exit if less
if [ "${BASH_VERSINFO[0]}" -ge 4 ]
then
:
else
  echo "Need at least bash 4.0 to run this script."
  exit
fi

#check if mkvpropedit installed
if ! type mkvpropedit &> /dev/null
then
  echo "mkvpropedit is not installed"
  exit 1
fi

#check if mediainfo installed
if ! type mediainfo &> /dev/null
then
  echo "mediainfo is not installed"
  exit 1
fi

SHOWOUTPUT="YES"

for z in "$@"
do
case $z in
    -p=*)
    DIR="${z#*=}"
    shift # past argument=value
    ;;
    --clean)
    ACTION="CLEAN"
    shift # past argument with no value
    ;;
    --s)
    SHOWOUTPUT="NO"
    shift # past argument with no value
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
    echo "    This script search MKV files for rogue metadata, like video/audio track file titles,"
    echo "    tags such as XML tags, attachments (images, fonts, random files)"
    echo "    It will also identify when more than 1 audio or video (rare) track are found"
    echo "    You can list the results, which will output in CSV format"
    echo ""
    echo "    Usage:"
    echo "   ./mkvinfoclean.sh -p=\"/path/to/dir/\" [--clean] [--s]"
    echo ""
    echo "    Arguments:"
    echo "    -p path  to directory. without a value, will use current directory"
    echo "    --s part of a script. will not print headers, etc. useful for running 1 file at a time"

    echo ""
    echo "    --clean  optional. Script will go through and clean the following fields:"
    echo "    Tags, attachments, general title, date,segment info, previous/next filenames, uids,"
    echo "    track names for the first audio and video file"
    echo "    See https://matroska.org/technical/specs/index.html for info"
    echo "    Results will be posted after commands complete"
    echo " "
    echo "    Files with only A/V extra tracks will not be cleaned"
    echo "    These are fields where I found misc data tucked in there by various authors. This could change."
    echo ""
    echo "    .mkvinfoclean.ini  is created in \$HOME of the account running the script"
exit
    }

if [  "$function" = "help" ]
then
help_screen
fi

#change to location if different than below. Should be in user's home directory. will be created if not exists.
configfile="$HOME/.mkvinfoclean.ini"

#check for configuration file
if [ ! -f "$configfile" ]
then
echo "$configfile is missing. Creating file now"
echo "General;%CompleteName%:%Title%:%Description%:%Attachments%:%VideoCount%:%AudioCount%:" > "$configfile"
echo "Video;%Title%:">> "$configfile"
echo "Audio;%Title%">> "$configfile"
fi

# If no file/directory is given, work in local directory
if [ "$DIR" = "" ]
then
  DIR="."
fi

# Test if file or directory is given
if [[ -f "$DIR" ]]
then
SHOWOUTPUT="NO"
fi

if [[ -d "$DIR" ]]
then
    :
elif [[ -f "$DIR" ]]
then
    SHOWOUTPUT="NO"
else
    echo "$DIR is not valid"
    exit 1
fi


if [ "$ACTION" = "CLEAN" ]
then
tmpfile1=$(mktemp /tmp/mediaclean.XXXXXX)
tmpfile2=$(mktemp /tmp/mediaclean.XXXXXX)
fi


# CSV Header
if [ "$SHOWOUTPUT" = "YES" ]
then
echo "\"CompleteName\",\"Title\",\"Description\",\"Attachments\",\"VidTitle\",\"AudTitle\",\"VidCount\",\"AudCount\""
fi

while IFS=':' read -r CompleteName Title Description Attachments VidCount AudCount VidTitle AudTitle
do 

  # skip files that are not impacted - single a/v and no metatadata
  if [ ",\"$Title\",\"$Description\",\"$Attachments\",\"$VidTitle\",\"$AudTitle\",\"$VidCount\",\"$AudCount\"" = ",\"\",\"\",\"\",\"\",\"\",\"1\",\"1\"" ]
  then
  continue
  fi

  # check if only A/V track count is impacted or metadata also exists
  AVONLY=0
  if [ ",\"$Title\",\"$Description\",\"$Attachments\",\"$VidTitle\",\"$AudTitle\"," = ",\"\",\"\",\"\",\"\",\"\"," ]
  then
  AVONLY=1  
  fi

  echo "\"$CompleteName\",\"$Title\",\"$Description\",\"$Attachments\",\"$VidTitle\",\"$AudTitle\",\"$VidCount\",\"$AudCount\""
  removeattachments=""
  if [ ! -z "$Attachments" ]
   then 
   IFS='/' read -r -a attacharray <<< "$Attachments"
   attachcount=${#attacharray[@]}
   Attnum=1
   while [  $Attnum -le $attachcount ]; do
	   removeattachments="--delete-attachment $Attnum $removeattachments"
       let Attnum=Attnum+1 
   done
   unset IFS
  fi
 
  if [ "$ACTION" = "CLEAN" ] && [ $AVONLY = 0 ]
  then
    #echo "File: $CompleteName" >> "$tmpfile1"
    mkvpropedit -r "$tmpfile2" "$CompleteName" $removeattachments --tags all: -d title -d date -d segment-uid -d segment-filename -d prev-filename -d next-filename -d prev-uid -d next-uid --edit track:v1 --delete name --edit track:a1 --delete name 
   if [ $? -eq 0 ]
   then
    echo " - cleaned"
   else
    echo " - check output"
    echo "File: $CompleteName" >> "$tmpfile1"
    cat "$tmpfile2" >> "$tmpfile1"
    SHOWERROR="YES"
   fi

    #cat "$tmpfile2" >> "$tmpfile1"
  fi

# Old way of detecting.
done< <( find "$DIR" -type f -iname "*.mkv" -exec mediainfo --Inform=file://$configfile "$1"  {} \;)


if [ "$ACTION" = "CLEAN" ] && [ "$SHOWERROR" = "YES" ]
then
if [ "$SHOWOUTPUT" = "YES" ]
then
echo ""
echo ""
echo "RESULTS:"
echo ""
fi

cat "$tmpfile1"
rm "$tmpfile1"
rm "$tmpfile2"

fi

exit 0
