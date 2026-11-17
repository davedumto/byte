#!/bin/sh
# Sets up `git shipit` on this Mac (step 5, decision 4A). Run it yourself: it changes things outside
# this project folder, and it says exactly what before doing anything.
#   1. copies the events token from the iPod (over your SSH key) to ~/.config/byte/events.token, mode 600
#   2. sets the global git alias:  shipit = !<this folder>/git-shipit
#   3. adds a global post-commit hook (git config hook.byte.*) so Byte turns Focused when you commit.
#      It runs alongside every repo's own hooks; off for one repo: git config hook.byte.enabled false
#   4. checks that Byte answers
# Safe to run again (e.g. after the token changes). Undo: git config --global --unset alias.shipit;
# git config --global --remove-section hook.byte; rm -r ~/.config/byte
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
CONF="${BYTE_CONFIG_DIR:-$HOME/.config/byte}"
IPOD_HOST="${BYTE_IPOD_HOST:-192.168.0.161}"
KEY="${BYTE_IPOD_KEY:-$HOME/.ssh/ipod_ed25519}"
REMOTE_TOKEN=/var/jb/var/mobile/byte/events.token
ALIAS_VALUE="!\"$HERE/git-shipit\""

current=$(git config --global --get alias.shipit 2>/dev/null || true)
HOOK_VALUE="\"$HERE/git-commit-hook\""
current_hook=$(git config --global --get hook.byte.command 2>/dev/null || true)

echo "This will:"
echo "  1. copy $REMOTE_TOKEN from mobile@$IPOD_HOST to $CONF/events.token (mode 600)"
if [ -z "$current" ]; then
  echo "  2. add the global git alias: shipit = $ALIAS_VALUE"
elif [ "$current" = "$ALIAS_VALUE" ]; then
  echo "  2. keep the global git alias shipit (already set up)"
else
  echo "  2. REPLACE your existing global git alias:"
  echo "       shipit = $current"
  echo "     with: shipit = $ALIAS_VALUE"
fi
if [ "$current_hook" = "$HOOK_VALUE" ]; then
  echo "  3. keep the global post-commit hook hook.byte (already set up)"
else
  echo "  3. add a global post-commit hook: hook.byte.event = post-commit, hook.byte.command = $HOOK_VALUE"
  echo "     (runs alongside each repo's own hooks; turn off per repo with: git config hook.byte.enabled false)"
fi
echo "  4. check that Byte answers (the Byte app must be open on the iPod)"
printf "Continue? [y/N] "
read -r answer
case "$answer" in y|Y|yes|YES) ;; *) echo "Nothing changed."; exit 1 ;; esac

# 1. Token
[ -r "$KEY" ] || { echo "SSH key $KEY not found (set BYTE_IPOD_KEY)." >&2; exit 1; }
token=$(ssh -i "$KEY" -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=8 "mobile@$IPOD_HOST" "cat $REMOTE_TOKEN" | tr -d ' \r\n') || {
  echo "Couldn't read the token from the iPod. Is it awake on Wi-Fi, with brain 0.1.6 installed?" >&2; exit 1; }
printf '%s' "$token" | LC_ALL=C grep -Eqx '[0-9a-f]{64}' || { echo "The iPod's events token is malformed." >&2; exit 1; }
(umask 077
 mkdir -p "$CONF"
 chmod 700 "$CONF"
 tmp="$CONF/events.token.new"
 printf '%s\n' "$token" > "$tmp"
 chmod 600 "$tmp"
 mv -f "$tmp" "$CONF/events.token")
echo "Token saved to $CONF/events.token"

# 2. Alias
git config --global alias.shipit "$ALIAS_VALUE"
echo "git shipit is ready."

# 3. Commit hook (config-based hooks: this Mac's git 2.54 has them; a git without them ignores these keys)
git config --global hook.byte.event post-commit
git config --global hook.byte.command "$HOOK_VALUE"
echo "Commit hook ready: Byte turns Focused when you commit."

# 4. Check
if "$HERE/byte-event" health; then
  echo "All set. Use 'git shipit' instead of 'git push' and Byte celebrates."
else
  echo "Set up, but Byte didn't answer right now. Open Byte on the iPod and try: $HERE/byte-event health"
fi
