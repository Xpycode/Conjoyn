#!/bin/bash
# make-dmg.sh — wrap the notarized Conjoyn.app in a styled, notarized DMG for distribution.
#
# This is the last ship step. It produces 04_Exports/Conjoyn.dmg: a read-only,
# Developer-ID-signed, Apple-notarized, stapled disk image whose window shows the app
# beside an /Applications drop-link. Gatekeeper accepts it offline (the ticket is stapled
# to both the app inside and the DMG itself), so it installs with no "unidentified
# developer" prompt on any Mac.
#
# Flow (inside-out, mirroring notarize.sh):
#   1. Run notarize.sh → a signed + notarized + STAPLED Conjoyn.app at the known build path.
#      (Set SKIP_APP=1 to reuse an already-stapled app — useful when iterating on DMG layout
#       without burning a second app-notarization round-trip.)
#   2. create-dmg → a styled window (volume icon, app icon, /Applications drop-link).
#   3. codesign the DMG (Developer ID Application, --timestamp) — same identity as the app.
#   4. notarytool submit the DMG --wait, then stapler staple it.
#   5. spctl assessment (DMG uses -t open, the install-time check).
#
# Credentials: reuses the same conjoyn-notary keychain profile as notarize.sh (override via
# NOTARY_PROFILE). Create it once with `xcrun notarytool store-credentials` — see notarize.sh.
set -euo pipefail

# --- config ----------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"          # …/01_Project
TEAM_ID="FDMSRXXN73"
IDENTITY="Developer ID Application"
NOTARY_PROFILE="${NOTARY_PROFILE:-conjoyn-notary}"

# Same DERIVED path notarize.sh builds into, so we consume the app it stapled.
DERIVED="${PROJECT_DIR}/build/notarize"
APP="${DERIVED}/Build/Products/Release/Conjoyn.app"

OUT_DIR="${PROJECT_DIR}/../04_Exports"
DMG="${OUT_DIR}/Conjoyn.dmg"
VOLNAME="Conjoyn"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }

# --- 0. preflight ----------------------------------------------------------
command -v create-dmg >/dev/null 2>&1 || {
    echo "error: create-dmg not found. Install it with: brew install create-dmg" >&2
    exit 1
}
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "error: no notarytool keychain profile '$NOTARY_PROFILE'." >&2
    echo "Create it once with 'xcrun notarytool store-credentials' (see notarize.sh header)." >&2
    exit 1
fi

# --- 1. obtain a notarized + stapled app -----------------------------------
if [ "${SKIP_APP:-0}" = "1" ] && [ -d "$APP" ] && xcrun stapler validate "$APP" >/dev/null 2>&1; then
    bold "==> SKIP_APP=1 — reusing already-stapled app at $APP"
else
    bold "==> Building + notarizing the app (delegating to notarize.sh)…"
    NOTARY_PROFILE="$NOTARY_PROFILE" "${SCRIPT_DIR}/notarize.sh"
fi
[ -d "$APP" ] || { echo "error: expected app not found at $APP" >&2; exit 1; }
xcrun stapler validate "$APP" >/dev/null 2>&1 || {
    echo "error: $APP is not stapled — notarize.sh did not complete" >&2; exit 1; }

# --- 2. build the styled DMG -----------------------------------------------
# create-dmg wants a source FOLDER holding only the app; it injects the /Applications link.
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
/usr/bin/ditto "$APP" "$STAGING/Conjoyn.app"

# Reuse the app's own icon as the mounted-volume icon when actool emplaced one.
VOLICON_ARGS=()
APP_ICNS="$APP/Contents/Resources/AppIcon.icns"
[ -f "$APP_ICNS" ] && VOLICON_ARGS=(--volicon "$APP_ICNS")

mkdir -p "$OUT_DIR"
rm -f "$DMG"
bold "==> Building DMG window…"
# create-dmg occasionally trips on a transient "hdiutil: resource busy"; one retry clears it.
for attempt in 1 2; do
    if create-dmg \
        --volname "$VOLNAME" \
        "${VOLICON_ARGS[@]}" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon-size 128 \
        --icon "Conjoyn.app" 150 195 \
        --hide-extension "Conjoyn.app" \
        --app-drop-link 450 195 \
        --no-internet-enable \
        "$DMG" \
        "$STAGING"; then
        break
    fi
    [ "$attempt" = 2 ] && { echo "error: create-dmg failed twice" >&2; exit 1; }
    bold "==> create-dmg hiccup — retrying once…"
    rm -f "$DMG"
    sleep 2
done
[ -f "$DMG" ] || { echo "error: DMG was not produced at $DMG" >&2; exit 1; }

# --- 3. sign the DMG -------------------------------------------------------
bold "==> Signing the DMG…"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"
codesign --verify --verbose=2 "$DMG"

# --- 4. notarize + staple the DMG ------------------------------------------
bold "==> Submitting the DMG to Apple notary service (this can take a few minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

bold "==> Stapling ticket onto the DMG…"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"

# --- 5. final Gatekeeper assessment ----------------------------------------
bold "==> Gatekeeper assessment (install-time)…"
spctl -a -vvv -t open --context context:primary-signature "$DMG"

SIZE="$(du -h "$DMG" | cut -f1)"
bold "==> Done. Notarized + stapled DMG: $DMG ($SIZE)"
echo "Ship this file. It installs offline on any Mac with no Gatekeeper prompt."
