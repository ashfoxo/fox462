# DVD ripping and H.265 encoding, fox-copper's whole job.
#
#   insert a DVD
#     |  dvd-rip: MakeMKV, lossless. scripts/dvd-classify.sh sorts the disc
#     |  by its title lengths, and it ejects as soon as the rip is done, so
#     |  the next disc can go in while dvd-upload@<rip> sends this one:
#     |    movie  -> Media/Movies/Originals/<Title (Year)>/<Title (Year)>.mkv  (feature only)
#     |    tv     -> Media/Unsorted/TV/<label>-<date>/  (episodes only)
#     |    other  -> Media/Unsorted/<label>-<date>/  (every title of 10+ min)
#     |  Unsorted is yours to name and move into {Movies,TV}/Originals.
#   Filen:/Media/{Movies,TV}/Originals
#     |  media-encode, nightly (scripts/media-encode.sh)
#   Filen:/Media/{Movies,TV}/Converted      -> fox-red's Jellyfin (jellyfin.nix)
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
  fox.server.filenUnits = [ "dvd-rip" "dvd-upload@" "media-encode" ];

  # MakeMKV talks to the drive through the SCSI generic device.
  boot.kernelModules = [ "sg" ];

  # A DVD going in (a media change on the drive) starts a rip.
  services.udev.extraRules = ''
    ACTION=="change", SUBSYSTEM=="block", KERNEL=="sr0", ENV{ID_CDROM_MEDIA_DVD}=="1", RUN+="${pkgs.systemd}/bin/systemctl --no-block start dvd-rip.service"
  '';

  systemd.services.dvd-rip = {
    description = "Rip the DVD in /dev/sr0 to Filen";
    restartIfChanged = false;   # a deploy must never kill a rip in progress
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "dvd-rip";   # MakeMKV's settings and the rip itself
      TimeoutStartSec = "4h";
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
        rclone lsf "filen:/Media/Movies/Originals/$name" >/dev/null 2>&1 && kind=other
        # ...or one ripped here and still waiting to upload.
        cat /var/lib/dvd-rip/rips/*/upload 2>/dev/null | grep -qxF "Movies/Originals/$name" && kind=other
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

      # Hand the rip to its own upload job and free the drive. From here the
      # folder is the upload's, so it isn't removed on exit.
      printf '%s\n%s\n' "$dest" "$label" > "$out/upload"
      trap - EXIT
      systemctl --no-block start "dvd-upload@$stamp.service"
      eject "$dev" || true
      ${notify} "${host}: DVD ripped ($kind)" "$label is uploading to Filen Media/$dest. Next disc!" default
    '';
  };
  fox.server.monitoring.alertOnFailure.dvd-rip.title = "DVD rip FAILED";

  # One per rip, several at once if discs go in faster than uploads finish.
  # A failed upload keeps its folder; retry with
  #   sudo systemctl start dvd-upload@<rip>   (the folder name in /var/lib/dvd-rip/rips)
  # shortcut: an upload cut off by a reboot isn't resumed on its own; start
  # it again the same way.
  systemd.services."dvd-upload@" = {
    description = "Upload DVD rip %i to Filen";
    restartIfChanged = false;
    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "6h";
    };
    path = [ pkgs.coreutils pkgs.gnused ];
    scriptArgs = "%i";
    # The template can't use alertOnFailure (its notify unit would be a
    # template too), so it alerts itself.
    script = ''
      set -uo pipefail
      d=/var/lib/dvd-rip/rips/$1
      dest=$(sed -n 1p "$d/upload"); label=$(sed -n 2p "$d/upload")
      if rclone copy "$d/rip" "filen:/Media/$dest" --retries 3; then
        rm -rf "$d"
        ${notify} "${host}: DVD uploaded" "$label is in Filen Media/$dest." min
      else
        ${notify} "${host}: DVD upload FAILED" \
          "$label is still on ${host}. Retry: sudo systemctl start dvd-upload@$1" high
        exit 1
      fi
    '';
  };

  systemd.services.media-encode = {
    description = "Encode Filen media Originals to H.265";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      CacheDirectory = "media-encode";   # one original and its encode at a time
      Nice = 15;
      IOSchedulingClass = "idle";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
    environment.WORK = "/var/cache/media-encode";
    path = [ pkgs.bash pkgs.ffmpeg-headless pkgs.coreutils pkgs.gnugrep ];
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
