# YouTube channels as Jellyfin shows (ytdl-sub), into /mnt/music/video/YouTube
# next to jellyfin.nix's libraries. Add that folder once in Jellyfin as a
# Shows library. Each channel is a show; episodes are numbered by upload date.
#
# Everything from the last year is downloaded, and nothing is ever deleted
# (a video that ages past a year stays). A new channel: one line under
# subscriptions below.
#
# shortcut: YouTube often blocks data-center IPs ("confirm you're not a
# bot"). If ytdl-sub starts failing with that, run it from fox-copper's home
# IP instead, and bring it over with `copper pull` (which would then need a
# YouTube folder).
{ pkgs, ... }:
let
  dir = "/mnt/music/video/YouTube";
in
{
  # The share mounts as navidrome:navidrome, group-writable (music.nix).
  services.ytdl-sub.group = "navidrome";

  services.ytdl-sub.instances.youtube = {
    enable = true;
    schedule = "*-*-* 07:30:00";   # after media-sync, clear of the music jobs
    readWritePaths = [ "/mnt/music/video" ];   # exists (jellyfin.nix); YouTube may not yet
    subscriptions = {
      __preset__ = {
        date_range.after = "today-1year";
        # Unthrottled, YouTube answered 429 and "not a bot" after ~40 videos
        # even from a home IP. Videos that fail are retried the next day.
        ytdl_options = {
          sleep_interval_requests = 3;
          sleep_interval = 15;
          max_sleep_interval = 45;
        };
        overrides.tv_show_directory = dir;
      };
      "Jellyfin TV Show by Date" = {
        # /videos skips Shorts.
        "Last Week Tonight" = "https://www.youtube.com/@LastWeekTonight/videos";
      };
    };
  };

  systemd.services.ytdl-sub-youtube = {
    # Newer yt-dlp needs a JavaScript runtime for YouTube.
    path = [ pkgs.deno ];
    # Without the share, downloads would go nowhere it can write.
    unitConfig = {
      AssertPathIsMountPoint = "/mnt/music";
      RequiresMountsFor = "/mnt/music";
    };
    preStart = "mkdir -p '${dir}'";
    serviceConfig.TimeoutStartSec = "6h";   # the first run fetches a year
  };

  fox.server.monitoring.alertOnFailure.ytdl-sub-youtube.title = "YouTube download FAILED";
}
