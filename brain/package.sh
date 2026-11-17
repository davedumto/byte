#!/bin/sh
# Package brain/out/llama-server + the launch daemon into a rootless .deb (brain/packages/).
set -eu
cd "$(dirname "$0")"
[ -x out/llama-server ] && [ -x out/byte-brain-launcher ] || { echo "run ./build.sh first" >&2; exit 1; }
plutil -lint package/var/jb/Library/LaunchDaemons/app.byte.brain.plist >/dev/null

STAGE=.stage
rm -rf "$STAGE" && cp -R package "$STAGE"
mkdir -p "$STAGE/var/jb/usr/libexec/byte"
cp out/llama-server "$STAGE/var/jb/usr/libexec/byte/llama-server"
cp out/byte-brain-launcher "$STAGE/var/jb/usr/libexec/byte/byte-brain-launcher"
chmod 755 "$STAGE/var/jb/usr/libexec/byte/llama-server" "$STAGE/var/jb/usr/libexec/byte/byte-brain-launcher" "$STAGE/DEBIAN/postinst" "$STAGE/DEBIAN/prerm"
find "$STAGE" -name .DS_Store -delete

VERSION=$(awk '/^Version:/{print $2}' package/DEBIAN/control)
mkdir -p packages
"$THEOS/bin/dm.pl" -Zgzip -b "$STAGE" "packages/app.byte.brain_${VERSION}_iphoneos-arm64.deb"
rm -rf "$STAGE"
