#!/bin/sh
# Build the 3D world: bundle main.js, then inline bundle.js into page.html at /*BUNDLE*/ -> index.html
set -eu
cd "$(dirname "$0")"

# --target=safari15: iPod runs iOS 15.8 (Safari 15.6). Without it esbuild 0.28 emits Uint8Array.fromBase64 (Safari 18.2+) for the .glb.
npx esbuild main.js --bundle --minify --format=iife --loader:.glb=binary --target=safari15 --outfile=bundle.js

node -e '
const fs = require("fs");
const page = fs.readFileSync("page.html", "utf8");
const js = fs.readFileSync("bundle.js", "utf8");
const marker = "/*BUNDLE*/";
const n = page.split(marker).length - 1;
if (n !== 1) { console.error("page.html must contain " + marker + " exactly once, found " + n); process.exit(1); }
if (/<\/script/i.test(js)) { console.error("bundle.js contains </script, which would break inlining"); process.exit(1); }
fs.writeFileSync("index.html", page.split(marker).join(js)); // split/join: no $-pattern surprises
console.log("index.html: " + fs.statSync("index.html").size + " bytes");
'
