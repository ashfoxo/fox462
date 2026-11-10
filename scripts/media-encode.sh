#!/usr/bin/env bash
# Encode $MEDIA/{TV,Movies}/Originals into .../Converted as H.265. MEDIA is
# any rclone path: /var/lib/media on fox-copper, filen:/Media by default.
#
# Runs nightly on fox-copper (modules/server/services/dvd-rip.nix), and by
# hand on a rented box for a big backlog (hosts/fox-copper/README.md). Needs
# bash, rclone, ffmpeg and ffprobe. For filen:, rclone 1.70+ and the
# RCLONE_CONFIG_FILEN_* variables from filen-rclone.env in the environment.
#
# Originals is never modified, except that empty folders are removed. A
# file is done once Converted holds a file of the same path (always .mkv),
# so an interrupted run picks up where it stopped. Non-video files (art,
# .nfo, subtitles) are copied over as they are. A file that fails is
# skipped, and the run exits non-zero at the end.
#
#   WORK   scratch directory, needs room for JOBS originals plus their encodes
#   JOBS   files handled at once (default 1). Filen gives each transfer
#          only a slice of the bandwidth, so a big server wants several.
#   CRF    x265 quality, lower is better and bigger (default 22)
#   PRESET x265 speed (default medium)
set -euo pipefail

work=${WORK:-/var/tmp/media-encode}
media=${MEDIA:-filen:/Media}
crf=${CRF:-22}
preset=${PRESET:-medium}
jobs=${JOBS:-1}
mkdir -p "$work"
rm -f "$work/failed"
rm -rf "$work"/job.*
trap 'rm -rf "$work"/job.*' EXIT
export LC_ALL=C
# Filen is faster with one connection per transfer than with all of them
# multiplexed over HTTP/2 (as jellyfin.nix's media-sync).
export RCLONE_DISABLE_HTTP2=true

# one <src> <dst> <path> <out path>. Returns non-zero on any failure (set -e
# is off inside a function called with ||).
one() {
  local src=$1 dst=$2 f=$3 out=$4 tmp in codec field vf video
  if [ "$out" = "$f" ] && [[ "${f,,}" != *.mkv ]]; then
    echo "copy: $f"
    rclone copyto "$src/$f" "$dst/$f" || return 1
    return 0
  fi

  echo "encode: $f"
  tmp=$(mktemp -d "$work/job.XXXXXX") || return 1
  in="$tmp/in.${f##*.}"
  rclone copyto "$src/$f" "$in" || { rm -rf "$tmp"; return 1; }
  IFS=, read -r codec field < <(ffprobe -v error -select_streams v:0 \
    -show_entries stream=codec_name,field_order -of csv=p=0 "$in") || true

  if [ "${codec:-}" = hevc ]; then
    video=(-c:v copy)
  else
    # DVDs are often interlaced; bwdif is a good general deinterlacer.
    # shortcut: no inverse telecine, so telecined film DVDs get bwdif too;
    # add fieldmatch,decimate if a movie shows judder.
    vf=()
    case "${field:-}" in tt|bb|tb|bt) vf=(-vf bwdif=mode=send_frame) ;; esac
    video=(-c:v libx265 -preset "$preset" -crf "$crf" "${vf[@]}" -x265-params log-level=error)
  fi

  # Every audio and subtitle track kept as is; mkv holds them all. genpts:
  # old AVIs often lack timestamps, which mkv needs for copied audio.
  ffmpeg -nostdin -hide_banner -loglevel error -y -fflags +genpts -i "$in" \
    -map 0:v:0 -map 0:a? -map 0:s? -c copy "${video[@]}" "$tmp/out.mkv" || { rm -rf "$tmp"; return 1; }
  rclone copyto "$tmp/out.mkv" "$dst/$out" || { rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
}

for kind in TV Movies; do
  src="$media/$kind/Originals"
  dst="$media/$kind/Converted"
  rclone mkdir "$src"
  rclone mkdir "$dst"
  rclone lsf -R --files-only "$dst" | sort > "$work/done.list"

  rclone lsf -R --files-only "$src" | sort | { while IFS= read -r f; do
    case "${f,,}" in
      *.mkv|*.mp4|*.m4v|*.avi) out="${f%.*}.mkv" ;;
      *) out="$f" ;;
    esac
    grep -qxF -- "$out" "$work/done.list" && continue
    # At most $jobs at once; each runs in the background.
    while [ "$(jobs -rp | wc -l)" -ge "$jobs" ]; do wait -n || true; done
    { one "$src" "$dst" "$f" "$out" < /dev/null || { echo "FAILED: $f" >&2; touch "$work/failed"; }; } &
  done; wait; }   # wait inside the braces: the loop runs in a pipeline subshell

  # Empty show and movie folders, e.g. once you've moved a rip elsewhere.
  rclone rmdirs --leave-root "$src"
  rclone rmdirs --leave-root "$dst"
done

[ ! -e "$work/failed" ] || { echo "media-encode: some files failed, see above" >&2; exit 1; }
echo "media-encode: done"
