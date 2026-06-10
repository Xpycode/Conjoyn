#!/bin/bash
# fetch-ffmpeg.sh — download the INTERIM bundled FFmpeg/ffprobe helpers (Wave 0, task 0.4).
#
# Source: osxexperts.net — prebuilt *static* arm64 macOS binaries (FFmpeg 8.1), as named in
# IMPLEMENTATION_PLAN.md task 0.4. These are GPL builds (interim). Per docs/decisions.md the
# release build must swap to an LGPL static build before distribution (Wave 6, task 6.1).
#
# Binaries are gitignored (large) — every clone re-runs this script. Re-runnable / idempotent.
set -euo pipefail

FFMPEG_URL="https://www.osxexperts.net/ffmpeg81arm.zip"
FFPROBE_URL="https://www.osxexperts.net/ffprobe81arm.zip"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$SCRIPT_DIR/../Conjoyn/Resources/Helpers"
mkdir -p "$DEST"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fetch() {  # url  outname
    local url="$1" out="$2"
    echo "↓ $url"
    curl -fL --max-time 180 -o "$TMP/$out.zip" "$url"
    /usr/bin/unzip -o -q "$TMP/$out.zip" -d "$TMP/$out"
    # the archive contains a single binary (named ffmpeg/ffprobe); find and move it
    local bin
    bin="$(/usr/bin/find "$TMP/$out" -type f -name "$out" | head -1)"
    [ -n "$bin" ] || { echo "error: '$out' not found in archive"; exit 1; }
    /usr/bin/ditto "$bin" "$DEST/$out"
    chmod +x "$DEST/$out"
}

fetch "$FFMPEG_URL" ffmpeg
fetch "$FFPROBE_URL" ffprobe

echo "=== verify ==="
for t in ffmpeg ffprobe; do
    file "$DEST/$t" | grep -q "arm64" && echo "✓ $t is arm64 Mach-O" || { echo "✗ $t not arm64"; exit 1; }
    "$DEST/$t" -version >/dev/null 2>&1 && echo "✓ $t -version runs" || { echo "✗ $t -version failed"; exit 1; }
done
"$DEST/ffmpeg" -version | head -1

# GPL compliance notice (interim) — shipped alongside the binaries.
cat > "$DEST/ACKNOWLEDGEMENTS-FFmpeg.txt" <<'NOTICE'
This application bundles FFmpeg (ffmpeg, ffprobe).

INTERIM BUILD NOTICE
--------------------
The currently bundled FFmpeg binaries are static arm64 builds obtained from
https://www.osxexperts.net (FFmpeg 8.1). These are GPL-licensed builds used during
development. They MUST be replaced with an LGPL static build before public distribution
(see IMPLEMENTATION_PLAN.md task 6.1 / docs/decisions.md).

FFmpeg is free software licensed under the GNU General Public License (GPL) v2 or later
(or the GNU Lesser General Public License, LGPL, depending on build configuration).
FFmpeg source: https://ffmpeg.org/  —  https://git.ffmpeg.org/ffmpeg.git
A copy of the corresponding source for the bundled version is available on request.
NOTICE
echo "✓ wrote ACKNOWLEDGEMENTS-FFmpeg.txt"
echo "Done → $DEST"
