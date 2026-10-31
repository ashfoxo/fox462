# extraGpuDev: host GPU device nodes beyond /dev/dri (NVIDIA), from
# fox.desktop.sandboxGpuDevices. Missing ones are skipped.
# extraGpuEnv: environment the GPU driver needs (NVIDIA's EGL plugin list),
# from fox.desktop.sandboxGpuEnv.
{ pkgs, nixpak, extraGpuDev ? [ ], extraGpuEnv ? { } }:

let
  inherit (pkgs) lib;

  mkNixPak = nixpak.lib.nixpak {
    inherit (pkgs) lib pkgs;
  };

  # Sandboxes native Nix packages using Bubblewrap
  # rawPipeWire: the pipewire-0 socket, for apps that talk to PipeWire directly
  # (Vesktop's screen-share audio). Everything else plays and records through
  # the pulse socket, and screen sharing gets its stream from the portal.
  # machineId: /etc/machine-id, a permanent unique ID for this laptop. Only
  # Electron apps get it, since they complain without it.
  # state: where the app's home lives. "ram": in /run/sandbox-ram, gone at
  # power-off. "disk": ~/.local/share/sandboxes/<name>, kept. "logins": the
  # disk home, but ~/.cache is in RAM (the app itself must keep history and
  # caches off, see librewolf below). /tmp is always in RAM.
  # extraBindRw: a function of sloth (nixpak's path helpers) returning more
  # read-write binds, e.g. sloth: [ [ host-path sandbox-path ] ].
  makeGuiSandbox = { package, name, state ? "ram", extraBindRw ? (sloth: []), extraDev ? [], extraEnv ? {}, rawPipeWire ? false, machineId ? false }:
    (mkNixPak {
      config = { sloth, ... }: {
        app.package = package;

        # CA bundle. Without this every HTTPS site shows a certificate error.
        etc.sslCertificates.enable = true;

        # iGPU: binds /dev/dri, the needed /sys paths, and /run/opengl-driver (Mesa)
        gpu = {
          enable = true;
          provider = "nixos";
        };

        # D-Bus through the filtered proxy, with portal + notification access
        dbus.enable = true;
        dbus.policies = {
          "org.freedesktop.portal.*" = "talk";
          "org.freedesktop.Notifications" = "talk";
        };

        bubblewrap = {
          network = true;

          # New session: a sandboxed app started from a terminal can't push
          # keystrokes into that terminal (TIOCSTI) and run them outside.
          newSession = true;

          # Force dark mode for GTK / Electron apps, plus any per-app vars
          env = { GTK_THEME = "Adwaita:dark"; } // extraGpuEnv // extraEnv;

          # Webcams etc. (/dev/dri is already handled by gpu.enable)
          bind.dev = extraDev ++ extraGpuDev;

          bind.ro = [
            # Fonts + per-user profile (icons, cursors)
            "/etc/fonts"
            "/etc/profiles/per-user"

            # Name resolution and misc files libc and Chromium/Firefox expect
            "/etc/resolv.conf"
            "/etc/hosts"
            "/etc/nsswitch.conf"
            "/etc/localtime"

            # Host GTK theme settings, read-only
            (sloth.mkdir (sloth.concat [ sloth.homeDir "/.config/gtk-3.0" ]))
            (sloth.mkdir (sloth.concat [ sloth.homeDir "/.config/gtk-4.0" ]))
          ] ++ lib.optional machineId "/etc/machine-id";

          bind.rw = [
            # Wayland display socket
            (sloth.concat [ (sloth.env "XDG_RUNTIME_DIR") "/" (sloth.env "WAYLAND_DISPLAY") ])
            # PulseAudio-compat socket (pipewire-pulse), used for mic and speakers
            (sloth.concat [ (sloth.env "XDG_RUNTIME_DIR") "/pulse" ])

            # Isolate home directory state, in RAM or on disk (see state above)
            [
              (if state == "ram"
               then sloth.mkdir (sloth.concat [ "/run/sandbox-ram/" name ])
               else sloth.mkdir (sloth.concat [ sloth.homeDir "/.local/share/sandboxes/" name ]))
              sloth.homeDir
            ]

            # Per-app shared folder:
            # host /home/arlo/sandbox_folders/<n> -> sandbox ~/Shared
            [
              (sloth.mkdir (sloth.concat [ sloth.homeDir "/sandbox_folders/" name ]))
              (sloth.concat [ sloth.homeDir "/Shared" ])
            ]

            # Per-app /tmp, in RAM. bwrap gives the sandbox none by default, and
            # apps that assume it exists can crash at startup (Feishin hangs on
            # an error dialog). Host /run/sandbox-ram/<n>-tmp -> sandbox /tmp
            [
              (sloth.mkdir (sloth.concat [ "/run/sandbox-ram/" name "-tmp" ]))
              "/tmp"
            ]
          ]
          # Over the disk home, so caches never reach the disk.
          ++ lib.optional (state == "logins") [
            (sloth.mkdir (sloth.concat [ "/run/sandbox-ram/" name "-cache" ]))
            (sloth.concat [ sloth.homeDir "/.cache" ])
          ]
          ++ lib.optional rawPipeWire (sloth.concat [ (sloth.env "XDG_RUNTIME_DIR") "/pipewire-0" ])
          ++ extraBindRw sloth;
        };
      };
    }).config.env;

  # Chromium for a single web app. NIXOS_OZONE_WL makes the nixpkgs wrapper
  # pick native Wayland (the sandbox has no X11, same reason as Feishin).
  #
  # drm = true adds Google's Widevine module (unfree), which streaming sites
  # need to play video. It's added by the wrapper, so Chromium isn't rebuilt.
  makeWebApp = name: { drm ? false }: makeGuiSandbox {
    package =
      if drm
      then pkgs.ungoogled-chromium.override { enableWideVine = true; }
      else pkgs.ungoogled-chromium;
    inherit name;
    extraEnv = { NIXOS_OZONE_WL = "1"; };
  };
in
{
  # --- Browsers ---
  # File dialogs stay inside the sandbox: the portal file picker is turned
  # off, so open/save dialogs show only what the browser can actually reach
  # (its sandbox home, with ~/Shared = ~/sandbox_folders/mullvad-browser).
  # Downloads go straight to ~/Shared.
  mullvad-browser = makeGuiSandbox {
    package = pkgs.mullvad-browser.override {
      extraPrefs = ''
        lockPref("widget.use-xdg-desktop-portal.file-picker", 0);
        defaultPref("browser.download.folderList", 2);
        defaultPref("browser.download.dir", "/home/arlo/Shared");
        defaultPref("browser.download.useDownloadDir", true);
      '';
    };
    name = "mullvad-browser";
  };
  # The one browser that keeps logins across reboots. History, disk cache,
  # session restore and form data are off, and cookies are not cleared at exit.
  # shortcut: logins live in the on-disk profile; site storage persists with them.
  librewolf = makeGuiSandbox {
    package = pkgs.librewolf.override {
      extraPrefs = ''
        lockPref("places.history.enabled", false);
        lockPref("browser.cache.disk.enable", false);
        lockPref("browser.cache.offline.enable", false);
        lockPref("browser.sessionstore.max_tabs_undo", 0);
        lockPref("browser.sessionstore.resume_from_crash", false);
        lockPref("browser.formfill.enable", false);
        lockPref("browser.download.manager.addToRecentDocs", false);
        lockPref("privacy.clearOnShutdown.cookies", false);
        lockPref("privacy.clearOnShutdown_v2.cookiesAndStorage", false);
        lockPref("network.cookie.lifetimePolicy", 0);
      '';
    };
    name = "librewolf";
    state = "logins";
  };

  # Keyboard-driven browser. Its config (qutebrowser.py) is baked into the
  # package with --config-py, because the sandbox can't see ~/.config.
  qutebrowser = makeGuiSandbox {
    package = pkgs.symlinkJoin {
      name = "qutebrowser-configured";
      paths = [ pkgs.qutebrowser ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/qutebrowser \
          --add-flags "--config-py ${./qutebrowser.py}"
      '';
      meta.mainProgram = "qutebrowser";
    };
    name = "qutebrowser";
    # Native Wayland; the sandbox has no X11.
    extraEnv = { QT_QPA_PLATFORM = "wayland"; };
  };

  # --- Gaming ---
  prismlauncher    = makeGuiSandbox { package = pkgs.prismlauncher;    name = "prismlauncher"; state = "disk"; };  # worlds; synced by syncthing.nix

  # --- Communication ---
  vesktop          = makeGuiSandbox { package = pkgs.vesktop;          name = "vesktop"; rawPipeWire = true; machineId = true; };
  telegram-desktop = makeGuiSandbox { package = pkgs.telegram-desktop; name = "telegram"; };
  # Signal's login and message database are one store: it stays on disk.
  signal-desktop   = makeGuiSandbox { package = pkgs.signal-desktop;   name = "signal"; machineId = true; state = "disk"; };

  # --- Downloads ---
  # qBittorrent downloads into ~/torrents, the same path inside and outside
  # the sandbox. apps.nix points its save path there; restic.nix leaves it
  # out of backups. It can also still see ~/Shared like every sandbox.
  qbittorrent = makeGuiSandbox {
    package = pkgs.qbittorrent;
    name = "qbittorrent";
    extraEnv = { QT_QPA_PLATFORM = "wayland"; };  # the sandbox has no X11
    extraBindRw = sloth: [
      [
        (sloth.mkdir (sloth.concat [ sloth.homeDir "/torrents" ]))
        (sloth.concat [ sloth.homeDir "/torrents" ])
      ]
    ];
  };

  # Firefox and Feishin used to be here. Firefox is now the unsandboxed
  # "clean" browser (modules/desktop/programs.nix); Feishin runs unsandboxed (apps.nix).

  # --- Web apps (webapps.nix) ---
  # One ungoogled-chromium sandbox per site. Each sandbox has its own home
  # (~/.local/share/sandboxes/webapp-<id>), so each app is a fully separate
  # browser profile: separate cookies, logins and storage. No --user-data-dir
  # needed. Not installed directly; webapps.nix wraps each in a launcher.
  webapp-ente    = makeWebApp "webapp-ente" { };
  webapp-tuta    = makeWebApp "webapp-tuta" { };
  webapp-claude  = makeWebApp "webapp-claude" { };
  webapp-elk     = makeWebApp "webapp-elk" { };
  webapp-gmail   = makeWebApp "webapp-gmail" { };
  webapp-messages = makeWebApp "webapp-messages" { };
  webapp-appletv = makeWebApp "webapp-appletv" { drm = true; };
  webapp-spotify = makeWebApp "webapp-spotify" { drm = true; };

  # Fluent Reader is NOT here: nixpkgs ships it as an AppImage, whose wrapper
  # starts its own bubblewrap, and bubblewrap can't nest inside nixpak.
  # It's installed unsandboxed in apps.nix.
}
