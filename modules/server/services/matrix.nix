# Matrix as one inbox: continuwuity (homeserver) plus Telegram, Discord (DMs)
# and Instagram bridges. Private (matrix.<privateDomain>), one user, no
# federation. Setup steps are in hosts/fox-red/README.md, "Matrix".
{ config, pkgs, srv, ... }:
let
  inherit (srv) notify;
  priv = config.fox.server.privateDomain;
  me = "@arlo:${priv}";
  hs = "http://127.0.0.1:6167";
  # Each bridge logs in as you through the "doublepuppet" appservice, so what
  # you send from the Telegram/Discord/Instagram apps shows up as you.
  doublePuppet = { ${priv} = "as_token:$DOUBLE_PUPPET_AS_TOKEN"; };
  env = "/run/secrets/matrix-bridges.env";
in
{
  # matrix-bridges.env      DOUBLE_PUPPET_AS_TOKEN= (the as_token of the
  #                         doublepuppet registration), and
  #                         MAUTRIX_TELEGRAM_TELEGRAM_API_ID= /
  #                         MAUTRIX_TELEGRAM_TELEGRAM_API_HASH= from my.telegram.org
  fox.server.secretNames = [ "matrix-bridges.env" ];

  services.matrix-continuwuity = {
    enable = true;
    # The plain package (0.5.10) is marked insecure (SEC8); the fix is 26.x.
    package = pkgs.matrix-continuwuity_latest;
    settings.global = {
      server_name = priv;            # permanent: it is in every user and room ID
      address = [ "127.0.0.1" ];
      allow_federation = false;
      trusted_servers = [ ];         # no key lookups at matrix.org either
      allow_registration = false;    # the first account uses the one-time token in the log
      allow_announcements_check = false;
      max_request_size = 104857600;  # 100 MiB: Telegram videos are often past the 20 MB default
      well_known.client = "https://matrix.${priv}";
    };
  };

  fox.server.privateSites.matrix.upstream = "127.0.0.1:6167";

  # Media goes in the music share's matrix/ folder, mounted a second time so
  # continuwuity owns it here. shortcut: it's also readable through /mnt/music
  # (0664, any local user); a separate sub-account would fix that.
  fileSystems."/mnt/matrix-media" = {
    device = "//u650931-sub1.your-storagebox.de/u650931-sub1/matrix";
    fsType = "cifs";
    options = [
      "credentials=/run/secrets/storagebox-creds"
      "vers=3.1.1"
      "seal"
      "uid=continuwuity"
      "gid=continuwuity"
      "file_mode=0600"
      "dir_mode=0700"
      "_netdev"
      "nofail"
    ];
  };

  systemd.services.continuwuity = {
    # Never start without the share, or media would quietly fill the VPS disk.
    # A missing mount leaves this unit failed, which the health check reports.
    unitConfig = {
      AssertPathIsMountPoint = "/mnt/matrix-media";
      RequiresMountsFor = "/mnt/matrix-media";
    };
    serviceConfig = {
      BindPaths = [ "/mnt/matrix-media:/var/lib/continuwuity/media" ];
      MemoryMax = "1G";
    };
  };

  services.mautrix-telegram = {
    enable = true;
    # No end-to-bridge encryption here, so no libolm (marked insecure).
    package = pkgs.mautrix-telegram.override { withE2BE = false; };
    environmentFile = env;
    serviceDependencies = [ "continuwuity.service" ];
    settings = {
      homeserver = { address = hs; domain = priv; };
      appservice = {
        # The default is 0.0.0.0:8080, which is Miniflux's port.
        hostname = "127.0.0.1";
        port = 29317;
        address = "http://127.0.0.1:29317";
      };
      bridge = {
        # "*" can't be removed from the module default; relaybot with no bot
        # token does nothing, and there are no other users anyway.
        permissions = { "*" = "relaybot"; ${me} = "admin"; };
        login_shared_secret_map = doublePuppet;
        sync_direct_chats = true;    # existing DMs come in at login, not just groups
      };
    };
  };
  systemd.services.mautrix-telegram.serviceConfig.MemoryMax = "512M";

  # Legacy bridge: settings replace the module's defaults section by section,
  # and the bridge fills anything left out from its own example config.
  services.mautrix-discord = {
    enable = true;
    # Built without encryption support, so no libolm (marked insecure).
    package = pkgs.mautrix-discord.overrideAttrs { buildInputs = [ ]; tags = [ "nocrypto" ]; };
    environmentFile = env;
    serviceDependencies = [ "mautrix-discord-registration.service" "continuwuity.service" ];
    settings = {
      homeserver = { address = hs; domain = priv; };
      appservice = {
        hostname = "127.0.0.1";
        port = 29334;
        address = "http://127.0.0.1:29334";
        id = "discord";
        bot = { username = "discordbot"; displayname = "Discord bridge bot"; };
        database = {
          type = "sqlite3";
          uri = "file:/var/lib/mautrix-discord/mautrix-discord.db?_txlock=immediate";
        };
      };
      bridge = {
        permissions = { ${me} = "admin"; };
        login_shared_secret_map = doublePuppet;
        # DMs only: servers stay unbridged unless you run `guilds bridge`.
        startup_private_channel_create_limit = 25;
        backfill.forward_limits = {
          initial = { dm = 50; channel = 0; thread = 0; };
          missed = { dm = 100; channel = 0; thread = 0; };
        };
      };
    };
  };
  systemd.services.mautrix-discord.serviceConfig.MemoryMax = "512M";

  # One instance holds both Instagram accounts (log in twice).
  services.mautrix-meta.package = pkgs.mautrix-meta.override { withGoolm = true; };
  services.mautrix-meta.instances.instagram = {
    enable = true;
    registerToSynapse = false;       # true would define a half-empty matrix-synapse unit
    environmentFile = env;
    serviceDependencies = [ "mautrix-meta-instagram-registration.service" "continuwuity.service" ];
    settings = {
      homeserver = { address = hs; domain = priv; };
      bridge.permissions = { ${me} = "admin"; };
      double_puppet.secrets = doublePuppet;
      # The module requires end-to-bridge encryption by default. Skipped: its
      # keys would sit on this same box, and NetBird already encrypts the hop.
      encryption = { allow = false; default = false; require = false; };
    };
  };
  systemd.services.mautrix-meta-instagram.serviceConfig.MemoryMax = "512M";

  fox.server.monitoring.watchUnits = [ "continuwuity.service" "mautrix-*.service" ];

  # The bridge folders hold your logged-in sessions: treat this backup like
  # credentials. Their SQLite databases are snapshotted instead of copied live.
  # continuwuity's RocksDB can't be copied live either, so it is stopped for
  # the few seconds the copy takes (bridges retry anything sent meanwhile).
  # Media isn't in the copy: the bind mount only exists inside the service.
  systemd.tmpfiles.rules = [ "d /var/backup/continuwuity 0700 root root -" ];
  fox.server.backup = {
    paths = [
      "/var/backup/continuwuity"
      "/var/lib/mautrix-telegram"
      "/var/lib/mautrix-discord"
      "/var/lib/mautrix-meta-instagram"
    ];
    exclude = [ "/var/lib/mautrix-*/*.db" "/var/lib/mautrix-*/*.db-*" ];
    sqlite = [
      "/var/lib/mautrix-telegram/mautrix-telegram.db"
      "/var/lib/mautrix-discord/mautrix-discord.db"
      "/var/lib/mautrix-meta-instagram/mautrix-meta.db"
    ];
    prepare = ''
      if [ -d /var/lib/private/continuwuity ]; then
        ${pkgs.systemd}/bin/systemctl stop continuwuity
        ${pkgs.rsync}/bin/rsync -a --delete /var/lib/private/continuwuity/ /var/backup/continuwuity/ \
          || ${notify} "${config.networking.hostName}: matrix copy failed" \
               "Could not copy continuwuity's database. Tonight's backup carries the previous copy." high
        ${pkgs.systemd}/bin/systemctl start continuwuity
      fi
    '';
  };
}
