#!/bin/sh
# Run a command on the iPod as mobile: Wi-Fi if it answers, otherwise the Lightning cable (via iproxy).
# Key login only (BatchMode): never falls back to password prompts.
# Usage: ./ipod.sh 'command ...'
set -eu
IPOD_HOST="${BYTE_IPOD_HOST:-192.168.0.161}"
KEY="${BYTE_IPOD_KEY:-$HOME/.ssh/ipod_ed25519}"
USB_PORT=2222

ssh_ipod() { # extra ssh args..., then the remote command
  ssh -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=5 -o PasswordAuthentication=no "$@"
}

if ssh_ipod "mobile@$IPOD_HOST" true 2>/dev/null; then
  echo "(via Wi-Fi)" >&2
  exec ssh -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=5 -o PasswordAuthentication=no "mobile@$IPOD_HOST" "$1"
fi

command -v iproxy >/dev/null || { echo "Wi-Fi unreachable and iproxy not found" >&2; exit 1; }
iproxy $USB_PORT 22 >/dev/null 2>&1 &
IPROXY_PID=$!
trap 'kill $IPROXY_PID 2>/dev/null || true' EXIT
sleep 1
echo "(via USB)" >&2
ssh_ipod -p $USB_PORT -o HostKeyAlias="$IPOD_HOST" mobile@127.0.0.1 "$1"
