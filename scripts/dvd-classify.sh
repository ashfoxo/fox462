#!/usr/bin/env bash
# Decide what a DVD is from `makemkvcon -r --minlength=600 info` on stdin,
# using only title lengths. Prints one line:
#   movie <title>        a feature (70+ min): rip just that title
#   tv <title>...        2+ episodes of similar length (15-70 min, longest
#                        no more than 1.3x the shortest): rip those
#   other                unclear: rip every title for a human to sort
#   none                 no video titles (a data disc)
# A long title as long as the episodes together is "play all", so still TV.
# A long title beside similar-length shorter ones that aren't a play-all is
# a movie with extras or a TV disc: "other", so no feature is ever skipped.
# Used by modules/server/services/dvd-rip.nix; tested by dvd-classify-test.sh.
set -euo pipefail
awk -F, '
  /^TINFO:/ && $2 == 9 {
    id = substr($1, 7) + 0
    v = $4; gsub(/"/, "", v)
    n = split(v, t, ":"); s = 0
    for (i = 1; i <= n; i++) s = s * 60 + t[i]
    dur[id] = s; if (id > top) top = id; seen = 1
  }
  END {
    if (!seen) { print "none"; exit }
    long = -1; max = 0; ne = 0; sum = 0; lo = 1e9; hi = 0
    for (id = 0; id <= top; id++) {
      if (!(id in dur)) continue
      d = dur[id]
      if (d > max) { max = d; long = id }
      if (d >= 900 && d < 4200) {
        eps = eps " " id; ne++; sum += d
        if (d < lo) lo = d; if (d > hi) hi = d
      }
    }
    similar = ne >= 2 && hi <= 1.3 * lo
    playall = similar && max >= 4200 && max >= 0.9 * sum && max <= 1.1 * sum
    if (playall)          print "tv" eps
    else if (max >= 4200) print (similar ? "other" : "movie " long)
    else                  print (similar ? "tv" eps : "other")
  }'
