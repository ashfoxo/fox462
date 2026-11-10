#!/usr/bin/env bash
# Self-check for dvd-classify.sh: bash scripts/dvd-classify-test.sh
set -euo pipefail
c="$(dirname "$0")/dvd-classify.sh"
fail=0
check() {  # check <expected> <duration>...
  local want=$1 got i=0; shift
  got=$(for d in "$@"; do echo "TINFO:$i,9,0,\"$d\""; echo "TINFO:$i,2,0,\"x\""; i=$((i+1)); done | bash "$c")
  [ "$got" = "$want" ] && echo "ok    $want" || { echo "FAIL  want '$want', got '$got' for: $*"; fail=1; }
}
check "movie 0"     2:49:03                                  # Interstellar alone
check "movie 1"     0:12:00 2:01:30 0:25:00 0:41:00          # feature + uneven extras
check "tv 0 1 2 3"  0:44:10 0:43:05 0:45:30 0:42:50          # drama disc
check "tv 1 2 3 4"  1:28:00 0:22:00 0:21:30 0:22:10 0:21:50  # sitcom + play all
check "other"       1:55:00 0:20:00 0:21:00                  # feature + 2 similar extras
check "other"       0:55:00                                  # one special
echo -n "" | { got=$(bash "$c"); [ "$got" = none ] && echo "ok    none" || { echo "FAIL  none: $got"; fail=1; }; }
exit $fail
