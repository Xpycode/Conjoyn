#!/bin/bash
# make-appcast.sh — generate the EdDSA-signed Sparkle appcast for the notarized Conjoyn DMG.
#
# Runs AFTER make-dmg.sh has produced the stapled, notarized 04_Exports/Conjoyn.dmg. It stages that
# DMG under a version-stamped name, runs Sparkle's `generate_appcast` over the staging folder (which
# auto-computes the exact enclosure `length` and signs it with the EdDSA private key), then hand-
# verifies every load-bearing field before the appcast is fit to deploy.
#
# Flow:
#   1. Read the shipped version from the exported app (CFBundleShortVersionString / CFBundleVersion).
#   2. Stage 04_Exports/Conjoyn.dmg → 04_Exports/appcast/Conjoyn-<short>.dmg (distinct URL per release).
#   3. generate_appcast --account conjoyn --download-url-prefix <feed host>/ over the staging folder.
#   4. Verify: xmllint well-formed; sparkle:version == build; enclosure length == stat -f%z of the DMG;
#      non-empty sparkle:edSignature; report shortVersionString + minimumSystemVersion.
#
# Why --account conjoyn: the private key lives in the login keychain under the `conjoyn` account
# (Wave 0). Omit it and generate_appcast looks up a nonexistent default key. (Penumbra uses `penumbra`.)
#
# Enclosure is DMG (not zip): one notarized DMG serves as both the website download and the Sparkle
# enclosure. NEVER hand-edit `length` or `edSignature` — generate_appcast computes both from the bytes,
# and any later byte change (re-zip, CDN gzip) invalidates the signature.
set -euo pipefail

# --- config ----------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"          # …/01_Project
ACCOUNT="${SPARKLE_ACCOUNT:-conjoyn}"                  # EdDSA keychain account (Wave 0)
FEED_HOST="${FEED_HOST:-https://conjoyn.lucesumbrarum.com}"   # no trailing slash; we add it below

# The app make-dmg.sh consumed — authoritative for the version that's inside the DMG.
EXPORT_APP="${PROJECT_DIR}/build/notarize/export/Conjoyn.app"
OUT_DIR="${PROJECT_DIR}/../04_Exports"
DMG="${OUT_DIR}/Conjoyn.dmg"
APPCAST_DIR="${OUT_DIR}/appcast"                       # staging + appcast.xml (gitignored)

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
die()  { echo "error: $*" >&2; exit 1; }

# --- 0. preflight ----------------------------------------------------------
[ -f "$DMG" ] || die "no DMG at $DMG — run make-dmg.sh first."
[ -d "$EXPORT_APP" ] || die "no exported app at $EXPORT_APP — run make-dmg.sh (it builds + stamps the version)."
command -v xmllint >/dev/null 2>&1 || die "xmllint not found (expected on macOS)."

# Resolve generate_appcast — prefer Conjoyn's own DerivedData, then any sibling (the binary is
# identical across projects; --account is what binds it to Conjoyn's key). Path is volatile.
GEN="$(find ~/Library/Developer/Xcode/DerivedData/Conjoyn-* -path '*artifacts*[Ss]parkle*bin/generate_appcast' 2>/dev/null | head -1)"
[ -n "$GEN" ] || GEN="$(find ~/Library/Developer/Xcode/DerivedData -path '*artifacts*[Ss]parkle*bin/generate_appcast' 2>/dev/null | head -1)"
[ -n "$GEN" ] && [ -x "$GEN" ] || die "generate_appcast not found in DerivedData — open the project so SPM resolves Sparkle."

# --- 1. read the shipped version -------------------------------------------
PLIST="${EXPORT_APP}/Contents/Info.plist"
SHORT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"   # 1.0
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"              # 100 == sparkle:version
[ -n "$SHORT" ] && [ -n "$BUILD" ] || die "could not read version from $PLIST"
bold "==> Appcast for Conjoyn ${SHORT} (build ${BUILD}) · account=${ACCOUNT} · host=${FEED_HOST}"

# --- 2. stage the DMG under a version-stamped name -------------------------
# A distinct enclosure URL per release (Conjoyn-1.0.dmg) keeps old versions resolvable and avoids
# a cache collision when 1.0.1 ships. generate_appcast scans this folder.
STAGED_DMG="${APPCAST_DIR}/Conjoyn-${SHORT}.dmg"
mkdir -p "$APPCAST_DIR"
/usr/bin/ditto "$DMG" "$STAGED_DMG"
DMG_LEN="$(stat -f%z "$STAGED_DMG")"
echo "  staged $(basename "$STAGED_DMG") (${DMG_LEN} bytes)"

# --- 3. generate (auto length + EdDSA sign) --------------------------------
bold "==> Running generate_appcast (auto length + EdDSA sign)…"
"$GEN" --account "$ACCOUNT" --download-url-prefix "${FEED_HOST}/" "$APPCAST_DIR"
APPCAST="${APPCAST_DIR}/appcast.xml"
[ -f "$APPCAST" ] || die "generate_appcast did not write $APPCAST"

# --- 4. verify the load-bearing fields -------------------------------------
bold "==> Verifying appcast…"
xmllint --noout "$APPCAST" || die "appcast.xml is not well-formed"
echo "  ✓ well-formed XML"

# sparkle:version (== CFBundleVersion); tolerate element or attribute form.
grep -Eq "(<sparkle:version>${BUILD}</sparkle:version>|sparkle:version=\"${BUILD}\")" "$APPCAST" \
    || die "sparkle:version != ${BUILD} (must equal CFBundleVersion, monotonic)"
echo "  ✓ sparkle:version = ${BUILD}"

# enclosure length must be the EXACT byte count of the staged DMG, or EdDSA verification fails.
grep -q "length=\"${DMG_LEN}\"" "$APPCAST" || die "enclosure length != ${DMG_LEN} (signature would fail)"
echo "  ✓ enclosure length = ${DMG_LEN}"

# non-empty EdDSA signature
grep -Eq 'sparkle:edSignature="[A-Za-z0-9+/=]{40,}"' "$APPCAST" || die "missing/empty sparkle:edSignature"
echo "  ✓ sparkle:edSignature present"

# enclosure URL points at the version-stamped DMG on the feed host
grep -q "url=\"${FEED_HOST}/Conjoyn-${SHORT}.dmg\"" "$APPCAST" \
    || die "enclosure url is not ${FEED_HOST}/Conjoyn-${SHORT}.dmg"
echo "  ✓ enclosure url = ${FEED_HOST}/Conjoyn-${SHORT}.dmg"

# soft (report-only) — shortVersionString + minimumSystemVersion
SVS="$(grep -oE '<sparkle:shortVersionString>[^<]*</sparkle:shortVersionString>|sparkle:shortVersionString="[^"]*"' "$APPCAST" | head -1 || true)"
MSV="$(grep -oE '<sparkle:minimumSystemVersion>[^<]*</sparkle:minimumSystemVersion>' "$APPCAST" | head -1 || true)"
echo "  · ${SVS:-shortVersionString: (none — expected ${SHORT})}"
echo "  · ${MSV:-minimumSystemVersion: (none — expected 14.0)}"

bold "==> Done. Signed appcast: $APPCAST"
echo "Enclosure: $STAGED_DMG  →  ${FEED_HOST}/Conjoyn-${SHORT}.dmg"
echo "Deploy appcast.xml + Conjoyn-${SHORT}.dmg together (Wave 4). Add release notes via a"
echo "matching Conjoyn-${SHORT}.html in $APPCAST_DIR and re-run to embed a <description>."
