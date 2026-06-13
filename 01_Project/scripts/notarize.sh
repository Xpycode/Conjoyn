#!/bin/bash
# notarize.sh — build, sign, notarize, and staple Conjoyn for direct distribution.
#
# Archive → Developer-ID export flow:
#   1. Clean `xcodebuild archive`, then `-exportArchive` with method=developer-id. The EXPORT pass
#      (not a plain `build`) is what re-signs every NESTED Mach-O with Developer ID + hardened
#      runtime + secure timestamp — Sparkle's Autoupdate/Updater.app/Installer.xpc/Downloader.xpc
#      ship ADHOC-signed inside the SPM artifact and a plain `xcodebuild build` leaves them adhoc,
#      which Apple's notary service rejects. (Never `codesign --deep` to fix it — that mis-signs the
#      XPC services → "Failed to gain authorization." Export re-signs them correctly. See the sibling
#      Penumbra/CropBatch runbooks.)
#   2. Verify EVERY nested Mach-O is Developer ID + hardened-runtime (app wrapper, ffmpeg, ffprobe,
#      Sparkle.framework, Autoupdate, Updater, Installer.xpc, Downloader.xpc) before a notary round-trip.
#   3. Zip the .app and submit to Apple's notary service (notarytool submit --wait).
#   4. Staple the ticket onto the .app and confirm Gatekeeper now accepts it.
#
# Credentials: a one-time keychain profile holds the App Store Connect API key. Create it once:
#
#   xcrun notarytool store-credentials "$NOTARY_PROFILE" \
#       --key   /path/to/AuthKey_XXXXXXXXXX.p8 \
#       --key-id    <KEY_ID> \
#       --issuer    <ISSUER_ID>
#
# Then this script needs no secrets. Override the profile name via NOTARY_PROFILE env var.
set -euo pipefail

# --- config ----------------------------------------------------------------
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"        # …/01_Project
PROJECT="${PROJECT_DIR}/Conjoyn.xcodeproj"
SCHEME="Conjoyn"
TEAM_ID="FDMSRXXN73"
IDENTITY="Developer ID Application"
NOTARY_PROFILE="${NOTARY_PROFILE:-conjoyn-notary}"

DERIVED="${PROJECT_DIR}/build/notarize"
ARCHIVE="${DERIVED}/Conjoyn.xcarchive"
EXPORT_DIR="${DERIVED}/export"
EXPORT_OPTS="${DERIVED}/exportOptions.plist"
APP="${EXPORT_DIR}/Conjoyn.app"               # the exported, Developer-ID-resigned app
OUT_DIR="${PROJECT_DIR}/../04_Exports"
ZIP="${OUT_DIR}/Conjoyn.zip"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }

# --- 0. preflight: credentials exist? --------------------------------------
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "error: no notarytool keychain profile '$NOTARY_PROFILE'." >&2
    echo "Create it once with 'xcrun notarytool store-credentials' (see header of this script)." >&2
    exit 1
fi

# --- 1a. clean archive -----------------------------------------------------
bold "==> Archiving Release (Developer ID, hardened runtime)…"
rm -rf "$DERIVED"
mkdir -p "$DERIVED"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    clean archive

[ -d "$ARCHIVE" ] || { echo "error: archive did not produce $ARCHIVE" >&2; exit 1; }

# --- 1b. export Developer ID (re-signs ALL nested code) --------------------
bold "==> Exporting Developer-ID app (re-signs nested Sparkle/XPC + helpers)…"
cat > "$EXPORT_OPTS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST

rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$EXPORT_OPTS" \
    -exportPath "$EXPORT_DIR"

[ -d "$APP" ] || { echo "error: export did not produce $APP" >&2; exit 1; }

# --- 2. verify EVERY nested Mach-O before we waste a notary round-trip ------
# Each must be Developer ID + hardened runtime (flags=0x10000(runtime)) — an adhoc nested binary
# (flags=…0x10002(adhoc,runtime)) passes `--deep --strict` locally but is REJECTED by notarization.
bold "==> Verifying signatures (app + helpers + Sparkle nested Mach-Os)…"
codesign --verify --deep --strict --verbose=2 "$APP"

SPK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
assert_devid_runtime() {
    local label="$1" path="$2"
    [ -e "$path" ] || { echo "error: $label missing at $path" >&2; exit 1; }
    # Capture first (no pipe): `grep -q` would SIGPIPE codesign and, under `set -o pipefail`,
    # fail the pipeline even though the binary is correctly signed.
    local info; info="$(codesign -dvv "$path" 2>&1)"
    case "$info" in
        *"flags=0x10000(runtime)"*) ;;
        *) echo "error: $label is not hardened-runtime (adhoc nested binary?) — notary would reject" >&2
           printf '%s\n' "$info" | grep -i 'flags=' >&2 || true; exit 1 ;;
    esac
    case "$info" in
        *"Authority=Developer ID Application"*) ;;
        *) echo "error: $label is not Developer-ID signed — notary would reject" >&2; exit 1 ;;
    esac
    echo "  ✓ ${label}"
}
assert_devid_runtime "app wrapper"     "$APP"
assert_devid_runtime "ffmpeg"          "$APP/Contents/Resources/Helpers/ffmpeg"
assert_devid_runtime "ffprobe"         "$APP/Contents/Resources/Helpers/ffprobe"
assert_devid_runtime "Sparkle.framework" "$SPK/Sparkle"
assert_devid_runtime "Autoupdate"      "$SPK/Autoupdate"
assert_devid_runtime "Updater.app"     "$SPK/Updater.app/Contents/MacOS/Updater"
assert_devid_runtime "Installer.xpc"   "$SPK/XPCServices/Installer.xpc/Contents/MacOS/Installer"
assert_devid_runtime "Downloader.xpc"  "$SPK/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"
echo "Signature OK (every nested Mach-O is Developer ID + hardened runtime)."

# --- 3. submit to the notary service ---------------------------------------
mkdir -p "$OUT_DIR"
rm -f "$ZIP"
bold "==> Zipping for submission…"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

bold "==> Submitting to Apple notary service (this can take a few minutes)…"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

# --- 4. staple + final Gatekeeper check ------------------------------------
bold "==> Stapling ticket…"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

bold "==> Gatekeeper assessment…"
spctl -a -vvv -t exec "$APP"

# Re-zip the now-stapled app so the distributed artifact carries the ticket offline.
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

bold "==> Done. Notarized + stapled app: $APP"
echo "Distributable zip (stapled): $ZIP"
