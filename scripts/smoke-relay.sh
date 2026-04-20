#!/usr/bin/env bash
# End-to-end smoke test for the smoovmux-relay executable.
#
# Spawns a python AF_UNIX echo server, runs the relay against it, feeds
# bytes via stdin, and verifies the round trip lands on stdout. Sits in
# scripts/ instead of Tests/PaneRelayTests/ because XCTest/swift-testing
# parallelism makes Foundation.Process+Pipe wedge in this scenario; a
# subprocess-based shell harness sidesteps the issue and still exercises the
# real binary on the wire.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RELAY="${SMOOVMUX_RELAY_PATH:-$REPO_ROOT/.build/arm64-apple-macosx/debug/smoovmux-relay}"

if [ ! -x "$RELAY" ]; then
  echo "smoke-relay: $RELAY not found or not executable" >&2
  echo "smoke-relay: run \`swift build\` first or set SMOOVMUX_RELAY_PATH" >&2
  exit 2
fi

SOCK="/tmp/smoovmux-relay-smoke-$$.sock"
SERVER_LOG="$(mktemp)"
RELAY_LOG="$(mktemp)"
RELAY_OUT="$(mktemp)"
trap 'rm -f "$SOCK" "$SERVER_LOG" "$RELAY_LOG" "$RELAY_OUT"' EXIT

python3 -c "
import socket, sys, time
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind('$SOCK')
s.listen(1)
conn, _ = s.accept()
deadline = time.time() + 2
conn.settimeout(0.1)
total = b''
while time.time() < deadline:
    try:
        chunk = conn.recv(4096)
        if not chunk: break
        total += chunk
        conn.sendall(b'echo:' + chunk)
    except socket.timeout:
        pass
sys.stderr.write('server-saw=' + repr(total) + '\n')
conn.close(); s.close()
" 2>"$SERVER_LOG" &
SERVER_PID=$!
sleep 0.3

printf 'hello\n' | SMOOVMUX_PANE_SOCKET="$SOCK" "$RELAY" >"$RELAY_OUT" 2>"$RELAY_LOG"
RELAY_EXIT=$?

wait "$SERVER_PID" 2>/dev/null || true

if [ "$RELAY_EXIT" -ne 0 ]; then
  echo "smoke-relay: relay exited $RELAY_EXIT" >&2
  cat "$RELAY_LOG" >&2
  exit 1
fi

EXPECTED='echo:hello'
GOT="$(cat "$RELAY_OUT" | tr -d '\n')"
if [ "$GOT" != "$EXPECTED" ]; then
  echo "smoke-relay: round-trip mismatch" >&2
  echo "  expected: $EXPECTED" >&2
  echo "  got:      $GOT" >&2
  echo "server log:" >&2
  cat "$SERVER_LOG" >&2
  exit 1
fi

echo "smoke-relay: ok ($EXPECTED)"
