#!/usr/bin/env bash
# Creates Spaces, files rooms into them, sets favourite/low-priority tags, mutes Communities except mentions.
# usage: MATRIX_TOKEN=... MATRIX_HS=... ./element-apply.sh ~/element-rooms.tsv [--dry-run]
# Safe to re-run: existing Spaces (matched by name) are reused.
set -euo pipefail
. "$(dirname "$0")/element-lib.sh"
file=${1:?tsv file}; dry=${2:-}
domain=${ME#*:}
declare -A space
for r in $(api GET /joined_rooms | jq -r '.joined_rooms[]'); do
  e=$(enc "$r")
  [ "$(api GET "/rooms/$e/state/m.room.create" | jq -r '.type // ""')" = m.space ] || continue
  space[$(api GET "/rooms/$e/state/m.room.name" | jq -r .name)]=$r
done
run() { if [ "$dry" = --dry-run ]; then echo "would: $*"; else "$@" >/dev/null; fi; }
while IFS=$'\t' read -r room name kind _ _ sp fav low _; do
  [[ $room == '#'* || -z $room || -z $sp ]] && continue
  case $sp in Family|Friends|Gay|Furry|Feed|"Small groups"|Communities|Misc) ;; *) echo "bad space '$sp' for $name" >&2; exit 1;; esac
  if [ -z "${space[$sp]:-}" ]; then
    echo "creating space $sp"
    if [ "$dry" = --dry-run ]; then space[$sp]='!dry:x'
    else space[$sp]=$(api POST /createRoom "$(jq -n --arg n "$sp" '{name:$n,preset:"private_chat",creation_content:{type:"m.space"}}')" | jq -r .room_id); fi
  fi
  echo "$sp <- $name"
  run api PUT "/rooms/$(enc "${space[$sp]}")/state/m.space.child/$(enc "$room")" "$(jq -n --arg d "$domain" '{via:[$d]}')"
  tags="/user/$(enc "$ME")/rooms/$(enc "$room")/tags"
  [ -n "$fav" ] && run api PUT "$tags/m.favourite" '{"order":0.5}'
  [ -n "$low" ] && run api PUT "$tags/m.lowpriority" '{"order":0.5}'
  # room rule with no actions silences the room; mention rules rank higher, so mentions still notify
  [ "$sp" = Communities ] && run api PUT "/pushrules/global/room/$(enc "$room")" '{"actions":[]}'
done < "$file"
