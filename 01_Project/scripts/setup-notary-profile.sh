#!/usr/bin/env bash
# One-time helper: recreate the `conjoyn-notary` notarytool keychain profile on this Mac.
#
# Keychains don't sync across Macs, so a fresh release Mac has the App Store Connect API key
# in 99-AUTH/ but no stored profile. This reads the .p8 + key-id + issuer straight from
# 99-AUTH/ and stores them in the login keychain. No secret is printed or copied into the repo.
#
# Usage:  01_Project/scripts/setup-notary-profile.sh
# Override the auth dir with AUTH_DIR=... if it lives elsewhere.
set -euo pipefail

AUTH_DIR="${AUTH_DIR:-/Users/sim/ProgrammingProjects/99-AUTH}"
PROFILE="${NOTARY_PROFILE:-conjoyn-notary}"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }

[ -d "$AUTH_DIR" ] || { echo "error: auth dir not found: $AUTH_DIR" >&2; exit 1; }

# --- locate the .p8 API key ------------------------------------------------
P8="$(ls "$AUTH_DIR"/AuthKey_*.p8 2>/dev/null | head -1 || true)"
[ -n "$P8" ] || { echo "error: no AuthKey_*.p8 in $AUTH_DIR" >&2; exit 1; }

# key-id is the XXXX in AuthKey_XXXX.p8
KEY_ID="$(basename "$P8" | sed -E 's/^AuthKey_([A-Z0-9]+)\.p8$/\1/')"
[ -n "$KEY_ID" ] || { echo "error: could not derive key-id from $(basename "$P8")" >&2; exit 1; }

# --- issuer UUID from IssuerID.rtf (strip RTF, grab the UUID) ---------------
ISSUER_FILE="$AUTH_DIR/IssuerID.rtf"
[ -f "$ISSUER_FILE" ] || { echo "error: $ISSUER_FILE not found" >&2; exit 1; }
ISSUER="$(grep -oiE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "$ISSUER_FILE" | head -1 || true)"
[ -n "$ISSUER" ] || { echo "error: no issuer UUID found in $ISSUER_FILE" >&2; exit 1; }

bold "Storing notarytool profile '$PROFILE'"
echo "  key:    $P8"
echo "  key-id: $KEY_ID"
echo "  issuer: $ISSUER"

xcrun notarytool store-credentials "$PROFILE" \
    --key    "$P8" \
    --key-id "$KEY_ID" \
    --issuer "$ISSUER"

bold "Verifying profile works against Apple…"
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null \
    && bold "✓ Profile '$PROFILE' is live. Re-run make-dmg.sh now." \
    || { echo "error: profile stored but history check failed — check the credentials." >&2; exit 1; }
