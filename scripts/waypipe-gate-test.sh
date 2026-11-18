#!/usr/bin/env bash
# Self-check for waypipe-gate.sh: bash scripts/waypipe-gate-test.sh
set -euo pipefail
gate="$(dirname "$0")/waypipe-gate.sh"
bin=$(mktemp -d); trap 'rm -rf "$bin"' EXIT
printf '#!/bin/sh\necho "socat $*"\n' > "$bin/socat"; chmod +x "$bin/socat"   # stand-in socat
export PATH="$bin:$PATH"
fail=0
passes()  { [ "$(bash "$gate" "$1" 3 /s)" = "socat STDIO UNIX-CONNECT:/s" ] && echo "ok    passes  $1" || { echo "FAIL  blocked $1"; fail=1; }; }
refused() { bash "$gate" "$1" 3 /s >/dev/null 2>&1 && { echo "FAIL  let through $1"; fail=1; } || echo "ok    refused $1"; }
passes  "7-2:5003-3:1024"
refused "7-2:5003-4:1024"    # another VM
refused "7-2:5003-33:1024"   # a CID that only starts with the right digit
refused "waypipe"            # instance name not in the expected form
refused ""
exit $fail
