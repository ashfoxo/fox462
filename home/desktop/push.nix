# `push`: copy ~/drop to Filen with rclone, by hand, at full speed.
#
# Run it inside ~/drop (all four folders) or inside one of them (just that
# one, or a subfolder of it). It only copies, never deletes: drop-clean
# (syncthing.nix) empties ~/drop later.
#
#   ~/drop/Movies/…      ->  Media/Movies/Converted/…
#   ~/drop/TV/…          ->  Media/TV/Converted/…
#   ~/drop/Audiobooks/…  ->  Media/Spoken/Audiobooks/…
#   ~/drop/Music/…       ->  Media/Music/Pirated/…
#
# One-time setup: `rclone config`, add a remote named "filen" (type filen).
# The login lives in ~/.config/rclone (persisted in modules/ephemeral-home.nix).
{ pkgs, ... }:
let
  push = pkgs.writeShellApplication {
    name = "push";
    runtimeInputs = with pkgs; [ rclone coreutils findutils ];
    text = ''
      drop=$HOME/drop
      remote=''${PUSH_REMOTE:-filen}

      # Filen is faster with one connection per transfer than with all of them
      # multiplexed over HTTP/2 (same as scripts/media-encode.sh).
      export RCLONE_DISABLE_HTTP2=true

      here=$(realpath -m "$PWD")
      case "$here" in
        "$drop"|"$drop"/*) ;;
        *) echo "push: run it inside $drop" >&2; exit 1 ;;
      esac

      if ! rclone lsd "$remote:" >/dev/null 2>&1; then
        echo "push: no working rclone remote called \"$remote\". Run: rclone config" >&2
        exit 1
      fi

      # push_dir <local dir> <path inside the Filen drive>
      push_dir() {
        [ -n "$(find "$1" -type f -not -name '.syncthing.*' -not -path '*/.st*' -print -quit)" ] || { echo "Nothing in $1"; return 0; }
        echo "== $1 -> $remote:$2"
        rclone copy "$1" "$remote:$2" \
          --progress --stats 1s \
          --transfers 8 --checkers 16 \
          --exclude '.syncthing.*' --exclude '.stfolder' --exclude '.stversions/**'
      }

      # dest_for <top folder in ~/drop>
      dest_for() {
        case "$1" in
          Movies)     echo "Media/Movies/Converted" ;;
          TV)         echo "Media/TV/Converted" ;;
          Audiobooks) echo "Media/Spoken/Audiobooks" ;;
          Music)      echo "Media/Music/Pirated" ;;
          *)          return 1 ;;
        esac
      }

      if [ "$here" = "$drop" ]; then
        for top in Movies TV Audiobooks Music; do
          [ -d "$drop/$top" ] && push_dir "$drop/$top" "$(dest_for "$top")"
        done
        # Loose files straight in ~/drop have nowhere to go.
        loose=$(find "$drop" -mindepth 1 -maxdepth 1 -not -name Movies -not -name TV -not -name Audiobooks -not -name Music -not -name '.st*' -print)
        [ -z "$loose" ] || { echo "Skipped (not in Movies, TV, Audiobooks or Music):"; echo "$loose"; }
      else
        rel=''${here#"$drop"/}
        top=''${rel%%/*}
        sub=''${rel#"$top"}
        dest=$(dest_for "$top") || { echo "push: $top is not one of Movies, TV, Audiobooks, Music" >&2; exit 1; }
        push_dir "$here" "$dest$sub"
      fi
    '';
  };
in
{
  home.packages = [ push ];
}
