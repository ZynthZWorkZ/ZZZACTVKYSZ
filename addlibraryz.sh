#!/bin/sh

folder_dialog() {
  result=$(osascript << EOT
    tell application "Finder"
      activate
      set fpath to POSIX path of (choose folder)
      return fpath
    end tell
EOT
  )
  echo "$result"
}

# Ask for folder
lib=$(folder_dialog)

if [ ! -d "$lib" ]; then
  echo "🥁 Invalid Kontakt library path"
  printf "🎹 Press Enter to continue..."
  read dummy
  exit 1
fi

# Path must begin with "/Volumes"
case "$lib" in
  /Volumes/*) ;;
  *)
    vol=$(ls -l /Volumes | grep ' -> /' | \
      awk '{for (i=9;i<=NF;i++) printf $i " "; print ""}' | \
      sed 's/ -> \///')
    lib="/Volumes/$vol$lib"
    ;;
esac

xml=/var/tmp/kontaktLibraryHints.xml

find "$lib" \( -iname "*.nicnt" -o -iname "*_info.nkx" \) -type f | while read file
do
  # Extract library version (`.nicnt` only)
  cver=

  case "$file" in
    *.nicnt)
      cver=$(dd skip=66 count=10 bs=1 if="$file" 2>/dev/null | sed 's/\x00//g')
      echo "$cver" | grep '[0-9]\.[0-9]\.[0-9]' >/dev/null 2>&1 || {
        cver=$(dd skip=66 count=6 bs=1 if="$file" 2>/dev/null | sed 's/\x00//g')
        echo "$cver" | grep '[0-9]\.[0-9]' >/dev/null 2>&1 || cver=
      }
      ;;
    *)
      # Skip `_info.nkx` if `.nicnt` is present
      ldir=$(dirname "$file")
      hasnicnt=$(ls "$ldir" | grep -i '.nicnt' | wc -l)
      [ "$hasnicnt" -ne 0 ] && continue
      ;;
  esac

  # Extract library installation hints XML tree
  awk '/<ProductHints[ >]/, $NF ~ /<\/ProductHints>/' "$file" | \
    LC_ALL=C sed 's/<\/ProductHints>.*/<\/ProductHints>/' | \
    xmllint --format --recover --encode "UTF-8" - > "$xml"

  name=$(xmllint --xpath "string(//Name)" "$xml")
  regkey=$(xmllint --xpath "string(//RegKey)" "$xml")
  plist="/Library/Preferences/com.native-instruments.$regkey.plist"
  xmldist="/Library/Application Support/Native Instruments/Service Center/$name.xml"

  # Check for bad `.nicnt` (unofficial)
  grep -i '<HU>' "$xml" >/dev/null 2>&1; nohu=$?
  grep -i '<JDX>' "$xml" >/dev/null 2>&1; nojdx=$?
  grep -i '<ProductSpecific>' "$xml" >/dev/null 2>&1; nops=$?

  if [ "$nohu" -ne 0 ] && [ "$nojdx" -ne 0 ]; then
    cp "$xml" "$xml.tmp"
    if [ "$nops" -ne 0 ]; then
      sed 's/<\/SNPID>/<\/SNPID>|    <ProductSpecific>|      <HU>6C70AC13E02414D1A552685A1301D859<\/HU>|      <JDX>023733942B73318EAEAD914E3981EC68BE72519A2F5738F828A6A028C4E1DBAC<\/JDX>|      <Visibility type="Number">3<\/Visibility>|    <\/ProductSpecific>/' "$xml.tmp" | tr '|' '\n' > "$xml"
    else
      sed 's/      <Visibility type="Number">/      <HU>6C70AC13E02414D1A552685A1301D859<\/HU>|      <JDX>023733942B73318EAEAD914E3981EC68BE72519A2F5738F828A6A028C4E1DBAC<\/JDX>|      <Visibility type="Number">/' "$xml.tmp" | tr '|' '\n' > "$xml"
    fi
    rm -f "$xml.tmp"
  fi

  # Integrate into Service Center
  sudo mkdir -p "/Library/Application Support/Native Instruments/Service Center"
  sudo chmod 755 "/Library/Application Support/Native Instruments/Service Center"
  sudo cp "$xml" "$xmldist"
  sudo chmod 755 "$xmldist"

  # Set `ContentDir`
  sudo rm -f "$plist"
  ContentDir=$(dirname "$file" | tr / :)
  # replace :: with :
  ContentDir=$(echo "$ContentDir" | sed 's/::/:/g')
  ContentDir=$(echo "$ContentDir" | sed 's/::/:/g')
  sudo defaults write "$plist" ContentDir "${ContentDir#:*:}:"

  # Obtain rest of parameters
  for key in RegKey SNPID Name HU JDX UPID AuthSystem
  do
    val=$(xmllint --xpath "string(//$key)" "$xml")
    if [ -n "$val" ]; then
      sudo defaults write "$plist" "$key" "$val"
    fi
  done

  # Write `ContentVersion`
  if [ -n "$cver" ]; then
    sudo defaults write "$plist" ContentVersion "$cver"
  fi

  # Get `Visibility`
  vis=$(xmllint --xpath "string(//ProductSpecific/Visibility)" "$xml")
  sudo defaults write "$plist" Visibility -int "$vis"

  # Review
  cat "$xml"
  defaults read "$plist"
  rm -f "$xml"
  echo
done

echo "🎸 Have fun! 🎻"
printf "🎹 Press Enter to continue..."
read dummy
