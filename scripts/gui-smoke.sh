#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CRYSTAL_CACHE_DIR="${CRYSTAL_CACHE_DIR:-/tmp/hnreader-crystal-cache}"
export HN_SMOKE_OUTPUT="${HN_SMOKE_OUTPUT:-/tmp/hnreader-smoke}"
mkdir -p "$HN_SMOKE_OUTPUT" bin
port_file=$(mktemp /tmp/hnreader-port.XXXXXX)
python3 scripts/smoke_server.py "$port_file" &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true; rm -f "$port_file"' EXIT
for attempt in {1..50}; do
  if [[ -s "$port_file" ]]; then break; fi
  sleep 0.1
done
export HN_SMOKE_URL="http://127.0.0.1:$(cat "$port_file")"
crystal build scripts/gui_smoke.cr -o bin/gui-smoke --error-trace
./bin/gui-smoke
