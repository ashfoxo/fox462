# Notesnook sync server: private note sync over NetBird.
#
# Upstream is streetwriters/notesnook-sync-server (a docker-compose file); this
# is the same set of containers under Podman, like the music stack:
#
#   notesnook-db      MongoDB, as a one-node replica set (the sync server needs one)
#   notesnook-s3      Silo (a MinIO fork), where encrypted attachments are kept
#   identity-server   accounts and login
#   notesnook-server  the sync API
#   sse-server        live-sync events
#
# Left out on purpose: autoheal (needs the Docker socket; systemd restarts
# failed containers), Monograph (public note pages, pointless on a private
# server), and upstream's optional themes, CORS proxy and inbox services.
#
# Everything listens on 127.0.0.1 and Caddy publishes it on the private domain,
# so it answers NetBird peers only:
#
#   notes.<privateDomain>          sync server (the main address)
#   auth.notes.<privateDomain>     accounts and login
#   events.notes.<privateDomain>   live-sync events
#   files.notes.<privateDomain>    attachments
#
# The app's Settings -> Server settings take these four. The names under
# notes. need their own wildcard certificate (see caddy.nix).
#
# Mail (sign-up confirmation, email 2FA, password reset) goes out through
# Purelymail's SMTP on port 587; Hetzner blocks outbound 25 and 465.
{ config, pkgs, lib, inputs, srv, ... }:
let
  inherit (srv) notify podman;
  host = config.networking.hostName;
  priv = config.fox.server.privateDomain;
  # The sync server is notes.<priv>; the rest sit one level down, under notes.
  url = name: if name == "sync" then "https://notes.${priv}" else "https://${name}.notes.${priv}";

  # Create the first account with this "false", then switch it to "true" and
  # deploy again: the instance then accepts no new accounts.
  disableSignups = "true";

  # Mongo and the S3 pair are pinned, as upstream pins them: a Mongo major bump
  # needs a dump and restore, never an in-place pull. The streetwriters images
  # follow :latest and are updated weekly by notesnook-update below.
  images = {
    mongo = "docker.io/library/mongo:7.0.12";
    silo = "docker.io/pgsty/silo:RELEASE.2026-09-16T00-00-00Z";
    mc = "docker.io/pgsty/mc:RELEASE.2026-09-13T00-00-00Z";
  };

  # What the three .NET services use to find each other (by container name, on
  # the notesnook network) plus the public addresses clients use.
  common = {
    SELF_HOSTED = "1";
    NOTESNOOK_SERVER_HOST = "notesnook-server";
    NOTESNOOK_SERVER_PORT = "5264";
    IDENTITY_SERVER_HOST = "identity-server";
    IDENTITY_SERVER_PORT = "8264";
    SSE_SERVER_HOST = "sse-server";
    SSE_SERVER_PORT = "7264";
    IDENTITY_SERVER_URL = url "auth";
    NOTESNOOK_APP_HOST = "https://app.notesnook.com";

    INSTANCE_NAME = "${host}-notesnook";
    DISABLE_SIGNUPS = disableSignups;
    NOTESNOOK_APP_PUBLIC_URL = "https://app.notesnook.com";
    AUTH_SERVER_PUBLIC_URL = url "auth";
    NOTESNOOK_API_PUBLIC_URL = url "sync";
    ATTACHMENTS_SERVER_PUBLIC_URL = url "files";
    MONOGRAPH_PUBLIC_URL = "https://monogr.ph";   # not run here; upstream wants it set

    # Mail goes out as the SMTP user (NOTESNOOK_SENDER_EMAIL defaults to it).
    # The login itself is in notesnook.env.
    SMTP_HOST = "smtp.purelymail.com";
    SMTP_PORT = "587";
  };

  secrets = [ "/run/secrets/notesnook.env" ];
  net = "--network=notesnook";
  hardening = "--security-opt=no-new-privileges";

  # Each unit waits for the network and, for the three apps, for MongoDB's
  # replica set to exist. oci-containers units don't know about either.
  needsNet = {
    after = [ "podman-network-notesnook.service" ];
    requires = [ "podman-network-notesnook.service" ];
  };
  needsMongo = needsNet // {
    after = [ "podman-network-notesnook.service" "notesnook-mongo-init.service" ];
    requires = [ "podman-network-notesnook.service" "notesnook-mongo-init.service" ];
  };
in
{
  # notesnook.env, one KEY=value per line:
  #   NOTESNOOK_API_SECRET  random, 32+ characters: signs and checks login tokens.
  #                         Changing it logs every device out.
  #   MINIO_ROOT_USER       Silo's account, more than 3 characters
  #   MINIO_ROOT_PASSWORD   more than 8 characters
  #   S3_ACCESS_KEY_ID      the same value as MINIO_ROOT_USER
  #   S3_ACCESS_KEY         the same value as MINIO_ROOT_PASSWORD
  #   SMTP_USERNAME         the Purelymail mailbox, e.g. name@purelymail.com. Mail
  #                         is sent from this address.
  #   SMTP_PASSWORD         that mailbox's password. (Purelymail's API key is for
  #                         their management API and is not used for SMTP.)
  # (upstream's compose file derives the last two from the first two; here
  # they are written out, so nothing needs templating.)
  fox.server.secretNames = [ "notesnook.env" ];

  # One site per address the app asks for. "notes" is covered by the
  # *.<privateDomain> wildcard; the names under notes. by *.notes.<privateDomain>.
  fox.server.privateSites = {
    notes.upstream = "127.0.0.1:5264";
    "auth.notes".upstream = "127.0.0.1:8264";
    "events.notes".upstream = "127.0.0.1:7264";
    "files.notes".upstream = "127.0.0.1:9000";
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/notesnook 0700 root root -"
    "d /var/backup/notesnook 0700 root root -"
  ];

  virtualisation.oci-containers.containers = {

    # Capped, because MongoDB otherwise sizes its cache to half the machine's
    # memory and this box also runs AudioMuse.
    notesnook-db = {
      image = images.mongo;
      cmd = [ "--replSet" "rs0" "--bind_ip_all" "--wiredTigerCacheSizeGB" "0.5" ];
      volumes = [ "/var/lib/notesnook/mongo:/data/db" ];
      extraOptions = [ net hardening "--memory=1g" ];
    };

    notesnook-s3 = {
      image = images.silo;
      cmd = [ "server" "/data/s3" "--console-address" ":9090" ];
      ports = [ "127.0.0.1:9000:9000" ];
      environmentFiles = secrets;
      environment.MINIO_BROWSER = "off";
      volumes = [ "/var/lib/notesnook/s3:/data/s3" ];
      extraOptions = [ net hardening ];
    };

    identity-server = {
      image = "docker.io/streetwriters/identity:latest";
      ports = [ "127.0.0.1:8264:8264" ];
      environmentFiles = secrets;
      environment = common // {
        MONGODB_CONNECTION_STRING = "mongodb://notesnook-db:27017/identity?replSet=rs0";
        MONGODB_DATABASE_NAME = "identity";
      };
      extraOptions = [ net hardening ];
    };

    notesnook-server = {
      image = "docker.io/streetwriters/notesnook-sync:latest";
      ports = [ "127.0.0.1:5264:5264" ];
      dependsOn = [ "notesnook-s3" "identity-server" ];
      environmentFiles = secrets;
      environment = common // {
        MONGODB_CONNECTION_STRING = "mongodb://notesnook-db:27017/?replSet=rs0";
        MONGODB_DATABASE_NAME = "notesnook";
        S3_INTERNAL_SERVICE_URL = "http://notesnook-s3:9000";
        S3_INTERNAL_BUCKET_NAME = "attachments";
        S3_SERVICE_URL = url "files";
        S3_REGION = "us-east-1";
        S3_BUCKET_NAME = "attachments";
      };
      extraOptions = [ net hardening ];
    };

    sse-server = {
      image = "docker.io/streetwriters/sse:latest";
      ports = [ "127.0.0.1:7264:7264" ];
      dependsOn = [ "identity-server" "notesnook-server" ];
      environmentFiles = secrets;
      environment = common;
      extraOptions = [ net hardening ];
    };

  };

  systemd.services = {

    # Named network, so the containers find each other by name.
    podman-network-notesnook = {
      description = "Create the notesnook podman network";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      script = ''
        ${podman} network inspect notesnook >/dev/null 2>&1 \
          || ${podman} network create notesnook
      '';
    };

    # Bind-mount sources are made here, not by tmpfiles: a tmpfiles rule would
    # chown MongoDB's directory back to root on every boot, undoing the owner
    # its entrypoint set.
    podman-notesnook-db = needsNet // { preStart = "mkdir -p /var/lib/notesnook/mongo"; };
    podman-notesnook-s3 = needsNet // { preStart = "mkdir -p /var/lib/notesnook/s3"; };
    podman-identity-server = needsMongo;
    podman-sse-server = needsMongo;
    podman-notesnook-server = needsMongo // {
      after = needsMongo.after ++ [ "notesnook-bucket.service" ];
      requires = needsMongo.requires ++ [ "notesnook-bucket.service" ];
    };

    # MongoDB must be a replica set before the apps connect. Initiating it is a
    # no-op once done (the state lives in the data directory), so this runs
    # safely on every boot. It retries while Mongo is still starting.
    notesnook-mongo-init = {
      description = "Initiate the Notesnook MongoDB replica set";
      wantedBy = [ "multi-user.target" ];
      after = [ "podman-notesnook-db.service" ];
      requires = [ "podman-notesnook-db.service" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      script = ''
        for i in $(seq 1 60); do
          if ${podman} exec notesnook-db mongosh --quiet --eval \
               'try { rs.status().ok } catch (e) { rs.initiate({_id: "rs0", members: [{_id: 0, host: "notesnook-db:27017"}]}).ok }' \
               >/dev/null 2>&1; then
            exit 0
          fi
          sleep 2
        done
        echo "MongoDB did not accept the replica set" >&2
        exit 1
      '';
    };

    # The attachments bucket, made once Silo is up (upstream's setup-s3). Making
    # it again is harmless (mc mb -p).
    notesnook-bucket = {
      description = "Create the Notesnook attachments bucket";
      wantedBy = [ "multi-user.target" ];
      after = [ "podman-notesnook-s3.service" ];
      requires = [ "podman-notesnook-s3.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        EnvironmentFile = "/run/secrets/notesnook.env";
      };
      script = ''
        for i in $(seq 1 60); do
          if ${podman} run --rm --network=notesnook --entrypoint /bin/bash \
               -e MINIO_ROOT_USER -e MINIO_ROOT_PASSWORD ${images.mc} -c \
               'mc alias set silo http://notesnook-s3:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" && mc mb silo/attachments -p' \
               >/dev/null 2>&1; then
            exit 0
          fi
          sleep 2
        done
        echo "could not create the attachments bucket" >&2
        exit 1
      '';
    };

    # The three streetwriters images follow :latest, and a :latest tag never
    # re-pulls on its own. Pull them weekly, and restart only if one moved.
    notesnook-update = {
      description = "Update the Notesnook server images";
      path = [ pkgs.coreutils pkgs.systemd ];
      serviceConfig.Type = "oneshot";
      onFailure = [ "notify-notesnook-update-failed.service" ];
      script = ''
        set -uo pipefail
        changed=0
        failed=0
        for c in identity-server notesnook-server sse-server; do
          img=$(${podman} inspect --format '{{.ImageName}}' "$c" 2>/dev/null) || continue
          before=$(${podman} image inspect --format '{{.Id}}' "$img" 2>/dev/null || echo none)
          if ! ${podman} pull -q "$img" >/dev/null; then
            echo "pull failed: $img" >&2
            failed=1
            continue
          fi
          after=$(${podman} image inspect --format '{{.Id}}' "$img" 2>/dev/null || echo none)
          [ "$before" != "$after" ] && changed=1
        done
        if [ "$changed" = 1 ]; then
          echo "Notesnook images changed, restarting"
          systemctl restart podman-identity-server.service podman-notesnook-server.service podman-sse-server.service
        else
          echo "Notesnook images unchanged"
        fi
        exit $failed
      '';
    };

    notify-notesnook-update-failed = {
      description = "Push an ntfy alert when the Notesnook update fails";
      serviceConfig.Type = "oneshot";
      script = ''
        ${notify} "${host}: Notesnook update FAILED" \
          "notesnook-update failed. journalctl -u notesnook-update" \
          high
      '';
    };

  };

  # Sunday 06:30 UTC, after the 06:00 music update.
  systemd.timers.notesnook-update = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 06:30";
      RandomizedDelaySec = "20m";
      Persistent = true;
    };
  };

  fox.server.backup = {
    # Accounts and notes live in MongoDB, dumped (not copied live) before each
    # backup. Attachments are already encrypted by the app; back up Silo's
    # folder as it is. A failed dump is loud, because the previous one would
    # otherwise be archived again behind a green heartbeat.
    paths = [ "/var/backup/notesnook" "/var/lib/notesnook/s3" ];
    prepare = ''
      if ${podman} exec notesnook-db mongodump --quiet --archive \
           > /var/backup/notesnook/notesnook.archive.tmp ; then
        mv /var/backup/notesnook/notesnook.archive.tmp /var/backup/notesnook/notesnook.archive
      else
        rm -f /var/backup/notesnook/notesnook.archive.tmp
        ${notify} "${host}: notesnook mongodump failed" \
          "Could not dump the Notesnook database. Tonight's backup carries the previous dump, or none at all." \
          high
      fi
    '';
  };
}
