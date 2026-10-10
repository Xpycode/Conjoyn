#!/bin/bash
set -euo pipefail
E3_BASE="$(cd "$(dirname "$0")" && pwd)"
E3_APP="$E3_BASE/export/Conjoyn.app"
E3_STAGE="$E3_BASE/dmg-stage"
E3_DMG="$E3_BASE/Conjoyn-1.0.6-pre-notary.dmg"
[ ! -e "$E3_DMG" ] || { echo 'Refusing to overwrite existing candidate'; exit 1; }
mkdir -p "$E3_STAGE"
ditto "$E3_APP" "$E3_STAGE/Conjoyn.app"
create-dmg --volname Conjoyn --volicon "$E3_APP/Contents/Resources/AppIcon.icns" --window-pos 200 120 --window-size 600 400 --icon-size 128 --icon Conjoyn.app 150 195 --hide-extension Conjoyn.app --app-drop-link 450 195 --no-internet-enable "$E3_DMG" "$E3_STAGE"
codesign --force --sign 'Developer ID Application' --timestamp "$E3_DMG"
codesign --verify --verbose=2 "$E3_DMG"
shasum -a 256 "$E3_DMG" "$E3_BASE/Conjoyn-1.0.6-pre-notary.zip"
