#!/bin/sh
# Resize tools/icon-1024.png into every AppIcon file the app's Info.plist references (and the extras Theos ships).
set -eu
cd "$(dirname "$0")/.."
SRC=tools/icon-1024.png
DST=../app/Resources
[ -f "$SRC" ] || { echo "missing $SRC; run tools/render-icon.sh first" >&2; exit 1; }

for spec in 29 40 57 60 72 76; do
  for scale in 1 2 3; do
    case "$scale" in 1) suffix="" ;; *) suffix="@${scale}x" ;; esac
    px=$((spec * scale))
    sips -s format png -z "$px" "$px" "$SRC" --out "$DST/AppIcon${spec}x${spec}${suffix}.png" >/dev/null
  done
done
echo "wrote $(ls "$DST"/AppIcon*.png | wc -l | tr -d ' ') icon files to $DST"
