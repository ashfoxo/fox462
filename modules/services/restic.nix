# restic.nix
#
# Daily encrypted backups of irreplaceable state to a Scaleway Object Storage
# bucket (S3-compatible, Paris region).
#
# Needs these keys in secrets.yaml (edited via sops), where <prefix> is the
# host's fox.backup.s3SecretPrefix (e.g. "fox-blue-"):
#   restic-password                - repository encryption password, shared by
#                                    every host (also kept in Bitwarden)
#   <prefix>s3-access-key-id       - that host's Scaleway API access key
#   <prefix>s3-secret-access-key   - that host's Scaleway API secret key
# Per-host settings are in modules/options.nix.
{ config, pkgs, lib, ... }:

let
  cfg = config.fox.backup;
  keyId = "${cfg.s3SecretPrefix}s3-access-key-id";
  secretKey = "${cfg.s3SecretPrefix}s3-secret-access-key";
in
lib.mkIf cfg.enable {
  # ---------------------------------------------------------------------------
  # Secrets
  # ---------------------------------------------------------------------------
  # Declares each secret so sops-nix decrypts it at boot into /run/secrets/.
  # The names must match the keys in secrets.yaml exactly.
  sops.secrets.restic-password = { };
  sops.secrets.${keyId} = { };
  sops.secrets.${secretKey} = { };

  # Builds a small environment file at boot from the decrypted secrets above.
  # This keeps the credentials out of the Nix store, which is world-readable.
  #
  # The variable names below are what restic's S3 backend looks for. The "AWS_"
  # prefix is just the standard S3 naming convention, and these values are
  # your Scaleway keys, not Amazon credentials.
  sops.templates."restic-s3-env".content = ''
    AWS_ACCESS_KEY_ID=${config.sops.placeholder.${keyId}}
    AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.${secretKey}}
    AWS_DEFAULT_REGION=fr-par
  '';

  # ---------------------------------------------------------------------------
  # Backup job
  # ---------------------------------------------------------------------------
  # Creates the systemd service "restic-backups-s3" and a matching timer, plus
  # a wrapper command "restic-s3" that is pre-configured for this repository
  # (use it for manual commands like `sudo restic-s3 snapshots`).
  services.restic.backups.s3 = {
    # Create the repository on first run if it doesn't exist yet.
    initialize = true;

    # Path-style URL: endpoint, then bucket, then a folder inside the bucket
    # named after the host. Set per host (fox.backup.repository).
    repository = cfg.repository;

    # Repository password and Scaleway credentials, from the sops secrets above.
    passwordFile = config.sops.secrets.restic-password.path;
    environmentFile = config.sops.templates."restic-s3-env".path;

    # /persist holds system state that survives reboots (impermanence).
    # /home/arlo is in RAM (ephemeral-home.nix); what survives is in
    # /persist/home/arlo.
    paths = [ "/persist" ];

    # Things that can be redownloaded or regenerated, so they aren't worth
    # paying to store. This is a starting guess; trim it after checking
    # `du` output on /persist.
    exclude = [
      "**/.cache"                      # app and tool caches
      "**/.local/share/Steam"          # Steam client data
      "**/steamapps"                   # Steam games (redownloadable)
      "**/node_modules"                # JS dependencies
      "**/target"                      # Rust build output
      "**/.direnv"                     # per-project dev environments
      "**/result"                      # nix build output symlinks
      "/persist/nix"                   # Nix store (rebuilt from the flake)
      "/persist/home/arlo/media"               # media library
      "/persist/home/arlo/torrents"            # torrent downloads (qBittorrent)
      "/persist/home/arlo/.local/share/Trash"  # deleted files
    ] ++ cfg.extraExclude;

    # Also skip any directory containing a CACHEDIR.TAG file, which is the
    # standard way for programs to mark a folder as disposable.
    extraBackupArgs = [ "--exclude-caches" ];

    # When to run. "daily" fires once a day; Persistent=true makes it run at
    # next boot if the machine was off at the scheduled time; the random delay
    # spreads the start time by up to an hour.
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "1h";
    };

    # Retention: after each backup, old snapshots are pruned, keeping the
    # newest 7 daily, 4 weekly, 6 monthly, and 1 yearly snapshot.
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 6"
      "--keep-yearly 1"
    ];
  };

  # ---------------------------------------------------------------------------
  # Retry and network behavior
  # ---------------------------------------------------------------------------
  # Wait for the network before starting, and retry if the run fails
  # (for example, Wi-Fi not connected yet after boot).
  systemd.services.restic-backups-s3 = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "10min";

      # Stamp the time of each successful run, for the lock screen's backup
      # chip (lockscreen.nix). ExecStartPost only runs if backup and prune
      # both succeeded. /var/lib/restic-status is persisted in
      # modules/impermanence.nix, so the stamp survives the root wipe at boot.
      StateDirectory = "restic-status";
      StateDirectoryMode = "0755";
      ExecStartPost = "${pkgs.coreutils}/bin/touch /var/lib/restic-status/last-success";
    };
    unitConfig = {
      StartLimitIntervalSec = "6h";
      StartLimitBurst = 5;
    };
  };
}