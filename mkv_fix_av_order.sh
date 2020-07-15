#!/bin/bash
trap "exit" INT

mkvfile="$1"

# Check if file is MKV 
if  [[ ! -f $mkvfile ]] || [[  "$(file -b "$mkvfile")" != "Matroska data" ]]
then
  echo "MKV file not provdied"
  exit 1
fi

# Check MKV file info
mkvresult=`mkvmerge -i "$mkvfile" | tail -n+2` 

# Count Tracks
trackcount=`echo "$mkvresult" | wc -l`

# If video is first track, nothing to fix
if ( echo "$mkvresult" | head -1 | grep -iq video )
then
  exit 0
fi

# Check if video isn't first track
if ( echo "$mkvresult" | head -1 | grep -iqv video )
then

  echo "fixing AV order $mkvfile"
  filebasename=${mkvfile%.*}
  audfilename="${filebasename}_A.mkv"
  vidfilename="${filebasename}_V.mkv"
  extrasfilename="${filebasename}_E.mkv"
  renamedfile="${filebasename}.mkv.old"

  # Extract audio
  mkvmerge -q -o "$audfilename" -D -S -B -T --no-chapters -M --no-global-tags "$mkvfile"
  # Extract video
  mkvmerge -q -o "$vidfilename" -A -S -B -T --no-chapters -M --no-global-tags "$mkvfile"
  # Extract extras/attachments
  mkvmerge -q -o "$extrasfilename" -A -D "$mkvfile"  
  # Rename current file to .old
  mv "$mkvfile" "$renamedfile"
  # Combine video, audio, extra
  mkvmerge -q -o "$mkvfile" "$vidfilename" "$audfilename" "$extrasfilename"
  rm "$audfilename"
  rm "$vidfilename"
  rm "$extrasfilename"
  if [ -f "$renamedfile" ] && [ -f "$mkvfile" ]
  then
    rm "$renamedfile"
    echo "$mkvfile AV order fixed"
  else
    echo "Error fixing AV order $mkvfile."
    mv "$renamedfile" "$mkvfile"
  fi
fi
