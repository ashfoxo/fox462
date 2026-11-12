# TV and movie requests. Seerr (request.<privateDomain>) is where you ask for
# something. Sonarr (tv.) and Radarr (movies.) find it through Prowlarr
# (indexers.), have qBittorrent fetch it inside the Mullvad-only qbt
# namespace (torrent.nix), then hardlink the finished files into Jellyfin's
# library: /mnt/music/video/{TV,Movies}. All four are NetBird-only, behind
# Caddy; the *arr apps listen on 127.0.0.1 only.
#
# Their traffic (indexer searches, metadata) leaves from fox-red's own IP.
# Only the torrents themselves go through Mullvad.
#
# Set up once in the web UIs: see fox-red's README, "Requests".
{ config, lib, ... }:
let
  # Sonarr and Radarr hardlink from torrents/ into video/, which only works
  # within one mount. A per-folder sandbox would make each folder its own
  # mount, so they get the share whole, minus what they have no business in.
  # shortcut: a denylist; a new top-level folder on the share is visible to
  # them until it's added here.
  shareSandbox = {
    unitConfig = {
      AssertPathIsMountPoint = "/mnt/music";
      RequiresMountsFor = "/mnt/music";
    };
    serviceConfig = {
      ProtectSystem = "strict";
      ReadWritePaths = [ "/mnt/music" ];
      InaccessiblePaths = map (d: "-/mnt/music/${d}")
        [ "drop" "ente-export" "inbox" "library" "spoken" "video/YouTube" ];
    };
  };
in
{
  # In the navidrome group: the share is group-writable (music.nix).
  services.sonarr = {
    enable = true;
    group = "navidrome";
    settings.server.bindaddress = "127.0.0.1";
  };
  services.radarr = {
    enable = true;
    group = "navidrome";
    settings.server.bindaddress = "127.0.0.1";
  };
  services.prowlarr = {
    enable = true;
    settings.server.bindaddress = "127.0.0.1";
  };
  # Reached only through Caddy; 5055 stays closed in the firewall.
  services.seerr.enable = true;

  systemd.services.sonarr = shareSandbox;
  # Radarr's module makes its data folder with tmpfiles, not StateDirectory,
  # so strict ProtectSystem needs it listed.
  systemd.services.radarr = lib.mkMerge [
    shareSandbox
    { serviceConfig.ReadWritePaths = [ config.services.radarr.dataDir ]; }
  ];

  fox.server.privateSites = {
    request.upstream = "127.0.0.1:5055";
    tv.upstream = "127.0.0.1:8989";
    movies.upstream = "127.0.0.1:7878";
    indexers.upstream = "127.0.0.1:9696";
  };
}
