#!/bin/sh
# Copy the newest Byte .deb to the iPod's staging folder and print the root install command.
# The root step is run by hand (it needs mobile's sudo password), decision 2026-11-16, option A.
set -eu
cd "$(dirname "$0")"

# Usage: ./deploy.sh          over Wi-Fi
#        ./deploy.sh --usb    over the Lightning cable (via iproxy), e.g. when Wi-Fi is asleep
IPOD_HOST="${BYTE_IPOD_HOST:-192.168.0.161}"
KEY="${BYTE_IPOD_KEY:-$HOME/.ssh/ipod_ed25519}"
STAGE=/var/mobile/byte-deploy
USB_PORT=2222
SSH_OPTS="-i $KEY -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8"

if [ "${1:-}" = "--usb" ]; then
  command -v iproxy >/dev/null || { echo "iproxy not found (brew install libimobiledevice)" >&2; exit 1; }
  iproxy $USB_PORT 22 >/dev/null 2>&1 &
  IPROXY_PID=$!
  trap 'kill $IPROXY_PID 2>/dev/null' EXIT
  sleep 1
  IPOD=mobile@127.0.0.1
  # same host key as on Wi-Fi, so check it against the saved one
  SSH_OPTS="$SSH_OPTS -o HostKeyAlias=$IPOD_HOST"
  SSH_PORT="-p $USB_PORT"; SCP_PORT="-P $USB_PORT"
  ROOT_PRE="  (first, in another Terminal tab, leave this running: iproxy $USB_PORT 22)"
  ROOT_HINT="ssh -t -p $USB_PORT -o HostKeyAlias=$IPOD_HOST -i $KEY $IPOD"
else
  IPOD=mobile@$IPOD_HOST
  SSH_PORT=""; SCP_PORT=""
  ROOT_PRE=""
  ROOT_HINT="ssh -t -i $KEY $IPOD"
fi

DEB=$(ls -t packages/*.deb 2>/dev/null | head -1)
[ -n "$DEB" ] || { echo "no .deb in packages/; run: make package" >&2; exit 1; }
NAME=$(basename "$DEB")

ssh $SSH_OPTS $SSH_PORT "$IPOD" "mkdir -p $STAGE"
scp -q $SSH_OPTS $SCP_PORT "$DEB" "$IPOD:$STAGE/$NAME"
LOCAL_SUM=$(shasum -a 256 "$DEB" | awk '{print $1}')
REMOTE_SUM=$(ssh $SSH_OPTS $SSH_PORT "$IPOD" "shasum -a 256 $STAGE/$NAME 2>/dev/null || sha256sum $STAGE/$NAME" | awk '{print $1}')
[ "$LOCAL_SUM" = "$REMOTE_SUM" ] || { echo "checksum mismatch after copy: $LOCAL_SUM vs $REMOTE_SUM" >&2; exit 1; }

echo "copied $NAME ($(wc -c < "$DEB" | tr -d ' ') bytes, sha256 ok) to $IPOD:$STAGE"
echo
echo "Now run this in your own Terminal (asks for mobile's password):"
[ -n "$ROOT_PRE" ] && echo "$ROOT_PRE"
echo "  $ROOT_HINT 'sudo dpkg -i $STAGE/$NAME && sudo uicache -p /var/jb/Applications/Byte.app'"
