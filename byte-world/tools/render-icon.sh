#!/bin/sh
# Step 1: bundle the icon renderer and start the save server (it exits after one save).
# Step 2: open http://127.0.0.1:8001/icon.html in a browser.
# Step 3: ./tools/icon-sizes.sh turns icon-1024.png into the app's icon files.
set -eu
cd "$(dirname "$0")/.."
npx esbuild tools/icon.js --bundle --minify --format=iife --loader:.glb=binary --outfile=tools/icon-bundle.js
exec python3 -I tools/icon_server.py "$(pwd)/tools/icon-1024.png"
