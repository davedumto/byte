#!/bin/sh
# Unit-test the shell's Foundation-only logic on the Mac (no device needed).
# LlamaBrain's HTTP tests run against Tests/fake_llama_server.py on a local port; EventServer's on port 17420.
set -eu
cd "$(dirname "$0")"
OUT="${TMPDIR:-/tmp}/byte-app-tests"
xcrun --sdk macosx swiftc -swift-version 5 -o "$OUT" \
  Sources/Bridge.swift Sources/Commands.swift Sources/Turns.swift Sources/Tokens.swift Sources/LlamaBrain.swift \
  Sources/Events.swift Sources/EventServer.swift \
  Tests/LlamaBrainTests.swift Tests/CommandsTests.swift Tests/EventsTests.swift Tests/main.swift

PORT=18080
python3 -I Tests/fake_llama_server.py $PORT &
SERVER=$!
trap 'kill $SERVER 2>/dev/null || true' EXIT
i=0; until nc -z 127.0.0.1 $PORT 2>/dev/null; do i=$((i+1)); [ $i -lt 50 ] || { echo "fake server didn't start" >&2; exit 1; }; sleep 0.1; done

FAKE_LLAMA_PORT=$PORT "$OUT"
