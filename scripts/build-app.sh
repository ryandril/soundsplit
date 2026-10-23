#!/bin/bash
# Builds build/SoundSplit.app (ad-hoc signed) and build/SoundSplit.zip.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
app=build/SoundSplit.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/SoundSplit "$app/Contents/MacOS/"
cp Resources/Info.plist "$app/Contents/"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$app/Contents/Resources/"

codesign --force --sign - --timestamp=none "$app"
(cd build && rm -f SoundSplit.zip && ditto -c -k --keepParent SoundSplit.app SoundSplit.zip)
echo "Built $app"
