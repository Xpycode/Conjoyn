#!/bin/bash
# notarize.sh — build, sign, notarize, and staple Conjoyn for direct distribution.
#
# Inside-out flow:
#   1. Clean Release build signed with "Developer ID Application" (helpers signed by the
#      post-build phase: --options runtime --timestamp, then the .app wrapper over them).
#   2. Verify the signature (deep + strict) and that helpers are hardened + timestamped.
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
APP="${DERIVED}/Build/Products/Release/Conjoyn.app"
OUT_DIR="${PROJECT_DIR}/../04_Exports"
ZIP="${OUT_DIR}/Conjoyn.zip"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }

# --- 0. preflight: credentials exist? --------------------------------------
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "error: no notarytool keychain profile '$NOTARY_PROFILE'." >&2
    echo "Create it once with 'xcrun notarytool store-credentials' (see header of this script)." >&2
    exit 1
fi

# --- 1. clean Developer ID Release build -----------------------------------
bold "==> Building Release (Developer ID, hardened runtime)…"
rm -rf "$DERIVED"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    build

[ -d "$APP" ] || { echo "error: build did not produce $APP" >&2; exit 1; }

# --- 2. verify signing before we waste a notary round-trip -----------------
bold "==> Verifying signature…"
codesign --verify --deep --strict --verbose=2 "$APP"
for h in ffmpeg ffprobe; do
    # Capture first (no pipe): `grep -q` would SIGPIPE codesign and, under `set -o pipefail`,
    # fail the pipeline even though the helper is correctly signed.
    info="$(codesign -dvv "$APP/Contents/Resources/Helpers/$h" 2>&1)"
    case "$info" in
        *"flags=0x10000(runtime)"*) ;;
        *) echo "error: helper '$h' is not hardened-runtime signed" >&2; exit 1 ;;
    esac
done
echo "Signature OK (app + helpers hardened & timestamped)."

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
