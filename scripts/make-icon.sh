#!/bin/bash
# Regenerate Resources/AppIcon.icns from the canonical vector (icon.svg).
#
# Run this whenever icon.svg changes, then commit the updated AppIcon.icns.
# The bundle build (scripts/bundle.sh) copies the committed .icns as-is, so the
# release/CI path never needs rsvg-convert — only this dev-time regen does.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SRC="${1:-$PROJECT_DIR/icon.svg}"
OUT="$PROJECT_DIR/Resources/AppIcon.icns"

if ! command -v rsvg-convert >/dev/null 2>&1; then
    echo "error: rsvg-convert not found — install with 'brew install librsvg'" >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

render() { rsvg-convert -w "$2" -h "$2" "$SRC" -o "$ICONSET/$1"; }
render icon_16x16.png        16
render icon_16x16@2x.png      32
render icon_32x32.png         32
render icon_32x32@2x.png      64
render icon_128x128.png      128
render icon_128x128@2x.png   256
render icon_256x256.png      256
render icon_256x256@2x.png   512
render icon_512x512.png      512
render icon_512x512@2x.png  1024

iconutil -c icns "$ICONSET" -o "$OUT"
echo "wrote $OUT ($(du -h "$OUT" | cut -f1))"
