# DVD ripping and H.265 encoding, fox-copper's whole job.
#
#   insert a DVD
#     |  dvd-rip: MakeMKV, lossless. scripts/dvd-classify.sh sorts the disc
#     |  by its title lengths, and ejects when done. Into /var/lib/media on
#     |  this machine; it holds no Filen login:
#     |    movie  -> Movies/Originals/<Title (Year)>/<Title (Year)>.mkv  (feature only)
#     |    tv     -> Unsorted/TV/<label>-<date>/  (episodes only)
#     |    other  -> Unsorted/<label>-<date>/  (every title of 10+ min)
#     |  Unsorted is yours to name and move into {Movies,TV}/Originals:
#     |  ssh fox-copper and mv in /var/lib/media (group users, no sudo).
#   /var/lib/media/{Movies,TV}/Originals
#     |  media-encode, nightly (scripts/media-encode.sh)
#   /var/lib/media/{Movies,TV}/Converted
#     |  `copper pull` on the laptop (home/desktop/copper.nix): to ~/copper
#     |  for you to put in Filen, and to ~/drop for fox-red's Jellyfin.
#
# TV stays by hand because a disc can't say which season or episode it is.
# A movie is named from the disc label and TMDB ("INTERSTELLAR" ->
# "Interstellar (2014)"), or the label alone if TMDB has no exact match;
# if Jellyfin matches one wrong, fix it with Identify in Jellyfin, no renaming.
# DVD ripping is free in MakeMKV; only Blu-ray needs a key.
# shortcut: MakeMKV betas stop running about 60 days after release ("This
# application version is too old"), so it comes from nixos-unstable, which
# updates it soonest; when it expires, update flake.lock. A bought key, or
# ffmpeg's own DVD reader, would end this for good.
{ config, pkgs, lib, srv, inputs, ... }:
let
  inherit (srv) notify;
  host = config.networking.hostName;
  media = "/var/lib/media";
  # Unfree, so no binary cache: it compiles on fox-copper at deploy.
  makemkv = (import inputs.nixpkgs-unstable {
    inherit (pkgs.stdenv.hostPlatform) system;
    config.allowUnfreePredicate = pkg: lib.getName pkg == "makemkv";
  }).makemkv;
  # First TMDB movie result whose title is the label, as "Title (Year)".
  tmdbPick = pkgs.writeText "tmdb-pick.jq" ''
    def norm: ascii_downcase | gsub("[^a-z0-9]"; "");
    [ .results[]
      | select(((.title // "" | norm) == ($q | norm) or (.original_title // "" | norm) == ($q | norm))
               and ((.release_date // "") | length) >= 4) ][0]
    | select(. != null) | "\(.title) (\(.release_date[:4]))"
  '';
in
{

  # tmdb.env: the API Read Access Token, from themoviedb.org > Settings > API
  # (free), for movie years. The bare token or TMDB_TOKEN=<token>; both work.
  fox.server.secretNames = [ "tmdb.env" ];

  # Group users (arlo) can read, rename and delete; setgid so what's made
  # inside gets the group too.
  systemd.tmpfiles.rules = map (d: "d ${media}${d} 2775 root users -")
    [ "" "/Movies" "/Movies/Originals" "/Movies/Converted" "/TV" "/TV/Originals" "/TV/Converted" "/Unsorted" ];

  # For `copper pull` / `copper done` on the laptop (home/desktop/copper.nix),
  # run over SSH as arlo.
  environment.systemPackages = [
    # Each encoded rip with its original, one per line:
    # <bytes of both>\t<Converted path>\t<Originals path>...
    (pkgs.writeShellApplication {
      name = "media-ready";
      runtimeInputs = [ pkgs.coreutils pkgs.findutils ];
      text = ''
        cd ${media}
        { find Movies/Converted TV/Converted -type f -not -name '*.partial' 2>/dev/null || true; } | sort |
        while IFS= read -r c; do
          o=''${c/\/Converted\//\/Originals\/}
          line=$c
          size=$(stat -c %s "$c")
          for f in "''${o%.*}".*; do
            [ -f "$f" ] || continue
            line+=$'\t'$f
            size=$((size + $(stat -c %s "$f")))
          done
          printf '%s\t%s\n' "$size" "$line"
        done
      '';
    })
    # Deletes the <bytes>\t<path> lines on stdin, each only if its size
    # still matches, then the folders left empty. Unsorted is never touched.
    (pkgs.writeShellApplication {
      name = "media-forget";
      runtimeInputs = [ pkgs.coreutils pkgs.findutils ];
      text = ''
        cd ${media}
        while IFS=$'\t' read -r size path; do
          case $path in
            *..*) echo "skipped: $path" >&2; continue ;;
            Movies/Originals/*|Movies/Converted/*|TV/Originals/*|TV/Converted/*) ;;
            *) echo "skipped: $path" >&2; continue ;;
          esac
          if [ -f "$path" ] && [ "$(stat -c %s "$path")" = "$size" ]; then
            rm -f -- "$path"
          else
            echo "kept on ${host} (missing or a different size): $path" >&2
          fi
        done
        find Movies TV -mindepth 2 -type d -empty -delete 2>/dev/null || true
      '';
    })
  ];

  # MakeMKV talks to the drive through the SCSI generic device.
  boot.kernelModules = [ "sg" ];

  # A DVD going in (a media change on the drive) starts a rip.
  services.udev.extraRules = ''
    ACTION=="change", SUBSYSTEM=="block", KERNEL=="sr0", ENV{ID_CDROM_MEDIA_DVD}=="1", RUN+="${pkgs.systemd}/bin/systemctl --no-block start dvd-rip.service"
  '';

  systemd.services.dvd-rip = {
    description = "Rip the DVD in /dev/sr0 to ${media}";
    restartIfChanged = false;   # a deploy must never kill a rip in progress
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "dvd-rip";   # MakeMKV's settings and the rip itself
      TimeoutStartSec = "4h";
      UMask = "0002";   # folders it makes stay group-writable (Unsorted is yours to move)
    };
    environment.HOME = "/var/lib/dvd-rip";
    path = with pkgs; [ makemkv util-linux eject coreutils gawk gnused gnugrep bash curl jq systemd ];
    script = ''
      set -euo pipefail
      dev=/dev/sr0   # the laptop's only drive
      label=$(blkid -o value -s LABEL "$dev" || true)
      label=''${label:-DVD}
      stamp=$(date +%F-%H%M)
      out=/var/lib/dvd-rip/rips/$stamp
      mkdir -p "$out/rip"
      trap 'rm -rf "$out"' EXIT
      mm() { makemkvcon -r --minlength=600 "$@"; }   # same titles for info and mkv

      mm info "dev:$dev" > "$out/info.txt"
      read -r kind titles < <(bash ${../../../scripts/dvd-classify.sh} < "$out/info.txt")
      if [ "$kind" = none ]; then
        eject "$dev" || true
        ${notify} "${host}: not a video DVD" "$label has no video titles. Ejected." default
        exit 0
      fi

      # A generic label, or a movie already ripped under this name, would
      # overwrite another movie: those go to Unsorted for you to name.
      name=$(echo "$label" | sed 's/_/ /g; s/.*/\L&/; s/\b./\u&/g')
      if [ "$kind" = movie ]; then
        # "Title (Year)" from TMDB, but only when a result's title matches the
        # label exactly (ignoring case and punctuation); otherwise the label
        # name, without a year. The most popular match wins, so a remake
        # (Dune 1984 or 2021) may need Identify in Jellyfin.
        # Whitespace stripped: a pasted token can carry a \r, and curl refuses
        # a header containing one (error 43).
        tok=$(tr -d ' \t\r\n' < /run/secrets/tmdb.env | sed 's/^TMDB_TOKEN=//')
        hit=$(curl -fsS -m 20 --get https://api.themoviedb.org/3/search/movie \
                -H "Authorization: Bearer $tok" --data-urlencode "query=$name" \
              | jq -r --arg q "$name" -f ${tmdbPick}) || true
        [ -n "$hit" ] && name=$(printf '%s' "$hit" | sed 's/: / - /g; s#[/\\:*?"<>|]##g')

        case "$label" in DVD|DVD_VIDEO|DVDVOLUME|DVD_ROM) kind=other ;; esac
        [ -e "${media}/Movies/Originals/$name" ] && kind=other
      fi
      [ "$kind" = other ] && titles=all

      for t in $titles; do mm mkv "dev:$dev" "$t" "$out/rip"; done
      ls "$out"/rip/*.mkv >/dev/null   # nothing ripped is a failure

      case "$kind" in
        movie) dest="Movies/Originals/$name"
               mv "$(ls "$out"/rip/*.mkv)" "$out/rip/$name.mkv" ;;
        tv)    dest="Unsorted/TV/$label-$stamp" ;;
        *)     dest="Unsorted/$label-$stamp" ;;
      esac

      # Same filesystem, so a rename: the encode never sees half a rip.
      mkdir -p "$(dirname "${media}/$dest")"
      mv "$out/rip" "${media}/$dest"
      chgrp -R users "${media}/$dest"
      chmod -R g+rwX,o-w "${media}/$dest"   # MakeMKV writes 666
      eject "$dev" || true
      ${notify} "${host}: DVD ripped ($kind)" "$label is in ${media}/$dest. Next disc!" default
    '';
  };
  fox.server.monitoring.alertOnFailure.dvd-rip.title = "DVD rip FAILED";

  systemd.services.media-encode = {
    description = "Encode ${media} Originals to H.265";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      CacheDirectory = "media-encode";   # one original and its encode at a time
      ReadWritePaths = [ media ];
      UMask = "0002";   # group-writable, so `copper done` (as arlo) can delete
      Nice = 15;
      IOSchedulingClass = "idle";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
    environment = {
      WORK = "/var/cache/media-encode";
      MEDIA = media;
      RCLONE_CONFIG = "/dev/null";   # local folders only, no remote to configure
    };
    path = [ pkgs.bash pkgs.ffmpeg-headless pkgs.coreutils pkgs.gnugrep pkgs.rclone ];
    script = "exec bash ${../../../scripts/media-encode.sh}";
  };

  # No timeout: a backlog takes as long as it takes. A run still going at
  # the next 02:00 just means the timer does nothing that night.
  systemd.timers.media-encode = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 02:00:00";
      Persistent = true;
    };
  };
  fox.server.monitoring.alertOnFailure.media-encode.title = "media encode FAILED";
}
