#!/bin/sh
# Mac unit tests for the brain launcher's token handling (the iOS-only memorystatus/setuid parts are tested on device).
set -eu
cd "$(dirname "$0")"
OUT="${TMPDIR:-/tmp}/byte-launcher-tests"
clang -Wall -Wextra -Werror -Wno-unused-function -o "$OUT" launcher/test_token.c
"$OUT"
