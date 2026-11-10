# Spoken word: Audiobookshelf for podcasts and audiobooks.
#
#   /mnt/music/spoken/Podcasts    downloaded here by Audiobookshelf
#   /mnt/music/spoken/Audiobooks  ~/drop/Audiobooks on the laptop, moved here
#                                 by drop-sort (server/services/syncthing.nix)
#                    |
#             Audiobookshelf, one library per folder
#
# Audiobookshelf cannot see new files on CIFS by itself (no inotify), so the
# Audiobooks library's own scheduled scan picks them up: set it once in the
# web UI, Library -> Edit -> Schedule, to daily at 03:30 UTC (after drop-sort).
{ ... }:
{
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

  # Users, progress and subscriptions. The files themselves are on the box.
  fox.server.backup = {
    paths = [ "/var/lib/audiobookshelf" ];
    sqlite = [ "/var/lib/audiobookshelf/config/absdatabase.sqlite" ];
  };
}
