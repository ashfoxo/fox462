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
  # network = false: no network at all, for apps that only show local files.
  # machineId: /etc/machine-id, a permanent unique ID for this laptop. Only
  # Electron apps get it, since they complain without it.
  # state: where the app's home lives. "ram": in /run/sandbox-ram, gone at
  # power-off. "disk": ~/.local/share/sandboxes/<name>, kept. "logins": the
  # disk home, but ~/.cache is in RAM (the app itself must keep history and
  # caches off). /tmp is always in RAM.
  # persist: with state "ram", folders (relative to the home) that are kept on
  # disk anyway, in ~/.local/share/sandboxes/<name>/<folder>: the login of the
  # app. Folders only, since a file can't be bound before it exists.
  # extraBindRw: a function of sloth (nixpak's path helpers) returning more
  # read-write binds, e.g. sloth: [ [ host-path sandbox-path ] ].
  # secrets: may talk to the host's secret service (pass-secret-service, home/default.nix),
  # for apps that keep their database key in the keyring (Element). Note it is
  # one shared keyring: the app can ask for any secret in it, not just its own.
  makeGuiSandbox = { package, name, state ? "ram", persist ? [ ], extraBindRw ? (_sloth: []), extraDev ? [], extraEnv ? {}, rawPipeWire ? false, machineId ? false, network ? true, secrets ? false }:
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
        } // lib.optionalAttrs secrets { "org.freedesktop.secrets" = "talk"; };

        bubblewrap = {
          inherit network;

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
          # Kept across reboots even though the rest of the home is in RAM.
          ++ map (p: [
            (sloth.mkdir (sloth.concat [ sloth.homeDir "/.local/share/sandboxes/" name "/" p ]))
            (sloth.concat [ sloth.homeDir "/" p ])
          ]) persist
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
  # keepLogin = false: nothing on disk, so you log in again after every boot.
  makeWebApp = name: { drm ? false, keepLogin ? true }: makeGuiSandbox {
    package =
      if drm
      then pkgs.ungoogled-chromium.override { enableWideVine = true; }
      else pkgs.ungoogled-chromium;
    inherit name;
    extraEnv = { NIXOS_OZONE_WL = "1"; };
    # The login: cookies, site storage. History and caches stay in RAM.
    persist = lib.optionals keepLogin (map (d: ".config/chromium/Default/" + d)
      [ "Network" "Local Storage" "IndexedDB" "Session Storage" ]);
  };
in
{
  # --- Browsers ---
  # Mullvad Browser runs in the untrusted VM, LibreWolf in personal (modules/vms.nix).

  # --- Gaming ---
  prismlauncher    = makeGuiSandbox { package = pkgs.prismlauncher;    name = "prismlauncher"; state = "disk"; };  # worlds; synced by syncthing.nix

  # --- Communication ---
  # Telegram, Discord (Vesktop) and Zoom for calls run in the calls VM (modules/vms.nix).

  # Element's login, message cache and E2EE keys are one store: it stays on disk.
  # Its database key goes in the host keyring, so the DB is useless without it.
  # The sandbox has no xdg-open, and Element's login (OIDC) opens the browser
  # with it. This one asks the host's desktop portal to open the link instead,
  # with "ask" so you pick the browser: the system default is Mullvad, which
  # can't hand the login back to Element, so pick the clean Firefox.
  element-desktop = makeGuiSandbox {
    package = let
      element = pkgs.element-desktop.override { commandLineArgs = "--password-store=gnome-libsecret"; };
      xdgOpen = pkgs.writeShellScriptBin "xdg-open" ''
        exec ${pkgs.glib.bin}/bin/gdbus call --session \
          --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop \
          --method org.freedesktop.portal.OpenURI.OpenURI "" "$1" "{'ask': <true>}" > /dev/null
      '';
    in pkgs.symlinkJoin {
      name = "element-desktop-xdg-open";
      paths = [ element ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/element-desktop --prefix PATH : ${xdgOpen}/bin
      '';
      meta.mainProgram = "element-desktop";
    };
    name = "element"; machineId = true; state = "disk"; secrets = true;
  };

  # --- Downloads ---
  # qBittorrent downloads into ~/torrents, the same path inside and outside
  # the sandbox. apps.nix points its save path there; restic.nix leaves it
  # out of backups. It can also still see ~/Shared like every sandbox.
  # qBittorrent runs in the torrent VM (modules/vms.nix).

  # Firefox and Feishin used to be here. Firefox is now the unsandboxed
  # "clean" browser (modules/desktop/programs.nix); Feishin runs unsandboxed (apps.nix).

  # --- Web apps (webapps.nix) ---
  # One ungoogled-chromium sandbox per site. Each sandbox has its own home
  # (~/.local/share/sandboxes/webapp-<id>), so each app is a fully separate
  # browser profile: separate cookies, logins and storage. No --user-data-dir
  # needed. Not installed directly; webapps.nix wraps each in a launcher.
  # Photos and email: logins kept in RAM only, so a seized laptop holds none.
  # Claude joins them as the last step of the audit work.
  webapp-ente    = makeWebApp "webapp-ente" { keepLogin = false; };
  webapp-tuta    = makeWebApp "webapp-tuta" { keepLogin = false; };
  webapp-claude  = makeWebApp "webapp-claude" { };
  webapp-elk     = makeWebApp "webapp-elk" { };
  webapp-gmail   = makeWebApp "webapp-gmail" { keepLogin = false; };
  webapp-spotify = makeWebApp "webapp-spotify" { drm = true; };

  # The health page (home/desktop/health): app-mode Chromium with no network,
  # seeing only the RAM folder health writes the page into. Nothing kept.
  health-view = makeGuiSandbox {
    package = pkgs.ungoogled-chromium;
    name = "health-view";
    network = false;
    extraEnv = { NIXOS_OZONE_WL = "1"; };
    extraBindRw = sloth: [
      [ (sloth.mkdir (sloth.concat [ (sloth.env "XDG_RUNTIME_DIR") "/health" ])) "/health" ]
    ];
  };

  # Fluent Reader is NOT here: nixpkgs ships it as an AppImage, whose wrapper
  # starts its own bubblewrap, and bubblewrap can't nest inside nixpak.
  # It's installed unsandboxed in apps.nix.
}
