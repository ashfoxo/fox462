# Spoken word: Audiobookshelf for podcasts and audiobooks, with its files
# copied to and from Filen.
#
#   /mnt/music/spoken/Podcasts    --- copy up, nightly --->   Filen:/Media/Spoken/Podcasts
#   /mnt/music/spoken/Audiobooks  <-- copy both ways ----->   Filen:/Media/Spoken/Audiobooks
#                    |
#             Audiobookshelf, one library per folder
#
# Podcasts are downloaded here by Audiobookshelf, so Filen only gets a backup
# copy. They are never pulled back down, so episodes Audiobookshelf cleans up
# stay deleted here (Filen keeps them). Audiobooks are the music pattern plus
# the reverse: drop a book in Filen and it comes down, add one here and it goes up.
#
# copy, never sync: nothing is deleted in Filen. To remove an audiobook for
# good, delete it in Filen AND here, or the pull puts it back.
#
# Audiobookshelf cannot see new files on CIFS by itself (no inotify), so the
# Audiobooks library's own scheduled scan picks them up: set it once in the
# web UI, Library -> Edit -> Schedule, to daily at 03:30 UTC (after this job).
{ config, pkgs, ... }:
let
  spokenDir = "/mnt/music/spoken";
  remote = "filen:/Media/Spoken";
in
{
  # filen-rclone.env is described in music-ingest.nix; listing it twice is harmless.
  fox.server.secretNames = [ "filen-rclone.env" ];

  # 8000 is AudioMuse's; 13378 is Audiobookshelf's usual port.
  services.audiobookshelf = {
    enable = true;
    port = 13378;
  };

  # Same share as the music, which mounts as navidrome:navidrome. Group
  # write on the mount (music.nix) lets Audiobookshelf save episodes there.
  users.users.audiobookshelf.extraGroups = [ "navidrome" ];
  systemd.services.audiobookshelf.after = [ "remote-fs.target" ];

  fox.server.privateSites.spoken.upstream = "127.0.0.1:13378";

  # Users, progress and subscriptions. The files themselves are on the box and in Filen.
  fox.server.backup = {
    paths = [ "/var/lib/audiobookshelf" ];
    sqlite = [ "/var/lib/audiobookshelf/config/absdatabase.sqlite" ];
  };

  systemd.services.spoken-sync = {
    description = "Copy podcasts and audiobooks between Filen and the Storage Box";
    after = [ "network-online.target" "remote-fs.target" ];
    wants = [ "network-online.target" ];
    # Without the mount, the pull would fill the VPS's own disk.
    unitConfig = {
      AssertPathIsMountPoint = "/mnt/music";
      RequiresMountsFor = "/mnt/music";
    };
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = [ "/run/secrets/filen-rclone.env" ];
      TimeoutStartSec = "6h";
      ProtectSystem = "strict";
      ReadWritePaths = [ "/mnt/music" ];
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      Nice = 10;
      IOSchedulingClass = "idle";
    };
    environment.RCLONE_CONFIG = "/dev/null";
    path = [ pkgs.rclone ];
    # --size-only: Filen and CIFS share no hash, and comparing mod times
    # across them would risk re-sending everything every night.
    script = ''
      set -euo pipefail
      mkdir -p ${spokenDir}/Podcasts ${spokenDir}/Audiobooks
      flags="--size-only --transfers 4 --checkers 8 --retries 3 --stats 5m --stats-log-level NOTICE"
      rclone copy ${remote}/Audiobooks ${spokenDir}/Audiobooks $flags
      rclone copy ${spokenDir} ${remote} $flags
    '';
  };

  # After music ingest (02:10), before the 03:00-05:00 upgrade window.
  systemd.timers.spoken-sync = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 02:40:00";
      RandomizedDelaySec = "10m";
      Persistent = true;
    };
  };

  fox.server.monitoring.alertOnFailure.spoken-sync.title = "spoken sync FAILED";
}
