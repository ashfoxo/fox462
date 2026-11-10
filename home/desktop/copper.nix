# `copper pull` / `copper done`: fox-copper's DVD rips into Filen, by hand.
# fox-copper holds no Filen login, so its rips pile up on its drive
# (modules/server/services/dvd-rip.nix) until you fetch them:
#
#   copper pull   copies every encoded rip and its original into ~/copper
#                 (as many as fit, leaving 10 GB free), laid out like Filen's
#                 Media folder. The encoded copies also go into ~/drop, so
#                 fox-red's Jellyfin gets them on its own.
#                 Then upload ~/copper/Movies and ~/copper/TV into Filen's
#                 Media folder.
#   copper done   once Filen has finished uploading: deletes what's in
#                 ~/copper there and on fox-copper. Only files whose size
#                 matches are deleted on fox-copper; rips that aren't encoded
#                 yet stay there either way.
#
# One YubiKey touch per command (the SSH connection is shared for a minute).
{ pkgs, ... }:
let
  copper = pkgs.writeShellApplication {
    name = "copper";
    runtimeInputs = with pkgs; [ openssh rsync coreutils findutils gnugrep ];
    text = ''
      dest=$HOME/copper
      sock="''${XDG_RUNTIME_DIR:-/tmp}/copper-ssh"
      sshopts="-o ControlMaster=auto -o ControlPath=$sock -o ControlPersist=60"
      # shellcheck disable=SC2086,SC2029  # sshopts is several words; args expand here on purpose
      on_copper() { ssh $sshopts fox-copper "$@"; }

      case "''${1:-}" in
        pull)
          mkdir -p "$dest"
          list=$(mktemp)
          trap 'rm -f "$list"' EXIT
          room=$(( $(df --output=avail -B1 "$dest" | tail -n1) - 10 * 1024 * 1024 * 1024 ))
          ready=$(on_copper media-ready)
          n=0 total=0 left=0
          while IFS=$'\t' read -r -a f; do
            [ -n "''${f[0]:-}" ] || continue
            [ -e "$dest/''${f[1]}" ] && continue   # pulled before, not done yet
            if [ "''${f[0]}" -gt "$room" ]; then left=$((left + 1)); continue; fi
            room=$((room - f[0])) total=$((total + f[0])) n=$((n + 1))
            printf '%s\n' "''${f[@]:1}" >> "$list"
          done <<< "$ready"
          if [ "$n" = 0 ]; then
            echo "Nothing new on fox-copper ($left more that don't fit)."
            exit 0
          fi

          echo "Pulling $n rips, $((total / 1024 / 1024 / 1024)) GB."
          rsync -a --info=progress2 -e "ssh $sshopts" --files-from="$list" fox-copper:/var/lib/media/ "$dest/"
          # The encoded copies to ~/drop/{Movies,TV}, for Jellyfin.
          grep '/Converted/' "$list" | while IFS= read -r p; do
            to="$HOME/drop/''${p%%/*}/''${p#*/Converted/}"
            mkdir -p "$(dirname "$to")"
            cp --reflink=auto "$dest/$p" "$to"
          done

          echo
          echo "Done. The encoded copies are in ~/drop, on their way to Jellyfin."
          [ "$left" = 0 ] || echo "$left more are waiting on fox-copper: no room. Pull again after copper done."
          echo "Next: upload ~/copper/Movies and ~/copper/TV into Filen's Media folder."
          echo "When Filen has finished uploading: copper done"
          ;;

        done)
          if [ -z "$(find "$dest" -type f -print -quit 2>/dev/null)" ]; then
            echo "$dest is empty."
            exit 0
          fi
          du -sh "$dest"
          read -rp "Has Filen finished uploading all of ~/copper? This deletes it here and on fox-copper. Type done: " a
          [ "$a" = "done" ] || exit 1
          (cd "$dest" && find . -type f -printf '%s\t%P\n') | on_copper media-forget
          rm -rf "$dest"
          echo "Deleted from ~/copper and fox-copper."
          ;;

        *)
          echo "usage: copper pull | copper done" >&2
          exit 1
          ;;
      esac
    '';
  };
in
{
  home.packages = [ copper ];
}
