#!/bin/sh
# Tests for byte-event and git-shipit against fake_byte.py (no iPod needed). Run: tools/mac/test.sh
set -u
cd "$(dirname "$0")"
HERE=$(pwd)
T=$(mktemp -d "${TMPDIR:-/tmp}/byte-mac-tests.XXXXXX")
PORT=17421
TOKEN=$(printf 'cd%.0s' $(seq 32))
LOG="$T/requests.log"
pass=0; fail=0
check() { if eval "$1"; then pass=$((pass + 1)); else fail=$((fail + 1)); echo "FAIL $2"; fi; }

python3 -I fake_byte.py $PORT "$TOKEN" "$LOG" & SERVER=$!
trap 'kill $SERVER 2>/dev/null; rm -rf "$T"' EXIT
i=0; until nc -z 127.0.0.1 $PORT 2>/dev/null; do i=$((i+1)); [ $i -lt 50 ] || { echo "fake server didn't start"; exit 1; }; sleep 0.1; done

export BYTE_CONFIG_DIR="$T/conf" BYTE_HOST=127.0.0.1 BYTE_PORT=$PORT
mkdir -p "$BYTE_CONFIG_DIR"; printf '%s\n' "$TOKEN" > "$BYTE_CONFIG_DIR/events.token"
last() { tail -n 1 "$LOG"; }
field() { last | python3 -I -c "import json,sys; r=json.loads(sys.stdin.read()); v=r['$1']; print(json.loads(v)['$2'] if '$2' else v)"; }

# --- byte-event ---
./byte-event push 3 vellar-sdk main 2>/dev/null; check '[ $? -eq 0 ]' "push exits 0"
check '[ "$(field path "")" = /event ]' "push goes to /event"
check '[ "$(field auth "")" = True ]' "push carries the token"
check '[ "$(field body type)" = push ] && [ "$(field body commits)" = 3 ]' "push body type and commits"
check '[ "$(field body repo)" = vellar-sdk ] && [ "$(field body branch)" = main ]' "push body repo and branch"
check 'field body ts | grep -Eqx "[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"' "push body timestamp"

./byte-event push 2 'we"ird {repo} $(x)' 'feat/ünï code' 2>/dev/null
check '[ "$(field body repo)" = "we-ird--repo----x-" ]' "repo name made JSON-safe"
check 'field body branch | grep -Eqx "feat/[-a-z]+"' "branch name made JSON-safe, slash kept"
./byte-event push "$(printf 'x%.0s' $(seq 300))" "$(printf 'r%.0s' $(seq 300))" 2>/dev/null
check '[ "$(field body commits)" = 0 ]' "non-numeric commits sent as 0"
check '[ "$(field body repo | wc -c)" -le 101 ]' "repo name capped at 100 chars"
./byte-event push 2>/dev/null
check '[ "$(field body commits)" = 0 ] && [ "$(field body repo)" = "" ]' "push with no details"

out=$(./byte-event commit 2>&1); code=$?
check '[ $code -eq 0 ] && [ -z "$out" ]' "commit exits 0 and prints nothing"
check '[ "$(field body type)" = commit ] && field body ts | grep -Eqx "[0-9T:Z-]{20}"' "commit body"
./byte-event commit extra 2>/dev/null; check '[ $? -eq 2 ]' "commit takes no arguments"
./byte-event health 2>/dev/null; check '[ $? -eq 0 ] && [ "$(field method "")" = GET ] && [ "$(field path "")" = /health ]' "health"

out=$(BYTE_TOKEN=$(printf 'ab%.0s' $(seq 32)) ./byte-event push 1 r b 2>&1); code=$?
check '[ $code -eq 1 ] && echo "$out" | grep -q "refused the token"' "wrong token: exit 1 with a hint"
out=$(BYTE_TOKEN=nothex ./byte-event push 2>&1); code=$?
check '[ $code -eq 2 ] && echo "$out" | grep -q malformed' "malformed token: exit 2"
out=$(BYTE_CONFIG_DIR="$T/none" ./byte-event push 2>&1); code=$?
check '[ $code -eq 2 ] && echo "$out" | grep -q install.sh' "no token file: exit 2, points at install.sh"
n=$(wc -l < "$LOG")
./byte-event 2>/dev/null; check '[ $? -eq 2 ]' "no arguments: usage"
./byte-event dance 2>/dev/null; check '[ $? -eq 2 ]' "unknown command: usage"
./byte-event health extra 2>/dev/null; check '[ $? -eq 2 ]' "extra arguments: usage"
check '[ "$(wc -l < "$LOG")" -eq "$n" ]' "usage errors send nothing"
mkdir -p "$T/bin"; REAL_CURL=$(command -v curl)
printf '#!/bin/sh\necho "$*" >> "%s"\nexec "%s" "$@"\n' "$T/curl-args" "$REAL_CURL" > "$T/bin/curl"; chmod +x "$T/bin/curl"
PATH="$T/bin:$PATH" ./byte-event push 1 r b 2>/dev/null
check '[ -s "$T/curl-args" ] && ! grep -q "$TOKEN" "$T/curl-args"' "token never on curl's command line (not visible in ps)"
check '[ "$(field auth "")" = True ]' "...yet the request still carried it"

start=$(date +%s)
out=$(BYTE_PORT=17499 ./byte-event push 1 r b 2>&1); code=$?
check '[ $code -eq 1 ] && echo "$out" | grep -q "is the app open"' "nothing listening: exit 1 with a hint"
check '[ $(( $(date +%s) - start )) -le 4 ]' "nothing listening: gives up within 4 s"

# --- Bonjour discovery, then the cached address when Bonjour has nothing ---
# A throwaway service whose host record points at 127.0.0.1, so nothing on the LAN can reach the fake.
NAME="Byte-test-$$"
dns-sd -P "$NAME" _byte._tcp local. $PORT "byte-test-$$.local." 127.0.0.1 >/dev/null 2>&1 & ADV=$!
sleep 1
rm -f "$BYTE_CONFIG_DIR/host"
out=$(env -u BYTE_HOST BYTE_SERVICE_NAME="$NAME" ./byte-event health 2>&1); code=$?
check '[ $code -eq 0 ] && echo "$out" | grep -q "byte-test-$$.local"' "found by Bonjour"
check '[ "$(cat "$BYTE_CONFIG_DIR/host")" = "byte-test-$$.local" ]' "Bonjour address remembered"
kill $ADV 2>/dev/null; wait $ADV 2>/dev/null
printf '127.0.0.1\n' > "$BYTE_CONFIG_DIR/host"
start=$(date +%s)
out=$(env -u BYTE_HOST BYTE_SERVICE_NAME="$NAME-gone" ./byte-event health 2>&1); code=$?
check '[ $code -eq 0 ] && echo "$out" | grep -q "127.0.0.1"' "no Bonjour answer: falls back to the remembered address"
check '[ $(( $(date +%s) - start )) -le 4 ]' "fallback within 4 s"
rm -f "$BYTE_CONFIG_DIR/host"
out=$(env -u BYTE_HOST BYTE_SERVICE_NAME="$NAME-gone" ./byte-event health 2>&1); code=$?
check '[ $code -eq 1 ] && echo "$out" | grep -q "couldn.t find Byte"' "no Bonjour, nothing remembered: exit 1 with a hint"

# --- git-shipit (with a stub notifier that records its arguments) ---
STUB="$T/stub"; CALLS="$T/calls"
printf '#!/bin/sh\necho "$*" >> "%s"\n' "$CALLS" > "$STUB"; chmod +x "$STUB"
export BYTE_EVENT="$STUB" GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
git config --global user.name t; git config --global user.email t@example.invalid; git config --global init.defaultBranch main
git init -q --bare "$T/remote.git"
git init -q "$T/work/my-repo"; cd "$T/work/my-repo"
git remote add origin "$T/remote.git"
commit() { echo "$1" >> f; git add f; git commit -qm "$1"; }
commit one; commit two
"$HERE/git-shipit" -q -u origin main; code=$?
check '[ $code -eq 0 ] && [ "$(cat "$CALLS")" = "push 2 my-repo main" ]' "first push: 2 commits reported"
: > "$CALLS"
"$HERE/git-shipit" -q; check '[ $? -eq 0 ] && [ ! -s "$CALLS" ]' "nothing new: no celebration"
commit three; "$HERE/git-shipit" -q
check '[ "$(cat "$CALLS")" = "push 1 my-repo main" ]' "next push: 1 commit"
: > "$CALLS"
git checkout -qb feature; commit four; commit five; git checkout -q main
"$HERE/git-shipit" -q origin feature
check '[ "$(cat "$CALLS")" = "push 2 my-repo main" ]' "pushing another branch counts its commits"
: > "$CALLS"
commit six; "$HERE/git-shipit" -q origin main:main --dry-run
check '[ ! -s "$CALLS" ]' "dry run: no celebration"
"$HERE/git-shipit" -q nowhere main 2>/dev/null; code=$?
check '[ $code -ne 0 ] && [ ! -s "$CALLS" ]' "failed push: git's exit code, no celebration"
git tag v1; "$HERE/git-shipit" -q origin v1
check '[ ! -s "$CALLS" ]' "tag-only push: no celebration"
printf '#!/bin/sh\nexit 1\n' > "$STUB"
"$HERE/git-shipit" -q; check '[ $? -eq 0 ]' "unreachable Byte never fails the push"

# --- commit hook: config-based, runs alongside the repo's own hook, never slows or fails a commit ---
printf '#!/bin/sh\nsleep 3; echo commit >> "%s"\n' "$CALLS" > "$STUB"
printf '#!/bin/sh\necho own-hook-ran >> "%s"\n' "$T/own" > .git/hooks/post-commit; chmod +x .git/hooks/post-commit
git config --global hook.byte.event post-commit
git config --global hook.byte.command "\"$HERE/git-commit-hook\""
: > "$CALLS"
start=$(date +%s); out=$(git commit -q --allow-empty -m hooked 2>&1); code=$?
check '[ $code -eq 0 ] && [ -z "$out" ]' "commit with the hook: succeeds, prints nothing"
check '[ $(( $(date +%s) - start )) -le 1 ]' "commit doesn't wait for Byte (notifier runs in the background)"
check '[ "$(cat "$T/own")" = own-hook-ran ]' "the repo's own post-commit hook still runs"
i=0; while [ ! -s "$CALLS" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
check '[ "$(cat "$CALLS")" = commit ]' "the hook sent a commit event"
: > "$CALLS"; git config hook.byte.enabled false; git commit -q --allow-empty -m off; sleep 3.5
check '[ ! -s "$CALLS" ]' "hook.byte.enabled false turns it off for one repo"
git config --unset hook.byte.enabled
printf '#!/bin/sh\nexit 1\n' > "$STUB"
git commit -q --allow-empty -m failing-notifier; check '[ $? -eq 0 ]' "a failing notifier never fails the commit"
git config --global --remove-section hook.byte
cd "$HERE"

# --- install.sh: answering no changes nothing ---
echo n | ./install.sh >/dev/null 2>&1; code=$?
check '[ $code -ne 0 ] && [ -z "$(git config --global --get alias.shipit)" ]' "install: 'no' leaves git config alone"

echo "$( [ $fail -eq 0 ] && echo "OK: $pass mac checks passed" || echo "$fail of $((pass + fail)) mac checks FAILED")"
[ $fail -eq 0 ]
