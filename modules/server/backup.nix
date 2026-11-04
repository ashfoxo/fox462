# Nightly restic backup and its monthly integrity check.
{ config, pkgs, lib, inputs, srv, ... }:
let
  inherit (srv) notify;
  cfg = config.fox.server.backup;
  host = config.networking.hostName;
in
{
  fox.server.secretNames = [ "restic-password" "restic-s3-env" "kuma-push-url" ];
  systemd.tmpfiles.rules = [ "d /var/backup/sqlite 0700 root root -" ];

  # The repository is fox.server.backup.repository, one bucket per host.
  # Versioning is on, so a plain delete from these credentials leaves a delete
  # marker rather than destroying data, and the key is limited to its bucket.
  #
  # What goes in comes from the services: each adds its own state to
  # fox.server.backup.paths, and its databases to .sqlite or .prepare.
  #
  # Secrets (see secret.sh):
  #   restic-password  long random passphrase, also kept off this box
  #   restic-s3-env    AWS_ACCESS_KEY_ID= / AWS_SECRET_ACCESS_KEY= for the bucket
  #   kuma-push-url    full Uptime Kuma push URL, no query string
  services.restic.backups.offsite = {
    repository = cfg.repository;
    passwordFile = "/run/secrets/restic-password";
    environmentFile = "/run/secrets/restic-s3-env";
    initialize = true;

    # Consistent database snapshots. Copying a live database file can produce
    # a torn file that only fails at restore time, so each one is dumped
    # instead of being copied underneath.
    #
    # A failed dump is non-fatal but loud. The previous dump stays on disk and
    # gets archived again, so a silent failure would mean shipping a stale
    # copy behind a green heartbeat.
    backupPrepareCommand = cfg.prepare + ''
      for db in ${lib.concatStringsSep " " cfg.sqlite} ; do
        [ -f "$db" ] || continue
        if ! ${pkgs.sqlite}/bin/sqlite3 "$db" \
             ".backup '/var/backup/sqlite/$(basename "$db")'" ; then
          ${notify} "${host}: sqlite dump failed" \
            "Could not snapshot $db. The copy in tonight's backup is stale." \
            urgent
        fi
      done
      exit 0
    '';

    # This is ExecStopPost, which systemd runs on failure too, so the result
    # guard prevents a false "up" ping. The trailing exit 0 keeps an
    # unreachable Kuma from marking a successful backup as failed; a missing
    # heartbeat is already what the 26h push monitor alerts on.
    backupCleanupCommand = ''
      [ "$SERVICE_RESULT" = success ] || exit 0
      url=$(cat /run/secrets/kuma-push-url 2>/dev/null) || exit 0
      [ -n "$url" ] || exit 0
      ${pkgs.curl}/bin/curl -fsS -m 10 --retry 3 \
        "$url?status=up&msg=OK" \
        || echo "heartbeat push failed" >&2
      exit 0
    '';

    paths = cfg.paths ++ [
      "/var/backup/sqlite"
      # The config as last deployed (deploy.sh copies it here), secrets still
      # encrypted. A copy that does not depend on the workstation or Codeberg.
      "/home/arlo/${host}"
    ];
    exclude = cfg.exclude;
    # Moved earlier so the worst-case start (01:50) leaves over an hour before
    # the 03:00 upgrade window. The old 02:00 + 30m jitter was one slow run
    # away from an unattended reboot landing mid-prune.
    timerConfig = {
      OnCalendar = "*-*-* 01:30:00";
      RandomizedDelaySec = "20m";
      Persistent = true;
    };
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 6"
    ];
  };

  systemd.services.restic-backups-offsite.onFailure = [ "notify-backup-failed.service" ];

  systemd.services.notify-backup-failed = {
    description = "Push an ntfy alert when the offsite backup fails";
    serviceConfig.Type = "oneshot";
    script = ''
      ${notify} "${host}: backup FAILED" \
        "restic-backups-offsite failed. journalctl -u restic-backups-offsite" \
        urgent
    '';
  };

  # Monthly integrity check. Plain `restic check` validates the repository
  # structure and indexes; --read-data-subset additionally downloads a sample
  # of the pack files and verifies their contents, which is the only thing that
  # proves the bytes sitting in the bucket are still readable. A backup that
  # has never been read back is a hypothesis, not a backup.
  #
  # The percentage form scales with the repository, so this stays proportionate
  # as it grows. At the current ~460 MiB that is roughly 25 MiB of egress per
  # run; raise the percentage while the repo is still small if you want fuller
  # coverage.
  #
  # 1st of the month at 07:00 is clear of the 01:30 backup, the 03:00-05:00
  # upgrade window, and the Sunday 06:00 image pulls.
  systemd.services.restic-check-offsite = {
    description = "Verify the offsite restic repository";
    # Repository and credentials are read back out of the backup job above
    # rather than repeated here, so the two cannot drift apart.
    environment = {
      RESTIC_REPOSITORY = config.services.restic.backups.offsite.repository;
      RESTIC_PASSWORD_FILE = config.services.restic.backups.offsite.passwordFile;
    };
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = config.services.restic.backups.offsite.environmentFile;
    };
    onFailure = [ "notify-check-failed.service" ];
    # Deliberately no `|| true` and no exit 0. Unlike the alerting path in
    # notify above, this unit failing IS the signal.
    script = ''
      ${pkgs.restic}/bin/restic check --read-data-subset=5%
    '';
  };

  systemd.timers.restic-check-offsite = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-01 07:00:00";
      RandomizedDelaySec = "30m";
      Persistent = true;
    };
  };

  systemd.services.notify-check-failed = {
    description = "Push an ntfy alert when the repository check fails";
    serviceConfig.Type = "oneshot";
    script = ''
      ${notify} "${host}: repo check FAILED" \
        "restic check found a problem offsite. journalctl -u restic-check-offsite" \
        urgent
    '';
  };
}
