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

# TODO: the unsandboxed apps below (notesnook, typora, libreoffice,
# darktable, kdenlive, feishin, zoom) could move into nixpak sandboxes, with
# their state in RAM where that is workable. Decide per app: documents and
# photo libraries need a folder that survives. vscodium, bitwarden (SSH agent),
# steam and fluent-reader (AppImage) can't be sandboxed this way.

let
  sandboxes = import ./sandboxes.nix {
    inherit pkgs nixpak;
    extraGpuDev = osConfig.fox.desktop.sandboxGpuDevices;
    extraGpuEnv = osConfig.fox.desktop.sandboxGpuEnv;
  };
  term = (import ../../lib/palette.nix).for "ghostty";
in
{
  # Ghostty's colours, from palette.nix. The 16 ANSI colours: black, red,
  # green, yellow, blue, magenta, cyan, white, then their bright versions.
  # The bright colours reuse the normal ones, except bright black (the grey
  # for comments) and bright white.
  # force: Ghostty writes an empty config.ghostty on first start, which
  # would otherwise block the switch.
  xdg.configFile."ghostty/config.ghostty" = {
    force = true;
    text = let
      ansi = with term; [ surf rust_text forest_text amber blue magenta teal_text dim ];
      bright = with term; [ faint rust_text forest_text amber blue magenta teal_text fg ];
    in ''
      background = #${term.bg}
      foreground = #${term.fg}
      cursor-color = #${term.forest_text}
      selection-background = #${term.forest}
      selection-foreground = #${term.fg}
    '' + lib.concatImapStrings (i: hex: "palette = ${toString (i - 1)}=#${hex}\n") (ansi ++ bright);
  };

  home.packages = [

    # --- Browsers -----------------------------------------------------------
    # Clean Firefox (unsandboxed, outside Mullvad) is in modules/desktop/programs.nix.

    # --- Communication ------------------------------------------------------
    sandboxes.element-desktop  # Matrix (fox-red)

    # --- Media ---------------------------------------------------------------
    pkgs.feishin               # Navidrome music
    pkgs.jellyfin-desktop      # Jellyfin movies and TV (mpv inside, so it direct-plays)
    pkgs.fluent-reader         # RSS (AppImage; can't be sandboxed, see sandboxes.nix)
    pkgs.vlc                   # backup player; mpv is the default (defaults.nix)
    pkgs.picard                # tag music, then it moves it into ~/drop/Music (fox-red files it)

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
