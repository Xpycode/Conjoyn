#!/bin/bash
# sign-bundled-binaries.sh — copy bundled FFmpeg helpers into the app and code-sign them.
#
# Run as a post-build (last) build phase so it executes BEFORE Xcode's final code-sign of the
# .app wrapper (inside-out signing). Trimmed for DJIjoiner: ffmpeg + ffprobe only (no BMX).
#
# Reads standard Xcode build-phase env vars: SRCROOT, BUILT_PRODUCTS_DIR, CONTENTS_FOLDER_PATH,
# CONFIGURATION, EXPANDED_CODE_SIGN_IDENTITY / CODE_SIGN_IDENTITY.
set -euo pipefail

HELPERS=(ffmpeg ffprobe)
SRC_DIR="${SRCROOT}/DJIjoiner/Resources/Helpers"
DEST_DIR="${BUILT_PRODUCTS_DIR}/${CONTENTS_FOLDER_PATH}/Resources/Helpers"

IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:--}}"

# Release builds get a secure timestamp (needed for notarization); dev builds skip it (faster, offline).
if [ "${CONFIGURATION:-Debug}" = "Release" ]; then
    TS_FLAG="--timestamp"
else
    TS_FLAG="--timestamp=none"
fi

if [ ! -d "$SRC_DIR" ]; then
    echo "warning: Helpers source dir not found ($SRC_DIR) — skipping bundle/sign (FFmpeg not acquired yet)"
    exit 0
fi

mkdir -p "$DEST_DIR"

for tool in "${HELPERS[@]}"; do
    src="$SRC_DIR/$tool"
    if [ ! -f "$src" ]; then
        echo "warning: bundled helper '$tool' missing at $src — skipping"
        continue
    fi
    echo "Bundling helper: $tool"
    /usr/bin/ditto "$src" "$DEST_DIR/$tool"
    chmod +x "$DEST_DIR/$tool"
    echo "Signing helper: $tool (identity: $IDENTITY)"
    /usr/bin/codesign --force --options runtime $TS_FLAG --sign "$IDENTITY" "$DEST_DIR/$tool"
    /usr/bin/codesign -dv "$DEST_DIR/$tool" 2>&1 | grep -E "Identifier|Signature|Runtime" || true
done

echo "Bundled helpers signed into: $DEST_DIR"
