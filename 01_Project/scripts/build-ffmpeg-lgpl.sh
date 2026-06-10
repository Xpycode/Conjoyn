#!/bin/bash
# build-ffmpeg-lgpl.sh — build the RELEASE bundled FFmpeg/ffprobe helpers (Wave 6, task 6.1).
#
# Replaces the interim GPL prebuilt (fetch-ffmpeg.sh, OSXExperts) with a reproducible static
# arm64 macOS build configured LGPL — i.e. WITHOUT --enable-gpl / --enable-nonfree, and with no
# external GPL libraries (x264/x265/…). A copy-only joiner + metadata reader needs none of them.
#
# Per docs/decisions.md (2026-06-07, "Bundle a static arm64 LGPL FFmpeg + ffprobe"):
#   --enable-static --disable-shared, LGPL default license, only built-in codecs/(de)muxers.
# Static = single Mach-O each, no install_name_tool dylib dance.
#
# Output binaries are gitignored (large) — release builds re-run this. Re-runnable / idempotent.
# Build deps: Xcode command-line tools (clang/make). No nasm/yasm needed on arm64 (NEON .S
# assembled by clang). No external libraries are fetched or linked.
set -euo pipefail

FFMPEG_VERSION="8.1"   # matches the interim binary we are replacing
FFMPEG_URL="https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$SCRIPT_DIR/../Conjoyn/Resources/Helpers"
mkdir -p "$DEST"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "↓ $FFMPEG_URL"
curl -fL --max-time 600 -o "$TMP/ffmpeg.tar.xz" "$FFMPEG_URL"
echo "→ extracting"
tar -xJf "$TMP/ffmpeg.tar.xz" -C "$TMP"
SRC="$TMP/ffmpeg-${FFMPEG_VERSION}"

echo "→ configure (LGPL, static, no external libs)"
cd "$SRC"
./configure \
    --cc=/usr/bin/clang \
    --arch=arm64 \
    --enable-static \
    --disable-shared \
    --enable-runtime-cpudetect \
    --disable-doc \
    --disable-debug \
    --disable-ffplay \
    --disable-network \
    --disable-autodetect \
    --pkg-config-flags=--static
    # NB: no --enable-gpl, no --enable-nonfree → license stays LGPL v2.1+.
    # --disable-autodetect keeps the build hermetic: it will NOT pick up any
    # Homebrew GPL libs (x264/x265) that happen to be installed.

echo "→ build (this takes a few minutes)"
make -j"$(sysctl -n hw.ncpu)"

echo "→ install binaries"
/usr/bin/ditto "$SRC/ffmpeg"  "$DEST/ffmpeg"
/usr/bin/ditto "$SRC/ffprobe" "$DEST/ffprobe"
chmod +x "$DEST/ffmpeg" "$DEST/ffprobe"

echo "=== verify ==="
for t in ffmpeg ffprobe; do
    file "$DEST/$t" | grep -q "arm64" && echo "✓ $t is arm64 Mach-O" || { echo "✗ $t not arm64"; exit 1; }
    "$DEST/$t" -version >/dev/null 2>&1 && echo "✓ $t -version runs" || { echo "✗ $t -version failed"; exit 1; }
    # Hard gate: refuse a GPL/nonfree build.
    if "$DEST/$t" -version | grep -q -- "--enable-gpl"; then echo "✗ $t is GPL (--enable-gpl)"; exit 1; fi
    if "$DEST/$t" -version | grep -q -- "--enable-nonfree"; then echo "✗ $t is nonfree"; exit 1; fi
done
echo "✓ no --enable-gpl / --enable-nonfree in either binary"
echo "--- ffmpeg -L (license) ---"
"$DEST/ffmpeg" -L 2>/dev/null | head -3
echo "--- ffmpeg -version ---"
"$DEST/ffmpeg" -version | head -1

# LGPL compliance notice — shipped alongside the binaries (replaces the interim GPL notice).
cat > "$DEST/ACKNOWLEDGEMENTS-FFmpeg.txt" <<NOTICE
This application bundles FFmpeg (ffmpeg, ffprobe).

LICENSE
-------
The bundled FFmpeg binaries are static arm64 builds compiled from unmodified FFmpeg
${FFMPEG_VERSION} source via 01_Project/scripts/build-ffmpeg-lgpl.sh. They are configured WITHOUT
--enable-gpl and WITHOUT --enable-nonfree, and link no external GPL libraries. As such they are
licensed under the GNU Lesser General Public License (LGPL) version 2.1 or later.

FFmpeg is free software. The corresponding source for the bundled version is available at:
  Source:  https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz
  Project: https://ffmpeg.org/  —  https://git.ffmpeg.org/ffmpeg.git
A copy of the corresponding source is also available on request.

Build configuration: --enable-static --disable-shared --disable-network --disable-autodetect
(LGPL default license; built-in codecs, demuxers and muxers only).
NOTICE
echo "✓ wrote ACKNOWLEDGEMENTS-FFmpeg.txt (LGPL)"
echo "Done → $DEST"
