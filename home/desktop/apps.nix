{ pkgs, lib, config, nixpak, osConfig, ... }:

# Desktop apps for arlo. Grouped by what they're for.
#
# Sandboxed apps come from sandboxes.nix (nixpak/bubblewrap). Each one gets
# its own home in ~/.local/share/sandboxes/<name> and can only reach files
# in ~/sandbox_folders/<name> (shown inside as ~/Shared). qBittorrent also
# gets ~/torrents.
#
# Elsewhere:
#   modules/desktop/programs.nix  CLI tools (ffmpeg, btop, adb, ...), Steam, and the two
#                                 apps outside Mullvad: Zoom and the clean Firefox
#   helpers.nix        Hyprland helpers (launcher, bar, lock, screenshots)
#   webapps.nix        Chromium web apps (Tuta, Claude, Gmail, ...)
#   dev.nix, filen.nix, voicenotes.nix

# TODO(audit): the unsandboxed apps below (notesnook, typora, libreoffice,
# darktable, kdenlive, feishin, zoom) could move into nixpak sandboxes, with
# their state in RAM where that is workable. Decide per app: documents and
# photo libraries need a folder that survives. vscodium, bitwarden (SSH agent),
# steam and fluent-reader (AppImage) can't be sandboxed this way.

let
  # qBittorrent's home is in RAM (sandboxes.nix), so its settings file is gone
  # after every boot. Before each start, write the one setting that matters
  # (downloads go to ~/torrents, which the sandbox binds from disk) if it is
  # missing. The torrent list itself is forgotten at power-off.
  qbittorrent = let
    inner = sandboxes.qbittorrent;
    conf = "/run/sandbox-ram/qbittorrent/.config/qBittorrent/qBittorrent.conf";
    torrents = "${config.home.homeDirectory}/torrents";
  in pkgs.symlinkJoin {
    name = "qbittorrent-seeded";
    paths = [ inner ];
    postBuild = ''
      rm "$out/bin/qbittorrent"
      cat > "$out/bin/qbittorrent" <<'EOF'
      #!${pkgs.runtimeShell}
      mkdir -p ${torrents} "$(dirname ${conf})"
      [ -e ${conf} ] || printf '[BitTorrent]\nSession\\DefaultSavePath=${torrents}\nSession\\TempPathEnabled=false\n' > ${conf}
      exec ${inner}/bin/qbittorrent "$@"
      EOF
      chmod +x "$out/bin/qbittorrent"
      for f in "$out"/share/applications/*.desktop; do
        [ -e "$f" ] || continue
        src=$(readlink -f "$f"); rm "$f"
        sed -e "s|^Exec=[^ ]*|Exec=$out/bin/qbittorrent|" "$src" > "$f"
      done
    '';
  };

  sandboxes = import ./sandboxes.nix {
    inherit pkgs nixpak;
    extraGpuDev = osConfig.fox.desktop.sandboxGpuDevices;
    extraGpuEnv = osConfig.fox.desktop.sandboxGpuEnv;
  };
in
{
  home.packages = [

    # --- Browsers -----------------------------------------------------------
    sandboxes.mullvad-browser
    sandboxes.librewolf
    sandboxes.qutebrowser
    # Clean Firefox (unsandboxed, outside Mullvad) is in modules/desktop/programs.nix.

    # --- Communication ------------------------------------------------------
    sandboxes.signal-desktop
    sandboxes.telegram-desktop
    sandboxes.vesktop          # Discord

    # --- Media ---------------------------------------------------------------
    pkgs.feishin               # Navidrome music
    pkgs.fluent-reader         # RSS (AppImage; can't be sandboxed, see sandboxes.nix)
    pkgs.vlc                   # backup player; mpv is the default (defaults.nix)

    # --- DVDs: rip to MKV, then compress -------------------------------------
    # MakeMKV: lossless rip of a disc to .mkv (unfree; free key while in beta,
    #   https://forum.makemkv.com/forum/viewtopic.php?t=1053).
    # HandBrake: shrink that .mkv (H.265 / AV1). Can also read DVDs directly.
    pkgs.makemkv
    pkgs.handbrake

    # --- Writing and notes -------------------------------------------------
    pkgs.notesnook
    pkgs.typora
    pkgs.libreoffice           # GTK build, matches the GTK file picker

    # --- Creative ------------------------------------------------------------
    pkgs.darktable
    pkgs.kdePackages.kdenlive

    # --- Radio -------------------------------------------------------------
    pkgs.chirp
    pkgs.wsjtx

    # --- Games ---------------------------------------------------------------
    sandboxes.prismlauncher    # Steam is in modules/desktop/programs.nix

    # --- Phone -------------------------------------------------------------
    pkgs.scrcpy                # mirror/control the phone: plug in USB, run `scrcpy`

    # --- Security ------------------------------------------------------------
    pkgs.bitwarden-desktop

    # --- Downloads -----------------------------------------------------------
    qbittorrent

    # --- Tools -------------------------------------------------------------
    pkgs.ghostty
    pkgs.vscodium
    pkgs.qdirstat              # disk usage map
  ];

  # VSCodium: no reopened windows, local file history or hot-exit backups, so
  # less of what you worked on is left in its folders. Merged into any
  # existing settings.json instead of replacing it.
  home.activation.vscodiumNoTraces =
    let settings = "${config.home.homeDirectory}/.config/VSCodium/User/settings.json";
    in lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run mkdir -p "$(dirname ${lib.escapeShellArg settings})"
      [ -s ${lib.escapeShellArg settings} ] || echo '{}' > ${lib.escapeShellArg settings}
      run ${lib.getExe pkgs.jq} '. + {
        "window.restoreWindows": "none",
        "workbench.localHistory.enabled": false,
        "files.hotExit": "off",
        "workbench.startupEditor": "none",
        "telemetry.telemetryLevel": "off"
      }' ${lib.escapeShellArg settings} > ${lib.escapeShellArg settings}.new \
        && run mv ${lib.escapeShellArg settings}.new ${lib.escapeShellArg settings} \
        || { rm -f ${lib.escapeShellArg settings}.new; echo "vscodium settings.json is not plain JSON (comments?); left as is" >&2; }
    '';
}
