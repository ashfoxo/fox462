# The music stack: Navidrome, AudioMuse, and the jobs that keep them in step.
{ config, pkgs, srv, ... }:
let
  inherit (srv) notify podman;
  # Shared by AudioMuse's web app and worker. Secrets come from audiomuse.env.
  audiomuseEnv = {
    MEDIASERVER_TYPE = "navidrome";
    NAVIDROME_URL = "http://navidrome:4533";
    POSTGRES_USER = "audiomuse";
    POSTGRES_DB = "audiomusedb";
    POSTGRES_HOST = "audiomuse-db";
    POSTGRES_PORT = "5432";
    TEMP_DIR = "/app/temp_audio";
    TZ = "UTC";
    # Similar songs comes from the main audio fingerprint index. CLAP
    # (search by text description) and lyrics transcription are separate,
    # heavy passes over every track, and neither is wanted here.
    CLAP_ENABLED = "false";
    LYRICS_ENABLED = "false";
  };
in
{
  # storagebox-creds   username= / password= for the CIFS mount
  # navidrome.env      ND_PASSWORDENCRYPTIONKEY=. Must never change; a copy
  #                    lives in Bitwarden.
  # navidrome-api.env  ND_USER= / ND_PASSWORD= for an admin account. Used by
  #                    music-ingest to trigger a library scan over the Subsonic
  #                    API. Must be an admin: startScan is admin-only.
  # audiomuse.env      POSTGRES_PASSWORD= for AudioMuse's own database,
  #                    AUDIOMUSE_USER= / AUDIOMUSE_PASSWORD= for its web login,
  #                    API_TOKEN= for the Navidrome plugin and the nightly
  #                    check, JWT_SECRET= so logins survive restarts, and
  #                    NAVIDROME_USER= / NAVIDROME_PASSWORD= for the non-admin
  #                    Navidrome account it reads the library through.
  fox.server.secretNames = [
    "storagebox-creds"
    "navidrome.env"
    "navidrome-api.env"
    "audiomuse.env"
  ];

  # Navidrome's own password is the entire gate here: the Subsonic API answers
  # bad credentials with HTTP 200, so no jail could watch it. NetBird is the
  # first gate. AudioMuse's own login is still in front of everything on muse.
  fox.server.privateSites = {
    music.upstream = "127.0.0.1:4533";
    muse.upstream = "127.0.0.1:8000";
  };

  systemd.tmpfiles.rules = [
    "d /var/backup/audiomuse 0700 root root -"
    # AudioMuse's bind-mount sources are made by mkdir in the units below,
    # not here: a tmpfiles rule would chown the postgres directory back to
    # root on every boot, undoing the owner its entrypoint set.
    "d /var/lib/audiomuse 0700 root root -"
    "d /var/lib/navidrome/plugins 0755 root root -"
  ];

  fox.server.backup = {
    paths = [ "/var/lib/navidrome" "/var/backup/audiomuse" ];
    exclude = [ "/var/lib/navidrome/cache" ];
    sqlite = [ "/var/lib/navidrome/navidrome.db" ];
    # AudioMuse's analysis results. Losing them only costs a re-analysis, but
    # that is hours of CPU, so they are dumped like the others.
    #
    # A failed dump is non-fatal but loud. The previous dump stays on disk and
    # gets archived again, so a silent failure would mean shipping a stale
    # copy behind a green heartbeat.
    prepare = ''
      if ${podman} exec audiomuse-db \
           pg_dump -U audiomuse -d audiomusedb \
           > /var/backup/audiomuse/audiomuse.sql.tmp ; then
        mv /var/backup/audiomuse/audiomuse.sql.tmp /var/backup/audiomuse/audiomuse.sql
      else
        rm -f /var/backup/audiomuse/audiomuse.sql.tmp
        ${notify} "${config.networking.hostName}: audiomuse pg_dump failed" \
          "Could not dump the AudioMuse database. Tonight's backup carries the previous dump, or none at all." \
          high
      fi
    '';
  };

  users.groups.navidrome = { };
  users.users.navidrome = {
    isSystemUser = true;
    group = "navidrome";
  };


  # This box is infrastructure, not backup: it holds only music, which is
  # replaceable. seal is here because the Storage Box is reached across the
  # public internet on 445, and vers=3.1.1 alone signs the session without
  # encrypting the payload.
  fileSystems."/mnt/music" = {
    device = "//u650931-sub1.your-storagebox.de/u650931-sub1";
    fsType = "cifs";
    options = [
      "credentials=/run/secrets/storagebox-creds"
      "vers=3.1.1"
      "seal"
      "cache=loose"
      "uid=navidrome"
      "gid=navidrome"
      "file_mode=0644"
      "dir_mode=0755"
      "_netdev"
      "nofail"
    ];
  };

  # Stops Navidrome scanning an empty directory and wiping its library if the
  # CIFS mount is missing. Systemd does not retry assert failures, which is
  # what the navidrome-mount-retry timer below exists to handle.
  #
  # RequiresMountsFor makes Navidrome wait for the mount and start the moment
  # it is ready, instead of failing the assert and waiting for the retry timer.
  systemd.services.podman-navidrome = {
    after = [ "remote-fs.target" "podman-network-music.service" ];
    requires = [ "podman-network-music.service" ];
    unitConfig = {
      AssertPathIsMountPoint = "/mnt/music";
      RequiresMountsFor = "/mnt/music";
    };
  };


  virtualisation.oci-containers.containers = {

      navidrome = {
        image = "docker.io/deluan/navidrome:latest";
        ports = [ "127.0.0.1:4533:4533" ];
        # Entrypoint chowns /data and drops privileges, so it needs these back.
        # On the music network so the AudioMuse plugin can reach
        # http://audiomuse-flask:8000, and AudioMuse can reach it back.
        extraOptions = [
          "--network=music"
          "--security-opt=no-new-privileges"
          "--cap-drop=ALL"
          "--cap-add=CHOWN"
          "--cap-add=DAC_OVERRIDE"
          "--cap-add=SETUID"
          "--cap-add=SETGID"
        ];
        # ND_PASSWORDENCRYPTIONKEY. The Subsonic API requires recoverable
        # passwords, so Navidrome encrypts rather than hashes them, and the
        # default key is in its source. This makes a stolen navidrome.db
        # useless on its own.
        #
        # ONE-TIME ONLY. Navidrome re-encrypts every password on the first
        # start after this is set, and changing it afterwards locks every
        # account out permanently. A copy lives in Bitwarden.
        environmentFiles = [ "/run/secrets/navidrome.env" ];
        environment = {
          ND_SCANSCHEDULE = "1h";
          ND_LOGLEVEL = "info";
          ND_SESSIONTIMEOUT = "24h";
          ND_BASEURL = "";
          ND_ENABLETRANSCODING = "true";
          ND_TRANSCODINGCACHESIZE = "1GB";
          ND_ENABLEINSIGHTS = "false";

          # The AudioMuse plugin, /var/lib/navidrome/plugins/audiomuseai.ndp,
          # kept current by music-stack-update. Its URL and API token are set
          # once in Navidrome's web UI and stored in navidrome.db. AudioMuse
          # comes first so it answers similar songs and similar artists;
          # Last.fm and Deezer still supply bios and artist pictures, and
          # step in if the plugin breaks (the nightly check notices that).
          ND_PLUGINS_ENABLED = "true";
          ND_PLUGINS_AUTORELOAD = "true";
          ND_AGENTS = "audiomuseai,lastfm,deezer";
        };
        volumes = [
          "/var/lib/navidrome:/data"
          "/mnt/music/library:/music:ro,rslave"
        ];
      };

      # AudioMuse: its own PostgreSQL, a web app and an analysis worker, all
      # on the music network. It reads the library through Navidrome's API
      # (as a non-admin user), so it never touches /mnt/music itself.
      # Updated together with Navidrome and its plugin by music-stack-update.
      #
      # PostgreSQL 15 is pinned to its major version, as upstream ships it:
      # a major bump needs a dump and restore, never an in-place pull.
      audiomuse-db = {
        image = "docker.io/library/postgres:15-alpine";
        volumes = [ "/var/lib/audiomuse/postgres:/var/lib/postgresql/data" ];
        environmentFiles = [ "/run/secrets/audiomuse.env" ];
        environment = {
          POSTGRES_USER = "audiomuse";
          POSTGRES_DB = "audiomusedb";
          TZ = "UTC";
        };
        extraOptions = [
          "--network=music"
          "--security-opt=no-new-privileges"
        ];
      };

      # Web interface and API, at https://muse.emberfox.net over NetBird.
      # The Navidrome plugin calls http://audiomuse-flask:8000.
      audiomuse-flask = {
        image = "ghcr.io/neptunehub/audiomuse-ai:latest";
        ports = [ "127.0.0.1:8000:8000" ];
        dependsOn = [ "audiomuse-db" ];
        environmentFiles = [ "/run/secrets/audiomuse.env" ];
        environment = audiomuseEnv // { SERVICE_TYPE = "flask"; };
        volumes = [ "/var/lib/audiomuse/plugins-flask:/app/plugin/installed" ];
        extraOptions = [
          "--network=music"
          "--security-opt=no-new-privileges"
          "--tmpfs=/app/temp_audio"
        ];
      };

      # Does the analysis. Capped at 2 CPUs and 4 GB so a full library scan
      # cannot starve the blog, Forgejo or ntfy on an 4 vCPU / 8 GB box.
      audiomuse-worker = {
        image = "ghcr.io/neptunehub/audiomuse-ai:latest";
        dependsOn = [ "audiomuse-db" ];
        environmentFiles = [ "/run/secrets/audiomuse.env" ];
        environment = audiomuseEnv // { SERVICE_TYPE = "worker"; };
        volumes = [ "/var/lib/audiomuse/plugins-worker:/app/plugin/installed" ];
        extraOptions = [
          "--network=music"
          "--security-opt=no-new-privileges"
          "--tmpfs=/app/temp_audio"
          "--cpus=2"
          "--memory=4g"
        ];
      };

  };

  # :latest tags never re-pull once a container exists, so without this the
  # images drift stale indefinitely. Scheduled clear of the reboot window.
  #
  # Navidrome, AudioMuse and the AudioMuse plugin must stay on matching
  # versions, so they update together: pull both images, fetch the plugin's
  # latest release, and if any of the three changed, restart all of them.
  # The nightly similar-songs check is the alarm if
  # a release ever breaks the trio.
  systemd.services.music-stack-update = {
    description = "Update Navidrome, AudioMuse and its plugin together";
    path = [ pkgs.curl pkgs.coreutils pkgs.systemd ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -uo pipefail
      changed=0
      failmark=$(mktemp)
      rm -f "$failmark"

      pull() {  # pull <container>; prints "changed" if the image moved
        img=$(${podman} inspect --format '{{.ImageName}}' "$1" 2>/dev/null) || return 0
        before=$(${podman} image inspect --format '{{.Id}}' "$img" 2>/dev/null || echo none)
        ${podman} pull -q "$img" >/dev/null || { echo "pull failed: $img" >&2; touch "$failmark"; return 0; }
        after=$(${podman} image inspect --format '{{.Id}}' "$img" 2>/dev/null || echo none)
        [ "$before" != "$after" ] && echo changed
        return 0
      }

      for c in navidrome audiomuse-flask audiomuse-db; do
        [ "$(pull "$c")" = changed ] && changed=1
      done

      # The plugin: latest release asset, swapped in only if it differs.
      plugdir=/var/lib/navidrome/plugins
      mkdir -p "$plugdir"
      tmp=$(mktemp)
      if curl -fsSL -m 120 -o "$tmp" \
           https://github.com/NeptuneHub/AudioMuse-AI-NV-plugin/releases/latest/download/audiomuseai.ndp \
         && [ -s "$tmp" ]; then
        if ! cmp -s "$tmp" "$plugdir/audiomuseai.ndp"; then
          install -m 0644 "$tmp" "$plugdir/audiomuseai.ndp"
          changed=1
        fi
      else
        echo "plugin download failed" >&2
        rm -f "$tmp"
        exit 1
      fi
      rm -f "$tmp"

      if [ "$changed" = 1 ]; then
        echo "music stack changed, restarting it"
        systemctl restart podman-audiomuse-db.service
        systemctl restart podman-audiomuse-flask.service podman-audiomuse-worker.service
        systemctl restart podman-navidrome.service
      else
        echo "music stack unchanged"
      fi

      if [ -e "$failmark" ]; then
        rm -f "$failmark"
        exit 1
      fi
    '';
  };

  systemd.timers.music-stack-update = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 06:00";
      RandomizedDelaySec = "30m";
      Persistent = true;
    };
  };

  fox.server.monitoring.alertOnFailure.music-stack-update.title = "music update FAILED";

  # Nightly proof that similar songs really come from AudioMuse. Navidrome
  # quietly falls back to Last.fm when the plugin breaks, so "Navidrome
  # returned similar songs" proves nothing on its own. Instead, for three
  # random tracks, ask AudioMuse directly and ask Navidrome, and pass if the
  # two answers overlap for at least one of them.
  systemd.services.similar-songs-check = {
    description = "Check that Navidrome's similar songs come from AudioMuse";
    path = with pkgs; [ curl jq coreutils ];
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = [
        "/run/secrets/navidrome-api.env"
        "/run/secrets/audiomuse.env"
      ];
    };
    script = ''
      set -uo pipefail

      subsonic() {  # subsonic <method> [curl args...]
        local method=$1; shift
        local salt token
        salt=$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')
        token=$(printf '%s%s' "$ND_PASSWORD" "$salt" | md5sum | cut -d' ' -f1)
        curl -fsS -m 30 --get "http://127.0.0.1:4533/rest/$method" \
          --data-urlencode "u=$ND_USER" --data-urlencode "t=$token" \
          --data-urlencode "s=$salt" --data-urlencode "v=1.16.1" \
          --data-urlencode "c=similar-songs-check" --data-urlencode "f=json" "$@"
      }

      fail() {
        echo "$1" >&2
        ${notify} "${config.networking.hostName}: similar songs broken" "$1" high
        exit 0
      }

      ids=$(subsonic getRandomSongs --data-urlencode size=3 \
              | jq -r '."subsonic-response".randomSongs.song[]?.id') \
        || fail "Navidrome did not answer getRandomSongs."
      [ -n "$ids" ] || fail "Navidrome returned no songs at all."

      muse_any=0
      for id in $ids; do
        muse=$(curl -fsS -m 60 -H "Authorization: Bearer $API_TOKEN" \
                 --get http://127.0.0.1:8000/api/similar_tracks \
                 --data-urlencode "item_id=$id" --data-urlencode n=10 \
               | jq -r '.[]?.item_id' 2>/dev/null) || continue
        [ -n "$muse" ] || continue
        muse_any=1
        nd=$(subsonic getSimilarSongs2 --data-urlencode "id=$id" --data-urlencode count=10 \
             | jq -r '."subsonic-response".similarSongs2.song[]?.id' 2>/dev/null)
        if [ -n "$nd" ] && grep -qxFf <(echo "$muse") <(echo "$nd"); then
          echo "ok: Navidrome's similar songs for $id match AudioMuse"
          exit 0
        fi
      done

      if [ "$muse_any" = 0 ]; then
        fail "AudioMuse returned no similar songs for 3 random tracks. Is it running, and has the library been analyzed?"
      fi
      fail "AudioMuse answers, but Navidrome's similar songs don't match it. The plugin is probably broken or out of step: check Navidrome's Plugins page and its log."
    '';
  };

  systemd.timers.similar-songs-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 05:30:00";
      RandomizedDelaySec = "10m";
      Persistent = true;
    };
  };

  # AssertPathIsMountPoint above leaves Navidrome down for good if the CIFS
  # mount is slow at boot. Only acts when the mount is present and the
  # container is not running, so it cannot mask a real storage outage.
  systemd.services.navidrome-mount-retry = {
    description = "Restart Navidrome if the music mount arrived after boot";
    path = [ pkgs.util-linux pkgs.systemd ];
    serviceConfig.Type = "oneshot";
    script = ''
      mountpoint -q /mnt/music || exit 0
      systemctl is-active --quiet podman-navidrome || systemctl restart podman-navidrome
      exit 0
    '';
  };

  systemd.timers.navidrome-mount-retry = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "15min";
    };
  };

  # The music network: Navidrome and AudioMuse find each other by name, which
  # only works on a named network: Podman runs a small DNS server on those.
  systemd.services.podman-network-music = {
    description = "Create the music podman network";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      ${podman} network inspect music >/dev/null 2>&1 \
        || ${podman} network create music
    '';
  };

  # oci-containers units don't know about the network units on their own.
  # Without these, a container can start first and die with
  # "network ... not found". Navidrome's is set where its mount guard is.
  systemd.services.podman-audiomuse-db = {
    after = [ "podman-network-music.service" ];
    requires = [ "podman-network-music.service" ];
    preStart = "mkdir -p /var/lib/audiomuse/postgres";
  };
  systemd.services.podman-audiomuse-flask = {
    after = [ "podman-network-music.service" ];
    requires = [ "podman-network-music.service" ];
    preStart = "mkdir -p /var/lib/audiomuse/plugins-flask";
  };
  systemd.services.podman-audiomuse-worker = {
    after = [ "podman-network-music.service" ];
    requires = [ "podman-network-music.service" ];
    preStart = "mkdir -p /var/lib/audiomuse/plugins-worker";
  };
}
