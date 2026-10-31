{ pkgs, lib, ... }:

let
  # Wraps an app so it always launches through mullvad-exclude, i.e. it
  # bypasses the Mullvad tunnel. The .desktop entries are rewritten too, so
  # launcher starts and links from other apps also go through the exclusion.
  mullvadExclude = { pkg, name, bins }: pkgs.symlinkJoin {
    name = "${name}-split-tunnel";
    paths = [ pkg ];
    postBuild = ''
      for b in ${lib.concatStringsSep " " bins}; do
        [ -e "$out/bin/$b" ] || continue
        rm "$out/bin/$b"
        printf '#!%s\nexec /run/wrappers/bin/mullvad-exclude %s "$@"\n' \
          "${pkgs.runtimeShell}" "${pkg}/bin/$b" > "$out/bin/$b"
        chmod +x "$out/bin/$b"
      done

      for f in "$out"/share/applications/*.desktop; do
        src=$(readlink -f "$f")
        rm "$f"
        sed -e "s|^Exec=[^ ]*|Exec=$out/bin/${builtins.head bins}|" \
            -e "s|^TryExec=.*|TryExec=$out/bin/${builtins.head bins}|" "$src" > "$f"
      done
    '';
  };

  # Zoom: excluded from Mullvad.
  zoomSplit = mullvadExclude { pkg = pkgs.zoom-us; name = "zoom-us"; bins = [ "zoom" "zoom-us" ]; };

  # Firefox: the "clean" browser. Not sandboxed, no extensions, outside the
  # Mullvad tunnel, but DNS is always encrypted: DNS-over-HTTPS to Quad9 in
  # strict mode (no fallback to plain DNS), locked so it can't be turned off.
  firefoxClean = mullvadExclude {
    pkg = pkgs.firefox.override {
      extraPolicies = {
        DNSOverHTTPS = {
          Enabled = true;
          ProviderURL = "https://dns.quad9.net/dns-query";
          Fallback = false;
          Locked = true;
        };
        DisableTelemetry = true;
        DisableFirefoxStudies = true;
        DisablePocket = true;
      };
    };
    name = "firefox";
    bins = [ "firefox" ];
  };
in
{
  ##### Programs #####
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = false;
  };

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = false; # Bitwarden owns SSH_AUTH_SOCK
    settings = {
      # Asked once, then remembered for 8 hours (with or without the YubiKey).
      # The unlocked key stays in RAM that long; a power-off clears it.
      default-cache-ttl = 28800;
      max-cache-ttl = 28800;
    };
  };

  programs.appimage = {
    enable = true;
    binfmt = false;
  };

  # The phone send/fetch commands are in network/phone.nix.
  environment.systemPackages = with pkgs; [
    git
    vim
    wget
    cryptsetup
    mkpasswd
    fastfetch
    ffmpeg          # convert/inspect any audio or video
    btop            # process monitor
    micro           # simple terminal editor
    yt-dlp
    cfspeedtest
    android-tools   # adb (scrcpy is in apps.nix)

    zoomSplit       # Zoom, outside Mullvad
    firefoxClean    # clean browser, outside Mullvad, encrypted DNS
  ];
}
