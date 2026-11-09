#!/bin/bash
# Builds the Release Mac app and installs it into /Applications (replacing the old copy).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=/tmp/opc-release
xcodebuild -project OpenPhotoCleaner.xcodeproj -scheme OpenPhotoCleaner -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$OUT" build | tail -3
pkill -x OpenPhotoCleaner || true
sleep 1
rm -rf /Applications/OpenPhotoCleaner.app
cp -R "$OUT/Build/Products/Release/OpenPhotoCleaner.app" /Applications/
echo "Installed /Applications/OpenPhotoCleaner.app"
