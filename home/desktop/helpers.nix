{ pkgs, lib, config, osConfig, ... }:

# Everything around the compositor that a full desktop would otherwise
# provide: wallpaper, idle, launcher, automount, polkit agent, and the
# keybind cheat sheet. Notifications are in quickshell.nix, the lock screen
# in lockscreen.nix.
#
# Every service here binds to hyprland-session.target (set in hyprland.nix
# via wayland.systemd.target), so it starts and stops with Hyprland.

let
  target = config.wayland.systemd.target;
  hyprctl = "${pkgs.hyprland}/bin/hyprctl";

  # Private repo, so the image lives in it. Must be `git add`ed, or flakes
  # can't see it.
  wallpaper = ./wallpapers/firewatch.jpg;

  font = "JetBrainsMono Nerd Font";

  pal = (import ../../lib/palette.nix).for;

  # Super + / : list every described keybind from the running Hyprland.
  # Read-only: picking an entry does nothing.
  cheatsheet = pkgs.writeShellApplication {
    name = "hypr-cheatsheet";
    runtimeInputs = with pkgs; [ jq fuzzel hyprland ];
    text = ''
      hyprctl binds -j | jq -r '
        # modmask is a bitfield: SHIFT=1 CTRL=4 ALT=8 SUPER=64
        def bit(n): (. / n | floor) % 2 == 1;
        def mods: [ (if bit(64) then "SUPER" else empty end),
                    (if bit(4)  then "CTRL"  else empty end),
                    (if bit(8)  then "ALT"   else empty end),
                    (if bit(1)  then "SHIFT" else empty end) ];
        def pad(n): if length < n then . + (" " * (n - length)) else . end;

        map(select(.has_description))
        | map({ d: .description, k: ((.modmask | mods) + [.key] | join(" + ")) })
        | unique
        | sort_by(.d)
        | .[]
        | "\(.d | pad(42))\(.k)"
      ' | fuzzel --dmenu --prompt "keys › " --width 72 --lines 24 >/dev/null || true
    '';
  };
in
{
  ##### Wallpaper #####
  services.hyprpaper = {
    enable = true;
    settings = {
      splash = false;
      wallpaper = [{
        monitor = "*"; # every monitor
        path = "${wallpaper}";
        fit_mode = "cover";
      }];
    };
  };

  ##### Idle #####
  # The lock screen itself is in lockscreen.nix.
  # Lock and screen-off times are per host (fox.desktop.lockAfter /
  # screenOffAfter): the laptop locks at 5 min and blanks at 5.5, the
  # desktop at 10 and 15. Separate from the laptop's 1h logind idle suspend
  # (modules/hardware/laptop.nix). Closing the lid suspends (logind
  # default); before_sleep_cmd locks first.
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "${pkgs.procps}/bin/pgrep -x hyprlock || ${pkgs.hyprlock}/bin/hyprlock";
        before_sleep_cmd = "${pkgs.systemd}/bin/loginctl lock-session";
        # Lua-config syntax: `hyprctl dispatch` takes an hl.dsp call now.
        # The old `hyprctl dispatch dpms on` fails silently under Lua.
        after_sleep_cmd = "${hyprctl} dispatch 'hl.dsp.dpms({ action = \"on\" })'";
      };
      listener = [
        {
          timeout = osConfig.fox.desktop.lockAfter;
          on-timeout = "${pkgs.systemd}/bin/loginctl lock-session";
        }
        {
          timeout = osConfig.fox.desktop.screenOffAfter;
          on-timeout = "${hyprctl} dispatch 'hl.dsp.dpms({ action = \"off\" })'";
          on-resume = "${hyprctl} dispatch 'hl.dsp.dpms({ action = \"on\" })'";
        }
      ];
    };
  };

  ##### Launcher #####
  programs.fuzzel = {
    enable = true;
    settings =
      let c = pal "fuzzel"; in {
        main = {
          font = "${font}:size=11";
          terminal = "ghostty -e";
          width = 40;
          lines = 12;
          horizontal-pad = 16;
          vertical-pad = 12;
        };
        border = {
          width = 2;
          radius = 6;
        };
        # fuzzel wants RRGGBBAA
        colors = {
          background = "${c.bg}f2";
          text = "${c.fg}ff";
          prompt = "${c.dim}ff";
          placeholder = "${c.dim}ff";
          input = "${c.fg}ff";
          match = "${c.fg}ff";
          selection = "${c.forest}ff";
          selection-text = "${c.fg}ff";
          selection-match = "${c.fg}ff";
          border = "${c.forest}ff";
        };
      };
  };

  ##### Notifications #####
  # Quickshell (quickshell.nix) is the notification daemon now: popups
  # top-right, chat messages collected in the bar's chat menu.

  ##### USB automount #####
  services.udiskie = {
    enable = true;
    automount = true;
    notify = true;
    tray = "never"; # mounts show up in yazi; no tray icon needed
  };
  # Home Manager binds udiskie to graphical-session.target. Pin it to the
  # Hyprland session like everything else here.
  systemd.user.services.udiskie = {
    Unit.PartOf = lib.mkForce [ target ];
    Unit.After = lib.mkForce [ target ];
    Install.WantedBy = lib.mkForce [ target ];
  };

  ##### Polkit agent (asks for your password when an app needs root) #####
  services.hyprpolkitagent.enable = true;

  home.packages = (with pkgs; [
    grim slurp wl-clipboard   # Super + Shift + S screenshot
    brightnessctl             # brightness keys
    playerctl                 # media keys
    pavucontrol               # audio mixer (bar volume right-click)
    bluetui                   # Bluetooth TUI (bar click)
  ]) ++ [ cheatsheet ];
}
