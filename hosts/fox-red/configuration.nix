# NixOS configuration for fox-red
# Astro blog + Miniflux + ntfy + MollySocket + Navidrome
# + Uptime Kuma + Forgejo, behind Caddy.
#
# All timers below are UTC. Local is EST/EDT, so subtract 5 or 4.
#
# Nightly order, deliberately non-overlapping:
#   01:00        postgres dump (HOST instance only, i.e. miniflux)
#   01:30-01:50  restic offsite backup, which first dumps Postgres and SQLite
#   02:10-02:25  music ingest: Filen -> beets -> Navidrome
#   03:00-05:00  autoUpgrade -- PAUSED for the rebuild, see Upgrades below
#   05:30        similar-songs check: Navidrome -> AudioMuse plugin
#   Sun 06:00    music stack update: Navidrome, AudioMuse, plugin together
#
# Secrets live encrypted in secrets/, one sops file per secret, readable only
# by the workstation's age key and fox-red's SSH host key (.sops.yaml). At
# activation sops-nix decrypts each one to /run/secrets/<name>, root:root
# 0400, and every service reads it from there. Edit one with:
#   sops --input-type binary --output-type binary secrets/<name>
#
# What each one holds:
#   storagebox-creds   username= / password= for the CIFS mount
#   miniflux.env       ADMIN_USERNAME= / ADMIN_PASSWORD=
#   molly.env          MollySocket registration
#   navidrome-api.env  ND_USER= / ND_PASSWORD= for an admin account. Used by
#                      music-ingest to trigger a library scan over the Subsonic
#                      API. Must be an admin: startScan is admin-only.
#   filen-rclone.env   RCLONE_CONFIG_FILEN_* defining the Filen rclone remote.
#                      PASSWORD and API_KEY are `rclone obscure` output, which
#                      is reversible encoding, not encryption. Treat as
#                      plaintext credentials. Re-export the API key via the
#                      Filen CLI if you ever change the account password.
#   navidrome.env      ND_PASSWORDENCRYPTIONKEY=. Must never change; a copy
#                      lives in Bitwarden.
#   health-check.env   KUMA_PUSH_URL= for the health-check push monitor
#   ntfy-alert.env     NTFY_URL= / NTFY_TOKEN=   (shell-sourceable)
#   kuma-push-url      full Uptime Kuma push URL, no query string
#   restic-password    long random passphrase, also kept off this box
#   restic-s3-env      AWS_ACCESS_KEY_ID= / AWS_SECRET_ACCESS_KEY= for the
#                      bagger-red bucket
#   netbird-setup-key  one-time NetBird setup key. Only used for the first
#                      enrolment; after that it can expire harmlessly.
#   njalla-token       Njalla API token for the wildcard certificate. Limited
#                      to emberfox.net, _acme-challenge TXT records, the four
#                      record methods, and fox-red's own IPv4 and IPv6.
#   audiomuse.env      POSTGRES_PASSWORD= for AudioMuse's own database,
#                      AUDIOMUSE_USER= / AUDIOMUSE_PASSWORD= for its web login,
#                      API_TOKEN= for the Navidrome plugin and the nightly
#                      check, JWT_SECRET= so logins survive restarts, and
#                      NAVIDROME_USER= / NAVIDROME_PASSWORD= for the non-admin
#                      Navidrome account it reads the library through.
#   forgejo-runner.env TOKEN= the runner registration token from Forgejo's
#                      Site administration -> Actions -> Runners. Only used to
#                      register once; the runner keeps its own credentials.

{ config, pkgs, lib, ... }:
let
  # Every file in secrets/, each decrypted to /run/secrets/<name>.
  secretNames = [
    "storagebox-creds"
    "miniflux.env"
    "molly.env"
    "navidrome.env"
    "navidrome-api.env"
    "filen-rclone.env"
    "health-check.env"
    "ntfy-alert.env"
    "kuma-push-url"
    "restic-password"
    "restic-s3-env"
    "netbird-setup-key"
    "njalla-token"
    "audiomuse.env"
    "forgejo-runner.env"
    "forgejo-noreply"
  ];

  secHeaders = ''
    header {
      Strict-Transport-Security "max-age=31536000; includeSubDomains"
      X-Content-Type-Options "nosniff"
      X-Frame-Options "SAMEORIGIN"
      Content-Security-Policy "frame-ancestors 'self'"
      Referrer-Policy "strict-origin-when-cross-origin"
      -Server
    }
  '';

  # Same block, except the CSP is set only if the backend did not send one.
  # Caddy's `header` REPLACES upstream values, so applying secHeaders above to
  # an app that ships its own Content-Security-Policy silently overwrites it
  # with this frame-ancestors-only policy. The app keeps working, which is why
  # you would never notice, but its real CSP is gone. Forgejo ships its own, so
  # it gets this variant.
  #
  # Miniflux may be losing its own CSP to secHeaders the same way.
  # Not changed here: worth checking separately with curl -I before touching.
  secHeadersDeferCSP = ''
    header {
      Strict-Transport-Security "max-age=31536000; includeSubDomains"
      X-Content-Type-Options "nosniff"
      X-Frame-Options "SAMEORIGIN"
      ?Content-Security-Policy "frame-ancestors 'self'"
      Referrer-Policy "strict-origin-when-cross-origin"
      -Server
    }
  '';

  # Caddy access logs, watched by nothing. ntfy and Navidrome both 401
  # legitimate clients holding stale tokens, so no jail could use them.
  mkLog = prefix: keep: host: ''
    log {
      output file /var/log/caddy/${prefix}-${host}.log {
        roll_size 20mb
        roll_keep ${toString keep}
      }
      format json
    }
  '';
  plainLog = mkLog "access" 2;

  # Fire-and-forget ntfy alert. Never fails its caller: an alerting path that
  # can fail a backup or an upgrade is worse than no alerting path.
  # Usage: notify <title> <body> <priority>
  notify = pkgs.writeShellScript "notify" ''
    set -u
    [ -r /run/secrets/ntfy-alert.env ] || exit 0
    . /run/secrets/ntfy-alert.env
    ${pkgs.curl}/bin/curl -fsS -m 10 --retry 3 \
      -H "Authorization: Bearer $NTFY_TOKEN" \
      -H "Title: $1" \
      -H "Priority: $3" \
      -d "$2" \
      "$NTFY_URL" >/dev/null 2>&1 || true
    exit 0
  '';

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

  # The system's own podman, wrapped with NixOS's container config. Scripts
  # run by systemd have no podman on PATH, so they call it by this path.
  podman = "/run/current-system/sw/bin/podman";

in
{
  imports = [ ./hardware-configuration.nix ./music-ingest.nix ];

  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
    # Rollback targets from the rescue console, now that reboots are unattended.
    configurationLimit = 20;
  };

  networking.hostName = "fox-red";

  # Decrypted with fox-red's SSH host key, which sops-nix picks up from
  # services.openssh on its own. If this server is ever reinstalled, the host
  # key changes: re-encrypt secrets/ for the new key from the workstation.
  #
  # Every secret is root-only by default. The exceptions are listed after.
  sops.secrets = lib.mkMerge [
    (lib.genAttrs secretNames (name: {
      sopsFile = ./secrets + "/${name}";
      format = "binary";
    }))
    {
      # Caddy reads the Njalla token straight from this file with its
      # {file.*} placeholder (see the *.emberfox.net site), so it never
      # lands in the Nix store or the Caddyfile. Owned by caddy because Caddy
      # reads it as itself. An environment-file route was tried first and
      # Caddy saw an empty token; reading the file directly also logs a
      # clear error if it ever fails.
      "njalla-token" = {
        owner = "caddy";
        restartUnits = [ "caddy.service" ];
      };
      # Stays root-only: systemd hands it to Forgejo (services.forgejo.secrets
      # uses LoadCredential), so the forgejo user never reads the file itself.
      "forgejo-noreply".restartUnits = [ "forgejo.service" ];
    }
  ];

  time.timeZone = "UTC";

  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 80 443 ];
  };

  # NetBird client, joined to NetBird's hosted control plane. Nothing of
  # NetBird's server side runs here.
  #
  # Enrols itself on first start with the one-time setup key, then keeps its
  # identity in /var/lib/netbird, so later starts never need the key again.
  # The service, command and interface are all plain "netbird" / wt0:
  #   netbird status
  # UDP 51820 is opened so peers can connect directly instead of relaying.
  services.netbird.clients.netbird = {
    port = 51820;
    interface = "wt0";
    login = {
      enable = true;
      setupKeyFile = config.sops.secrets."netbird-setup-key".path;
    };
  };

  ############################################################################
  # Kernel hardening
  ############################################################################

  boot.kernel.sysctl = {
    "kernel.dmesg_restrict" = 1;
    "kernel.kptr_restrict" = 2;
    "kernel.sysrq" = 0;
    "kernel.yama.ptrace_scope" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
    "net.ipv4.tcp_syncookies" = 1;
  };

  nix.settings.allowed-users = [ "root" "@wheel" ];

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  ############################################################################
  # SSH
  ############################################################################

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      KbdInteractiveAuthentication = false;
      X11Forwarding = false;
      MaxAuthTries = 5;
      LoginGraceTime = 30;
      # arlo is you. arlofox is Forgejo's run user, and the two are one
      # character apart -- check twice when reading auth logs. Every key
      # Forgejo writes into /var/lib/forgejo/.ssh/authorized_keys carries a
      # forced command="... forgejo serv key-N" plus no-pty and the three
      # no-*-forwarding restrictions, so a key holder gets git operations and
      # nothing else. Password auth is already off, so there is no other door.
      #
      # Do NOT set services.openssh.authorizedKeysInHomedir = false. It breaks
      # git-over-SSH for forgejo, and the failure is an auth error with no
      # obvious cause.
      AllowUsers = [ "arlo" "forgejo" ];
    };
  };

  # arlo's password lives in /etc/shadow, set with passwd, and is NOT captured
  # by the restic paths below. A bare-metal restore produces an account that
  # cannot sudo until you reset it from a console.
  users.users.arlo = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB/Hsbetd/RG8hDEsngAOd5BfOn2/xLbP5Gm8P1ZViB7"
    ];
  };

  security.sudo.execWheelOnly = true;

  ############################################################################
  # fail2ban
  ############################################################################

  services.fail2ban = {
    enable = true;
    maxretry = 5;
    bantime = "1h";
    bantime-increment = {
      enable = true;
      maxtime = "168h";
    };
    ignoreIP = [
      "127.0.0.0/8"
      "::1"
    ];
  };

  ############################################################################
  # Users and storage
  ############################################################################

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

  ############################################################################
  # Containers (Podman)
  ############################################################################

  # Podman, run as root by systemd, with no daemon. Docker is gone: a root
  # daemon listening for commands was one more thing that could be abused.
  #
  # What runs in a container: Navidrome and AudioMuse (its web app, worker
  # and database), from upstream images, so they move in lockstep.
  #
  # Images are fully qualified (docker.io/...): Podman refuses to guess a
  # registry for a short name when nobody is there to answer its prompt.
  #
  # Containers still run as uid 0 internally. no-new-privileges blocks
  # escalation within a container, but a runtime escape lands at host root.
  # Rootless would fix that and is deliberately NOT used: it would break the
  # uid=navidrome mapping on the CIFS mount above. Accepted risk.
  virtualisation.podman = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
      flags = [ "--all" ];
    };
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

  virtualisation.oci-containers = {
    backend = "podman";
    containers = {

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
    onFailure = [ "notify-music-stack-update-failed.service" ];
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

  systemd.services.notify-music-stack-update-failed = {
    description = "Push an ntfy alert when the music stack update fails";
    serviceConfig.Type = "oneshot";
    script = ''
      ${notify} "fox-red: music update FAILED" \
        "music-stack-update failed. journalctl -u music-stack-update" \
        high
    '';
  };

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
        ${notify} "fox-red: similar songs broken" "$1" high
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

  ############################################################################
  # Uptime Kuma and MollySocket (native)
  ############################################################################

  # Both run under a systemd-made user, with their data in
  # /var/lib/private/<name> and /var/lib/<name> as a link to it. systemd
  # moved the old container data there on first start.

  # 2.x, where the container was 1.x. The first start upgraded the database,
  # one way; the 1.x copy is in /var/lib/uptime-kuma.v1-backup until cleanup.
  # Listens on 127.0.0.1:3001 as before. Its monitors reach the private sites
  # from fox-red's own NetBird address, which Caddy lets in.
  #
  # The module removes every privilege, so ping (ICMP) monitors cannot work.
  # Use HTTP or TCP monitors.
  services.uptime-kuma.enable = true;

  # Outbound only, as before: the web server stays off, and pushes may only go
  # to this ntfy. The registration secret comes in as MOLLY_* variables, which
  # override the settings below.
  services.mollysocket = {
    enable = true;
    environmentFile = "/run/secrets/molly.env";
    settings = {
      db = "/var/lib/mollysocket/db.sqlite";
      webserver = false;
      allowed_endpoints = [ "https://ntfy.emberfox.net" ];
    };
  };

  # Threshold alerting. Kuma watches endpoints; this watches the host itself.
  # The restart-delta check exists because a unit in a restart loop never
  # reaches "failed" state, so nothing else here would see it.
  systemd.services.health-check = {
    description = "Host health thresholds -> ntfy + Kuma push";
    path = with pkgs; [ curl systemd coreutils gawk ];
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = "/run/secrets/health-check.env";
      StateDirectory = "health-check";
    };
    script = ''
      set -uo pipefail

      LOAD_MAX=2.0
      DISK_MAX=80
      MEM_MIN=400
      RESTART_MAX=3
      COOLDOWN=14400

      STATE=/var/lib/health-check
      problems=()

      LOAD15=$(awk '{print $3}' /proc/loadavg)
      if awk -v l="$LOAD15" -v t="$LOAD_MAX" 'BEGIN{exit !(l>t)}'; then
        problems+=("load15 $LOAD15 (max $LOAD_MAX)")
      fi

      DISK=$(df --output=pcent / | tail -1 | tr -dc '0-9')
      if [ "$DISK" -ge "$DISK_MAX" ]; then
        problems+=("disk / at ''${DISK}%")
      fi

      MEM=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
      if [ "$MEM" -lt "$MEM_MIN" ]; then
        problems+=("mem available ''${MEM}MB")
      fi

      FAILED=$(systemctl list-units --state=failed --no-legend --plain | awk '{print $1}' | tr '\n' ' ')
      if [ -n "$FAILED" ]; then
        problems+=("failed: $FAILED")
      fi

      for unit in $(systemctl list-units --type=service --no-legend --plain 'podman-*.service' uptime-kuma.service mollysocket.service | awk '{print $1}'); do
        n=$(systemctl show -p NRestarts --value "$unit")
        f="$STATE/nr.$unit"
        prev=$(cat "$f" 2>/dev/null || echo "$n")
        echo "$n" > "$f"
        if [ $(( n - prev )) -ge "$RESTART_MAX" ]; then
          problems+=("$unit restarted $(( n - prev ))x in 5min")
        fi
      done

      STAMP="$STATE/last-alert"
      NOW=$(date +%s)

      if [ ''${#problems[@]} -gt 0 ]; then
        MSG=$(printf '%s\n' "''${problems[@]}")
        LAST=$(cat "$STAMP" 2>/dev/null || echo 0)
        if [ $(( NOW - LAST )) -ge "$COOLDOWN" ]; then
          ${notify} "fox-red: health check" "$MSG" urgent
          echo "$NOW" > "$STAMP"
        fi
        curl -fsS -m 10 -G "$KUMA_PUSH_URL" \
          --data-urlencode "status=down" --data-urlencode "msg=$MSG" >/dev/null 2>&1 || true
      else
        if [ -f "$STAMP" ]; then
          ${notify} "fox-red: health recovered" "All checks clear." default
          rm -f "$STAMP"
        fi
        curl -fsS -m 10 -G "$KUMA_PUSH_URL" \
          --data-urlencode "status=up" --data-urlencode "msg=OK" >/dev/null 2>&1 || true
      fi
      exit 0
    '';
  };

  systemd.timers.health-check = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5m";
      OnUnitActiveSec = "5m";
      RandomizedDelaySec = "30s";
    };
  };

  ############################################################################
  # Services
  ############################################################################

  services.ntfy-sh = {
    enable = true;
    settings = {
      listen-http = ":8090";
      base-url = "https://ntfy.emberfox.net";
      auth-file = "/var/lib/ntfy-sh/auth.db";
      # UnifiedPush needs anonymous writes to up* topics, granted out of band
      # with: ntfy access '*' 'up*' write-only
      # The alerting topic in ntfy-alert.env must NOT match up*, and needs its
      # own token: ntfy token add arlo
      auth-default-access = "deny-all";
    };
  };

  services.miniflux = {
    enable = true;
    config = {
      LISTEN_ADDR = "localhost:8080";
      BASE_URL = "https://rss.emberfox.net";
      POLLING_FREQUENCY = "15";
    };
    # /run is wiped on reboot, but sops-nix decrypts this again on every boot
    # before services start. File contains ADMIN_USERNAME= and ADMIN_PASSWORD=.
    adminCredentialsFile = "/run/secrets/miniflux.env";
  };

  ############################################################################
  # Forgejo
  ############################################################################

  # Native module, not a container. Two consequences:
  #   - It upgrades with the channel via system.autoUpgrade, so it is NOT in
  #     the container-updates loop and must not be added to it.
  #   - services.forgejo.package defaults to forgejo-lts, so this holds an LTS
  #     line rather than chasing every feature release.
  #
  # Repositories live on local disk under stateDir. Do NOT point
  # repositoryRoot at /mnt/music or any other CIFS mount: git's locking and
  # rename semantics do not survive SMB, and the failure mode is corruption,
  # not an error.
  #
  # NixOS-specific trap, already handled by the module: git hooks and
  # authorized_keys entries embed the absolute store path of the running
  # binary, so an upgrade followed by a gc historically broke both. The
  # module's preStart rewrites those paths on every start, which covers both
  # nix.gc above and autoUpgrade below. If it ever drifts anyway:
  #   forgejo doctor check --run authorized-keys --fix
  services.forgejo = {
    enable = true;

    lfs.enable = true;

    # Settings read from files at start-up, so the values stay out of the
    # repo and the Nix store. Just the domain, e.g. example.net (no "@").
    secrets.service.NO_REPLY_ADDRESS = config.sops.secrets."forgejo-noreply".path;

    settings = {
      server = {
        DOMAIN = "git.arlofox.net";
        ROOT_URL = "https://git.arlofox.net/";
        HTTP_ADDR = "127.0.0.1";
        # 3001 kuma, 4533 navidrome, 8000 audiomuse, 8080 miniflux
        # 8090 ntfy. 3000 is the gap.
        HTTP_PORT = 3000;

        # Host sshd, not the built-in server: 22 is already open and already
        # hardened, and this is what makes the remote a plain
        # arlofox@git.arlofox.net:arlo/repo.git that any client handles with
        # no extra configuration.
        DISABLE_SSH = false;
        START_SSH_SERVER = false;
        SSH_PORT = 22;
        SSH_DOMAIN = "git.arlofox.net";

        # Unauthenticated visitors land on the profile rather than the
        # instance home page, which is Forgejo project marketing ("run the
        # binary", "ship it with Docker") and reads as nonsense on a
        # one-person forge. Signed-in sessions still get the dashboard, and
        # /explore stays reachable -- this changes the front door only.
        LANDING_PAGE = "/arlo";

        # No asset or avatar fetches from third-party CDNs.
        OFFLINE_MODE = true;
      };

      service = {
        DISABLE_REGISTRATION = true;

        # Public. Anonymous browsing and anonymous HTTPS clone both work.
        # Anonymous SSH does not exist -- SSH always authenticates a key --
        # so read-only visitors use the https:// URL.
        REQUIRE_SIGNIN_VIEW = false;

        # Public instance, so without this the account address would sit on
        # the profile page and in the author field of every commit. Commits
        # get <name>@<no-reply domain> instead; the real address stays for
        # login and, if mailer is ever enabled, notifications. The no-reply
        # domain itself (NO_REPLY_ADDRESS) is a secret, set below.
        DEFAULT_KEEP_EMAIL_PRIVATE = true;
      };

      # On for the blog: pushing to it builds and publishes arlofox.net
      # through the runner below. Workflows use plain shell steps only, so no
      # actions are fetched from anywhere.
      actions.ENABLED = true;

      picture = {
        DISABLE_GRAVATAR = true;
        ENABLE_FEDERATED_AVATAR = false;
      };

      session.COOKIE_SECURE = true;

      # No SMTP configured. Until this flips to true the admin address is an
      # identifier and a login handle only -- nothing is sent to it, INCLUDING
      # password resets. With registration disabled, /user/login is the entire
      # auth surface and there is no recovery path but the CLI. Put TOTP on
      # the account and keep the password in Bitwarden.
      mailer.ENABLED = false;
    };
  };

  ############################################################################
  # Blog builds
  ############################################################################

  # The blog (an Astro site in its own repo on this Forgejo) is built by this
  # runner on every push to main, and published to /var/lib/blog:
  #   releases/<commit>/   one finished build per commit, newest 5 kept
  #   current -> releases/<commit>/   switched atomically; Caddy serves it
  #
  # "native:host" runs jobs directly on fox-red, not in a container, as a
  # throwaway systemd user with a read-only view of the system. The only
  # thing it may write is /var/lib/blog, through the blog group.
  users.groups.blog = { };

  services.gitea-actions-runner = {
    package = pkgs.forgejo-runner;
    instances.blog = {
      enable = true;
      name = "fox-red";
      url = "https://git.arlofox.net";
      tokenFile = "/run/secrets/forgejo-runner.env";
      labels = [ "native:host" ];
      # What a job can run. Node matches the blog's own dev shell.
      hostPackages = with pkgs; [
        bash coreutils findutils gnugrep gnused gnutar gzip git nodejs_24
      ];
      settings.runner.capacity = 1;
      # Jobs run in /var/lib/blog/work. The runner's own state directory is
      # mounted noexec by systemd (DynamicUser), so npm's build tools
      # (esbuild) cannot run there.
      settings.host.workdir_parent = "/var/lib/blog/work";
    };
  };

  systemd.services.gitea-runner-blog.serviceConfig = {
    SupplementaryGroups = [ "blog" ];
    ReadWritePaths = [ "/var/lib/blog" ];
    UMask = "0002";
  };

  # A failed build writes /var/lib/blog/build-failed (commit and log link).
  # The runner cannot read the ntfy token, so root sends the alert instead.
  systemd.paths.blog-build-failed = {
    wantedBy = [ "multi-user.target" ];
    pathConfig.PathModified = "/var/lib/blog/build-failed";
  };
  systemd.services.blog-build-failed = {
    description = "Push an ntfy alert when a blog build fails";
    serviceConfig.Type = "oneshot";
    script = ''
      [ -s /var/lib/blog/build-failed ] || exit 0
      ${notify} "fox-red: blog build FAILED" \
        "The live site is unchanged. $(cat /var/lib/blog/build-failed)" \
        high
    '';
  };

  ############################################################################
  # Caddy
  ############################################################################

  services.caddy = {
    enable = true;
    # Only so the ACME CA can warn about renewal failures. Nothing else here
    # would tell you a cert was about to lapse.
    email = "fidgeting.twitch457@anonaddy.com";

    # Stock Caddy plus the Njalla DNS plugin, for the wildcard certificate.
    # The hash pins the plugin's source. On a plugin version bump, set it to
    # lib.fakeHash, build once, and copy the "got:" hash from the error.
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/njalla@v1.0.0" ];
      hash = "sha256-w8TGwmQHx9uTGQExZ8nAkH1jWnMXU0aUf73/9ZdHMOI=";
    };

    virtualHosts = {

      # The blog: plain files from the latest build (see Blog builds above).
      # current is a symlink each build switches in one step, so a visitor
      # never sees half a site.
      "arlofox.net".extraConfig = ''
        ${secHeaders}
        ${plainLog "arlofox.net"}

        root * /var/lib/blog/current
        encode zstd gzip

        # Ghost's old addresses, so existing links and feed readers follow.
        # Post and tag addresses are unchanged.
        redir /rss /rss.xml permanent
        redir /rss/ /rss.xml permanent
        @ghostImage path_regexp ghostImage ^/content/images/(?:size/[^/]+/)?(?:format/[^/]+/)?(.+)$
        redir @ghostImage /images/{re.ghostImage.1} permanent

        file_server

        handle_errors 404 {
          root * /var/lib/blog/current
          rewrite * /404.html
          file_server
        }
      '';

      "ntfy.emberfox.net".extraConfig = ''
        ${secHeaders}
        ${plainLog "ntfy.emberfox.net"}
        reverse_proxy 127.0.0.1:8090
      '';

      # Every private service, behind one wildcard certificate.
      #
      # The certificate comes from the DNS challenge through Njalla, because
      # Let's Encrypt cannot reach a NetBird address. A wildcard also keeps
      # the private names out of the public certificate logs. ntfy above has
      # its own site block, which beats this wildcard, so it stays public on
      # an ordinary certificate.
      #
      # DNS sends *.emberfox.net to fox-red's NetBird address, but Caddy still
      # listens on the public IP too, and anyone can send a request there with
      # a private Host header. So the source address is checked as well:
      #   100.64.0.0/10   NetBird peers
      #   127.0.0.0/8 ::1 fox-red itself
      # Uptime Kuma runs on fox-red, and its requests to these names leave
      # from fox-red's own NetBird address, so they fall in the first range.
      # Anything else gets its connection dropped with no response.
      #
      # Unknown names under emberfox.net are dropped the same way.
      "*.emberfox.net".extraConfig = ''
        tls {
          dns njalla {file./run/secrets/njalla-token}
          propagation_delay 2m
          propagation_timeout 10m
        }
        ${secHeaders}
        ${plainLog "private.emberfox.net"}

        @outside not remote_ip 100.64.0.0/10 127.0.0.0/8 ::1
        handle @outside {
          abort
        }

        @rss host rss.emberfox.net
        handle @rss {
          reverse_proxy localhost:8080
        }

        # Navidrome's own password is the entire gate here: the Subsonic API
        # answers bad credentials with HTTP 200, so no jail could watch it.
        # NetBird is now the first gate.
        @music host music.emberfox.net
        handle @music {
          reverse_proxy 127.0.0.1:4533
        }

        @status host status.emberfox.net
        handle @status {
          reverse_proxy 127.0.0.1:3001
        }

        # AudioMuse's own login is still in front of everything here.
        @muse host muse.emberfox.net
        handle @muse {
          reverse_proxy 127.0.0.1:8000
        }

        handle {
          abort
        }
      '';

      # secHeadersDeferCSP, not secHeaders: Forgejo sends its own
      # Content-Security-Policy and the plain block would silently replace it
      # with the frame-ancestors-only policy. Confirm after deploy with
      #   curl -sI https://git.arlofox.net/ | grep -i content-security
      #
      # Git over HTTP makes an unauthenticated request
      # first and takes the 401 before retrying with credentials, so every
      # normal clone would feed a 401-counting jail and ban you. Exactly the
      # ntfy and Navidrome problem. Nothing watches this namespace, hence
      # roll_keep 10 -- though a public forge fills it far faster than the
      # rest of these.
      #
      # No basic_auth gate, and there cannot be one: git sends its own
      # Authorization header carrying Forgejo credentials, so a Caddy-level
      # basic_auth would either consume it or reject every push.
      #
      # Caddy has no default request body limit, so there is no nginx
      # client_max_body_size equivalent to set here. Add
      #   request_body { max_size 512MB }
      # inside the handle block if you want a ceiling on pushes.
      "git.arlofox.net".extraConfig = ''
        ${secHeadersDeferCSP}
        ${mkLog "access" 10 "git.arlofox.net"}

        # Public forges are a magnet for crawlers walking every commit, blame
        # and archive URL across every ref, which is the usual way a small
        # instance falls over: each of those is a git operation, not a page
        # fetch. Served from Caddy rather than Forgejo's customDir so it does
        # not depend on where a given release puts static overrides. The
        # crawlers that ignore robots.txt are what a Caddy rate limiter would
        # be for later, which needs a plugin build via
        # services.caddy.package = pkgs.caddy.withPlugins { ... }.
        handle /robots.txt {
          root * ${pkgs.writeTextDir "robots.txt" ''
            User-agent: *
            Crawl-delay: 10
            Disallow: /*/*/commits/
            Disallow: /*/*/blame/
            Disallow: /*/*/raw/
            Disallow: /*/*/archive/
            Disallow: /*/*/src/commit/
            Disallow: /explore
            Disallow: /user/
          ''}
          file_server
        }

        handle {
          reverse_proxy 127.0.0.1:3000
        }
      '';

    };
  };

  ############################################################################
  # Backups
  ############################################################################

  services.postgresqlBackup = {
    enable = true;
    databases = [ "miniflux" ];
    startAt = "*-*-* 01:00:00";
  };

  # bagger-red, a fresh repository as of the rebuild. Versioning is on, so a
  # plain delete from these credentials leaves a delete marker rather than
  # destroying data, and the key is limited to this one bucket.
  #
  # The previous repository is the redfox-backup bucket. It keeps the
  # pre-rebuild history and stays until bagger-red holds six months of its
  # own snapshots. To read it: same password, its old keys, and
  #   RESTIC_REPOSITORY=s3:https://s3.fr-par.scw.cloud/redfox-backup
  services.restic.backups.offsite = {
    repository = "s3:https://s3.fr-par.scw.cloud/bagger-red";
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
    backupPrepareCommand = ''
      # AudioMuse's analysis results. Losing them only costs a re-analysis,
      # but that is hours of CPU, so they are dumped like the others.
      if ${podman} exec audiomuse-db \
           pg_dump -U audiomuse -d audiomusedb \
           > /var/backup/audiomuse/audiomuse.sql.tmp ; then
        mv /var/backup/audiomuse/audiomuse.sql.tmp /var/backup/audiomuse/audiomuse.sql
      else
        rm -f /var/backup/audiomuse/audiomuse.sql.tmp
        ${notify} "fox-red: audiomuse pg_dump failed" \
          "Could not dump the AudioMuse database. Tonight's backup carries the previous dump, or none at all." \
          high
      fi

      # The forgejo path is interpolated from the module's own option rather
      # than hardcoded, so the [ -f ] guard below cannot start silently
      # skipping it if a release moves the file.
      for db in \
        /var/lib/navidrome/navidrome.db \
        /var/lib/private/uptime-kuma/kuma.db \
        /var/lib/private/mollysocket/db.sqlite \
        /var/lib/ntfy-sh/auth.db \
        ${config.services.forgejo.database.path} ; do
        [ -f "$db" ] || continue
        if ! ${pkgs.sqlite}/bin/sqlite3 "$db" \
             ".backup '/var/backup/sqlite/$(basename "$db")'" ; then
          ${notify} "fox-red: sqlite dump failed" \
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

    paths = [
      "/var/lib/navidrome"
      # NOT /var/lib/ntfy-sh. The ntfy module uses DynamicUser, so that path is
      # a symlink to private/ntfy-sh and restic archives the link, not the
      # data. Ownership will not survive a restore either, since the uid is
      # allocated per-boot; systemd re-chowns StateDirectory on start.
      "/var/lib/private/ntfy-sh"
      # Same symlink story for these two, which now run under DynamicUser.
      "/var/lib/private/uptime-kuma"
      "/var/lib/private/mollysocket"
      "/var/backup/postgresql"
      "/var/backup/sqlite"
      "/var/backup/audiomuse"
      # Repositories, LFS objects, attachments, the authorized_keys file --
      # and custom/conf/app.ini, which holds SECRET_KEY, INTERNAL_TOKEN and
      # the JWT secrets the module generated on first start. Restore the
      # sqlite dump without app.ini and stored 2FA secrets and tokens are
      # unreadable. The live .db rides along beside its dump, same as
      # navidrome.
      #
      # This is also what will grow the repository fastest from here, which
      # scales the monthly --read-data-subset=5% egress with it.
      config.services.forgejo.stateDir
      # The config as last deployed (deploy.sh copies it here), secrets still
      # encrypted. A copy that does not depend on the workstation or Codeberg.
      "/home/arlo/fox-red"
    ];
    exclude = [
      "/var/lib/navidrome/cache"
      "/var/lib/forgejo/data/tmp"
      "/var/lib/forgejo/log"
    ];
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
      ${notify} "fox-red: backup FAILED" \
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
      ${notify} "fox-red: repo check FAILED" \
        "restic check found a problem offsite. journalctl -u restic-check-offsite" \
        urgent
    '';
  };

  ############################################################################
  # Housekeeping
  ############################################################################

  systemd.tmpfiles.rules = [
    "d /var/log/caddy 0755 caddy caddy -"
    "d /var/backup/sqlite 0700 root root -"
    "d /var/backup/audiomuse 0700 root root -"
    # AudioMuse's bind-mount sources are made by mkdir in the units below,
    # not here: a tmpfiles rule would chown the postgres directory back to
    # root on every boot, undoing the owner its entrypoint set.
    "d /var/lib/audiomuse 0700 root root -"
    "d /var/lib/navidrome/plugins 0755 root root -"
    # setgid: everything the runner creates stays in the blog group.
    "d /var/lib/blog 2775 root blog -"
    "d /var/lib/blog/releases 2775 root blog -"
  ];

  services.journald.extraConfig = ''
    SystemMaxUse=500M
    MaxRetentionSec=1month
  '';

  # The forgejo CLI is how the first admin gets created and how a password
  # would ever be reset. It is already in the closure via the unit, so this
  # costs nothing. It sits outside the `with pkgs` scope on purpose: in there,
  # pkgs.config would shadow the config module argument.
  environment.systemPackages = (with pkgs; [
    curl
    htop
    git
    cifs-utils
    micro
    tmux
    rsync
    restic
    sqlite
    jq
  ]) ++ [ config.services.forgejo.package ];

  ############################################################################
  # Upgrades
  ############################################################################

  # The release line is pinned in flake.nix now, not by a channel URL here.
  #
  # system.autoUpgrade is deliberately OFF for the rebuild. The old one
  # rebuilt from /etc/nixos/configuration.nix every night at 03:00, which
  # would quietly undo whatever was deployed from this flake that day. Every
  # deploy comes from the workstation instead (deploy.sh), with
  # `nix flake update` first so security fixes keep landing.
  #
  # >>> A pinned release goes EOL silently. Calendar reminder: bump
  # >>> flake.nix to nixos-26.11 by DECEMBER 2026, and to 27.05 by JUNE 2027.

  # Flakes on the server itself, so deploy.sh can build here.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # NOT the NixOS release. This is the install-time compatibility marker, and
  # it is what pins PostgreSQL's major version under Miniflux. Leave at 24.11.
  system.stateVersion = "24.11";
}
