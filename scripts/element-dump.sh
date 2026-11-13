#!/usr/bin/env bash
# Read-only: lists your joined rooms to a TSV with an auto-suggested Space. Edit the file, then run element-apply.sh.
# usage: MATRIX_TOKEN=... MATRIX_HS=https://matrix.<domain> ./element-dump.sh > ~/element-rooms.tsv   (keep it out of the repo)
set -euo pipefail
. "$(dirname "$0")/element-lib.sh"
SMALL=15  # groups with more members than this go to Communities
dms=$(api GET "/user/$(enc "$ME")/account_data/m.direct" 2>/dev/null | jq -r '[.[][]]|join(" ")' || true)
printf '# room_id\tname\tkind\tmembers\tbridge\tspace\tfav\tlow\tpeople\n# space: Family|Friends|Gay|Furry|Feed|Small groups|Communities|Misc (blank = skip). fav/low: x\n'
for r in $(api GET /joined_rooms | jq -r '.joined_rooms[]'); do
  e=$(enc "$r")
  [ "$(api GET "/rooms/$e/state/m.room.create" | jq -r '.type // ""')" = m.space ] && continue
  name=$(api GET "/rooms/$e/state/m.room.name" 2>/dev/null | jq -r '.name // ""' || true)
  joined=$(api GET "/rooms/$e/joined_members"); members=$(jq -r ".joined|keys" <<<"$joined")
  n=$(jq length <<<"$members")
  # shortcut: bridge guessed from bot/ghost user IDs containing the network name; fix by hand if wrong
  bridge=$(jq -r '[.[]|capture("(?<b>telegram|discord|instagram|meta|gmessages|googlemessages)";"i")?|.b]|.[0] // ""' <<<"$members")
  if [[ " $dms " == *" $r "* ]]; then kind=dm; sp=Friends
  elif [ "${bridge,,}" = discord ] || [ "$n" -gt "$SMALL" ]; then kind=group; sp=Communities
  elif [ -z "$name" ]; then kind=group; sp=Misc
  else kind=group; sp="Small groups"; fi
  people=$(jq -r --arg me "$ME" '.joined|to_entries|map(select(.key!=$me)|.value.display_name // .key)|join("; ")' <<<"$joined")
  printf '%s\t%s\t%s\t%s\t%s\t%s\t\t\t%s\n' "$r" "${name:-(unnamed)}" "$kind" "$n" "$bridge" "$sp" "$people"
done
