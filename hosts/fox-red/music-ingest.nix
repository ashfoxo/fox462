# Filen -> Storage Box -> beets -> Navidrome ingest pipeline.
# Single-copy variant, for nixos-26.05.
#
# Lives at /etc/nixos/music-ingest.nix, imported from configuration.nix:
#   imports = [ ./hardware-configuration.nix ./music-ingest.nix ];
#
# Shape of the thing:
#
#   Filen:/Media/Music        the drop point. Never modified from this side.
#     |  rclone copy, but only paths absent from seen.list
#   /mnt/music/inbox          transient. Holds a file for exactly as long as it
#     |                       takes beets to claim it. What lingers here is what
#     |                       beets refused, and that is the queue you drain.
#     |  beet import (MOVE, incremental)
#   /mnt/music/library        beets-owned. Tagged, renamed, art embedded.
#     |                       The only copy on the Storage Box.
#     |  Subsonic startScan
#   Navidrome
#
# WHY THERE IS NO rclone sync HERE:
#
#   Sync decides what to transfer by comparing source to destination, which
#   stops working the moment beets empties the inbox: an empty destination
#   reads as "download everything again". So the pipeline keeps its own record
#   instead, seen.list, one remote path per line. Consequences:
#
#   * seen.list is load-bearing. Lose it and the next run re-downloads the
#     entire Filen music folder. Nothing is corrupted (duplicate_action: skip
#     catches every album beets already knows) but you pay the bandwidth and
#     then get an inbox full of rejected duplicates to clear by hand. It lives
#     under /var/lib/beets and rides in the restic paths for that reason.
#
#   * Deletions in Filen do not propagate. The path stays in seen.list forever
#     and the library keeps its copy. Usually what you want, but it means Filen
#     is the ingest source, not a control plane.
#
#   * Reorganising folders inside Filen looks like a pile of new files, because
#     seen.list keys on path. Everything gets re-pulled and then rejected as a
#     duplicate. Wasted bandwidth, no damage.
#
#   * The inbox does not self-clean. Anything left in it is a thing that needs
#     you. Treat a non-empty inbox as an open ticket.
#
#   * The compensating win: inbox and library are on the same SMB share, so
#     beets moves files with a server-side rename, no bytes over the wire.
#
# WHY BEETS STATE IS NOT ON THE MOUNT:
#
#   library.db is SQLite, and SQLite cannot lock over CIFS: it needs fcntl
#   advisory locks SMB does not provide, and cache=loose makes it worse. Put
#   the database on /mnt/music and every beets invocation dies with "database
#   is locked". Hence /var/lib/beets on local disk, and hence it must be backed
#   up, since it no longer rides along with the music.
#
# REQUIRED EDITS IN configuration.nix:
#
#   1. imports = [ ./hardware-configuration.nix ./music-ingest.nix ];
#
#   2. Navidrome's volume must point at the library, not the mount root, or it
#      indexes the inbox too and half-tagged files appear and vanish from the
#      library as they pass through:
#          -  "/mnt/music:/music:ro,rslave"
#          +  "/mnt/music/library:/music:ro,rslave"
#      The AssertPathIsMountPoint on docker-navidrome stays at /mnt/music: the
#      assert is about the mount, and the mount has not moved.
#
#   3. Secrets header additions:
#          navidrome-api.env  ND_USER= / ND_PASSWORD= for an ADMIN account.
#                             startScan is admin-only.
#          filen-rclone.env   RCLONE_CONFIG_FILEN_*. PASSWORD and API_KEY are
#                             `rclone obscure` output, which is reversible
#                             encoding, not encryption: treat as plaintext.
#                             Changing the Filen account password invalidates
#                             the API key; re-export it.
#
# ORDER OF OPERATIONS, first time:
#
#   a. sudo nixos-rebuild dry-run          # then switch
#   b. sudo systemctl start docker-navidrome && check the album count
#   c. adopt what you already own into the beets DB, in place:
#          printf 'import:\n  copy: no\n  move: no\n' > /tmp/adopt.yaml
#          sudo music-beet --config /tmp/adopt.yaml import -A -W /mnt/music/library
#   d. sudo systemctl start music-reconcile.service   # READ THE SUMMARY
#   e. sudo systemctl start music-ingest.service

{ config, pkgs, lib, ... }:
let
  inboxDir = "/mnt/music/inbox";
  libraryDir = "/mnt/music/library";
  stateDir = "/var/lib/beets";
  seenList = "${stateDir}/seen.list";
  remote = "filen:/Media/Music";

  ##########################################################################
  # Acoustic fingerprinting
  ##########################################################################
  #
  # chroma runs Chromaprint over the audio and looks the fingerprint up in
  # AcoustID, producing candidate MusicBrainz releases even when the tags are
  # useless. It SUPPLEMENTS the matcher rather than replacing it: the final
  # score is still computed by comparing metadata, and there is no
  # fingerprint-only mode. It also decodes every file, which over CIFS means
  # reading every byte back off the Storage Box.
  #
  # Off by default because it is an optimisation, not a requirement: anything
  # Picard has already tagged matches on metadata alone. Turn it on if a lot of
  # what you drop into Filen arrives untagged.
  #
  # BEFORE FLIPPING THIS, confirm the dependency exists on your channel:
  #   nix-shell -p python3Packages.pyacoustid --run "python -c 'import acoustid'"
  # If that fails, leave this false. A missing plugin is a worse failure than a
  # missing optimisation: beets aborts the import rather than degrading.
  enableChroma = false;

  # pkgs.beets in 26.05 is just `toPythonApplication python3.pkgs.beets` and
  # takes no arguments, so the old `pluginOverrides` interface is gone. Plugin
  # dependencies are added by building the Python environment directly.
  beetsPython = pkgs.python3.withPackages (
    ps: [ ps.beets ] ++ lib.optional enableChroma ps.pyacoustid
  );

  # beets shells out to `fpcalc` from chromaprint, so it has to be on PATH at
  # runtime rather than merely present as a build input.
  beetsPkg = pkgs.runCommand "beets-wrapped"
    {
      nativeBuildInputs = [ pkgs.makeWrapper ];
    }
    ''
      mkdir -p $out/bin
      makeWrapper ${beetsPython}/bin/beet $out/bin/beet \
        ${lib.optionalString enableChroma
          "--prefix PATH : ${lib.makeBinPath [ pkgs.chromaprint ]}"}
    '';

  # Local copy of the notify helper from configuration.nix. Duplicated on
  # purpose: this module should be droppable into another host without dragging
  # the rest of the file along.
  notify = pkgs.writeShellScript "notify-music" ''
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

  beetsConfig = pkgs.writeText "beets-config.yaml" ''
    directory: ${libraryDir}
    library: ${stateDir}/library.db

    import:
      # MOVE, not copy. Same SMB share on both sides, so this is a server-side
      # rename: no bytes cross the network. It is also what makes this the
      # single-copy variant, and what makes the inbox a queue rather than a
      # mirror.
      copy: no
      move: yes
      write: yes
      # Skips directories already imported. State lives in $BEETSDIR/state.pickle.
      incremental: yes
      # Leave at no. Directories beets skipped are recorded as seen, so an album
      # it could not match is reported once and then left alone, instead of
      # re-alerting every night for as long as it sits in the inbox.
      incremental_skip_later: no
      # Unattended runs are -q, which auto-accepts only strong matches. This
      # decides everything else: skip it, leave it in the inbox, alert. The
      # alternative, "asis", silently commits bad metadata to the library.
      quiet_fallback: skip
      duplicate_action: skip
      resume: no
      bell: no

    # NO scrub. Scrub wipes every tag before beets writes its own, and beets
    # only writes back the fields it models: acoustid_id, originalyear,
    # release-group fields, ReplayGain and multi-valued artist credits written
    # by Picard would all be destroyed. Without it, beets normalises what it
    # manages and leaves everything else alone.
    plugins: musicbrainz${lib.optionalString enableChroma " chroma"} fromfilename fetchart embedart mbsync
    ${lib.optionalString enableChroma ''
    chroma:
      auto: yes
    ''}
    musicbrainz:
      # Without these, two pressings of the same album are a coin flip.
      extra_tags: [year, catalognum, country, media, label]
      searchlimit: 5

    match:
      # Lower = stricter. 0.04 is the default. Raise toward 0.10 to auto-accept
      # more and be alerted less, once you trust what is landing.
      strong_rec_thresh: 0.04

    # The default `replace` rules already strip characters SMB refuses
    # (: * ? " < > |) and trailing dots. Do not override them: a path beets
    # considers legal but CIFS rejects fails the import mid-album.
    paths:
      default: $albumartist/$album%aunique{}/$track $title
      singleton: Singles/$artist/$title
      comp: Compilations/$album%aunique{}/$track $title
      albumtype:soundtrack: Soundtracks/$album%aunique{}/$track $title

    art_filename: cover
    fetchart:
      auto: yes
      cautious: yes
      sources:
        - filesystem
        - coverart
        - itunes

    embedart:
      auto: yes
      ifempty: yes

    threaded: yes
    per_disc_numbering: no
  '';

  # Interactive escape hatch. Same config, database and state as the timer, so
  # a manual import of an album the unattended run skipped lands in exactly the
  # right place.
  musicBeet = pkgs.writeShellScriptBin "music-beet" ''
    export BEETSDIR=${stateDir}
    exec ${beetsPkg}/bin/beet "$@"
  '';

  # Forget that a remote path was ever ingested, so the next run pulls it
  # again. This is the recovery tool for "beets tagged that album wrong and I
  # deleted it from the library": without it, seen.list insists the file is
  # already handled and the album is simply gone from the Storage Box.
  #   music-reingest "Boards of Canada"
  # Prints what it would forget; requires --yes to actually do it.
  musicReingest = pkgs.writeShellScriptBin "music-reingest" ''
    set -euo pipefail
    if [ $# -lt 1 ]; then
      echo "usage: music-reingest <substring> [--yes]" >&2
      exit 2
    fi
    pattern="$1"
    matches=$(${pkgs.gnugrep}/bin/grep -F -- "$pattern" ${seenList} || true)
    if [ -z "$matches" ]; then
      echo "no entries in seen.list match: $pattern"
      exit 0
    fi
    echo "$matches"
    echo "---"
    echo "$(printf '%s\n' "$matches" | wc -l) entries would be forgotten."
    if [ "''${2:-}" != "--yes" ]; then
      echo "re-run with --yes to apply, then: systemctl start music-ingest"
      exit 0
    fi
    tmp=$(mktemp)
    ${pkgs.gnugrep}/bin/grep -F -v -- "$pattern" ${seenList} > "$tmp" || true
    mv "$tmp" ${seenList}
    chmod 600 ${seenList}
    echo "done. run: systemctl start music-ingest"
  '';
in
{
  environment.systemPackages = [ pkgs.rclone beetsPkg musicBeet musicReingest ];

  systemd.tmpfiles.rules = [
    "d ${stateDir} 0700 root root -"
    "f ${seenList} 0600 root root -"
    # Store path symlinked in rather than copied, so nixos-rebuild is the only
    # thing that can change the config.
    "L+ ${stateDir}/config.yaml - - - - ${beetsConfig}"
  ];

  # listOf options merge across modules, so this appends to the paths already
  # declared in configuration.nix. If the build reports a conflict here, delete
  # this line and add "/var/lib/beets" to the restic paths list directly.
  #
  # Matters more in the single-copy variant than the mirror one: losing this
  # directory loses seen.list, and the next run re-downloads everything.
  services.restic.backups.offsite.paths = [ stateDir ];

  ############################################################################
  # Reconcile
  ############################################################################

  # Compares Filen against the Storage Box file by file, marks everything
  # already here as seen, and leaves the rest for the ingest run to pull.
  #
  # This REPORTS, it does not transfer. Read the summary and the lists it
  # leaves in /var/lib/beets before starting music-ingest: if it claims
  # thousands of files are missing, the two sides disagree about paths rather
  # than contents, and running ingest would re-download the whole library.
  #
  # Run this BEFORE letting beets reorganise anything. It matches on relative
  # path, so if beets has renamed files into $albumartist/$album/... and Filen
  # has a different layout, every file reads as missing.
  systemd.services.music-reconcile = {
    description = "Reconcile Filen against the Storage Box and seed seen.list";
    after = [ "network-online.target" "remote-fs.target" ];
    wants = [ "network-online.target" ];
    requires = [ "remote-fs.target" ];
    unitConfig = {
      AssertPathIsMountPoint = "/mnt/music";
      RequiresMountsFor = "/mnt/music";
    };
    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = [ "/run/secrets/filen-rclone.env" ];
      TimeoutStartSec = "2h";
      ProtectSystem = "strict";
      ReadWritePaths = [ stateDir "/mnt/music" ];
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
    environment = {
      RCLONE_CONFIG = "/dev/null";
      LC_ALL = "C";
    };
    path = [ pkgs.rclone pkgs.coreutils ];
    script = ''
      set -euo pipefail
      work=$(mktemp -d)
      trap 'rm -rf "$work"' EXIT
      touch "$work/missing-here.list" "$work/missing-in-filen.list" "$work/differ.list"

      # --size-only is not laziness: Filen hashes with Blake3 and CIFS cannot,
      # so there is no common hash and a content check would mean downloading
      # every remote file to compare it. Size catches truncated and absent
      # files, which is what this step is for.
      #
      # check exits non-zero whenever it finds differences, which is the normal
      # outcome here, so its status is deliberately ignored.
      rclone check ${remote} ${libraryDir} \
        --size-only \
        --checkers 8 \
        --missing-on-dst "$work/missing-here.list" \
        --missing-on-src "$work/missing-in-filen.list" \
        --differ "$work/differ.list" || true

      rclone lsf -R --files-only --format p ${remote} | sort > "$work/remote.list"
      sort -u "$work/missing-here.list" > "$work/missing.sorted"

      # seen.list gets everything EXCEPT what is missing locally. Those stay
      # unseen so the next ingest run pulls exactly them and nothing else.
      comm -23 "$work/remote.list" "$work/missing.sorted" >> ${seenList}
      sort -u ${seenList} > "$work/seen.new"
      cat "$work/seen.new" > ${seenList}

      cp "$work/missing-here.list"     ${stateDir}/last-missing.list
      cp "$work/missing-in-filen.list" ${stateDir}/last-missing-in-filen.list
      cp "$work/differ.list"           ${stateDir}/last-differ.list

      echo "remote files:          $(wc -l < "$work/remote.list")"
      echo "seen.list now holds:   $(wc -l < ${seenList})"
      echo "missing on the box:    $(wc -l < "$work/missing-here.list")  -> next ingest pulls these"
      echo "on box, not in Filen:  $(wc -l < "$work/missing-in-filen.list")  -> Filen is NOT complete"
      echo "size mismatch:         $(wc -l < "$work/differ.list")  -> not pulled, review by hand"
    '';
  };

  ############################################################################
  # Ingest
  ############################################################################

  systemd.services.music-ingest = {
    description = "Pull new music from Filen, tag it against MusicBrainz, rescan Navidrome";

    after = [ "network-online.target" "remote-fs.target" ];
    wants = [ "network-online.target" ];
    requires = [ "remote-fs.target" ];

    # The critical guard. Without it, a missing CIFS mount means rclone
    # downloads onto the VPS root filesystem and fills the disk, and beets then
    # imports into a directory Navidrome cannot see. Systemd does not retry
    # assert failures, which is fine: the timer fires again tomorrow.
    unitConfig = {
      AssertPathIsMountPoint = "/mnt/music";
      RequiresMountsFor = "/mnt/music";
    };

    serviceConfig = {
      Type = "oneshot";
      EnvironmentFile = [
        "/run/secrets/filen-rclone.env"
        "/run/secrets/navidrome-api.env"
      ];
      TimeoutStartSec = "6h";
      # Runs as root because writes must not depend on the navidrome uid; the
      # mount's uid=navidrome makes everything written there navidrome-owned
      # regardless of who wrote it.
      ProtectSystem = "strict";
      ReadWritePaths = [ "/mnt/music" stateDir ];
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      Nice = 10;
      IOSchedulingClass = "idle";
    };

    onFailure = [ "notify-music-ingest-failed.service" ];

    environment = {
      BEETSDIR = stateDir;
      # Stops rclone looking for, or creating, a config file. The remote is
      # defined entirely by the RCLONE_CONFIG_FILEN_* vars in the env file.
      RCLONE_CONFIG = "/dev/null";
      # comm requires both inputs sorted under the same collation, and the
      # default locale sorts differently than C for anything non-ASCII. Get
      # this wrong and comm silently reports garbage.
      LC_ALL = "C";
    };

    path = [ pkgs.rclone beetsPkg pkgs.chromaprint pkgs.util-linux pkgs.curl
             pkgs.sqlite pkgs.coreutils pkgs.findutils pkgs.gnugrep ];

    script = ''
      set -euo pipefail

      mkdir -p ${inboxDir} ${libraryDir}

      count_items() {
        sqlite3 "${stateDir}/library.db" 'select count(*) from items' 2>/dev/null || echo 0
      }

      work=$(mktemp -d)
      trap 'rm -rf "$work"' EXIT

      # Full recursive listing of the remote. Cheap relative to transfers, and
      # the only way to notice a file that appeared inside an existing folder.
      rclone lsf -R --files-only --format p ${remote} | sort > "$work/remote.list"
      sort -u ${seenList} > "$work/seen.list"

      # Paths present remotely and absent from seen.list.
      comm -23 "$work/remote.list" "$work/seen.list" > "$work/new.list"
      newcount=$(wc -l < "$work/new.list")
      echo "remote: $(wc -l < "$work/remote.list") files, new: $newcount"

      if [ "$newcount" -gt 0 ]; then
        # --files-from-raw reads the list verbatim: no comment stripping, no
        # glob expansion. Filenames containing # or [ ] are common enough in
        # music that the non-raw variant will eventually bite.
        rclone copy --files-from-raw "$work/new.list" ${remote} ${inboxDir} \
          --transfers 4 \
          --checkers 8 \
          --retries 3 \
          --stats 5m \
          --stats-log-level NOTICE

        # Recorded only after a clean copy. If rclone fails, set -e stops the
        # script here and nothing is marked seen: the partially copied files
        # are already in the inbox, so the next run's copy skips them and
        # fetches the remainder. Idempotent either way.
        cat "$work/new.list" >> ${seenList}
        sort -u ${seenList} > "$work/seen.new"
        cat "$work/seen.new" > ${seenList}
      fi

      before=$(count_items)

      importlog="$work/import.log"

      # -q is what makes this unattended: strong matches applied, anything
      # ambiguous hits quiet_fallback (skip) and stays in the inbox. || true
      # because "nothing new" and "three albums were ambiguous" are both normal
      # outcomes, not failures.
      beet import -q --log "$importlog" ${inboxDir} || true

      after=$(count_items)
      added=$(( after - before ))

      # beets claims only audio when it moves an album, so covers, logs, cue
      # sheets and playlists stay behind. Under move: yes that means every
      # successful import litters the inbox, which would trip the leftover
      # alert below on every run.
      #
      # Only sweep directories with no audio left anywhere beneath them. If
      # audio is still there the album was skipped, and everything in it has to
      # stay put for you to review. -depth processes children first so a
      # multi-disc album whose CD1 was skipped keeps its album-level artwork.
      #
      # Deleting is safe here in a way it would not be elsewhere: Filen still
      # holds the original, and fetchart has already placed the art in the
      # library alongside the tracks.
      has_audio() {
        find "$1" -type f \( -iname '*.flac' -o -iname '*.mp3' -o -iname '*.m4a' \
          -o -iname '*.ogg' -o -iname '*.opus' -o -iname '*.wav' -o -iname '*.wma' \
          -o -iname '*.aiff' -o -iname '*.ape' -o -iname '*.alac' \) -print -quit \
          | grep -q .
      }

      find ${inboxDir} -mindepth 1 -depth -type d | while read -r d; do
        if ! has_audio "$d"; then
          find "$d" -type f -delete
          rmdir "$d" 2>/dev/null || true
        fi
      done

      leftover=$(find ${inboxDir} -type f | wc -l)
      echo "beets: $added tracks added, $leftover file(s) left in the inbox"

      if [ "$leftover" -gt 0 ]; then
        ${notify} "fox-red: music needs a look" \
          "$leftover file(s) beets would not auto-tag, sitting in the inbox. Run: sudo music-beet import -I ${inboxDir}" \
          default
      fi

      # Nothing new means nothing to tell Navidrome. Its own ND_SCANSCHEDULE
      # remains the backstop if this call ever fails.
      if [ "$added" -le 0 ]; then
        echo "no new tracks, skipping Navidrome scan"
        exit 0
      fi

      # Subsonic token auth: t = md5(password + salt), fresh salt per call, so
      # the password never appears in a URL, a log line, or the process table.
      salt=$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')
      token=$(printf '%s%s' "$ND_PASSWORD" "$salt" | md5sum | cut -d' ' -f1)

      curl -fsS -m 30 --get "http://127.0.0.1:4533/rest/startScan" \
        --data-urlencode "u=$ND_USER" \
        --data-urlencode "t=$token" \
        --data-urlencode "s=$salt" \
        --data-urlencode "v=1.16.1" \
        --data-urlencode "c=music-ingest" \
        --data-urlencode "f=json" >/dev/null

      echo "Navidrome scan triggered"
    '';
  };

  # 02:10 sits in the gap: after the 01:30-01:50 restic window, clear of the
  # 03:00-05:00 upgrade window.
  systemd.timers.music-ingest = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 02:10:00";
      RandomizedDelaySec = "15m";
      Persistent = true;
    };
  };

  systemd.services.notify-music-ingest-failed = {
    description = "Push an ntfy alert when the music ingest fails";
    serviceConfig.Type = "oneshot";
    script = ''
      ${notify} "fox-red: music ingest FAILED" \
        "music-ingest failed. journalctl -u music-ingest" \
        high
    '';
  };
}
