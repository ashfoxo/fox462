{ config, pkgs, ... }:
let
  # Shared with home/default.nix and hyprland.nix. Edit lib/session-vars.nix.
  sessionVars = import ../../lib/session-vars.nix;

  startHyprland = "${config.programs.hyprland.package}/bin/start-hyprland";
in
{
  ##### Login #####
  # greetd starts Hyprland as arlo at boot, and Hyprland locks itself
  # straight away (hyprland.nix), so the lock screen is the real login.
  # initial_session runs once per boot. After a log out, or if Hyprland
  # exits, default_session shows a text login (tuigreet) that starts
  # Hyprland again.
  services.greetd = {
    enable = true;
    settings = {
      initial_session = {
        command = startHyprland;
        user = "arlo";
      };
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --asterisks --cmd ${startHyprland}";
        user = "greeter";
      };
    };
  };

  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  ##### Desktop services the bar relies on #####
  services.upower.enable = true;                # the bar's battery
  services.power-profiles-daemon.enable = true; # the bar's power profile button

  # Portals: Hyprland's own for screenshots and screencast, GTK's for file
  # pickers (Hyprland's has none) and for telling apps to use dark mode
  # (read from the color-scheme setting in home/desktop/theme.nix). Your
  # nixpak apps open files through the FileChooser portal, so this matters.
  xdg.portal = {
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config.hyprland = {
      default = [ "hyprland" "gtk" ];
      "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
    };
  };

  # PAM services
  # hyprlock: touch a YubiKey to unlock (u2f is "sufficient", same as sudo).
  # Typing your password still works as a fallback. GPG is unlocked by a
  # YubiKey touch at login, not the login password (home/desktop/gpg-unlock.nix).
  # (The u2f and sudo settings themselves are in core/hardening.nix.)
  security.pam.services.hyprlock = {
    u2fAuth = true;
    # A touch only works in the first 10 minutes of a lock, and never after a
    # resume from suspend; otherwise only the password. The lock start time
    # and the flag are written by home/desktop/lock-screen.nix and
    # modules/hardware/laptop.nix. The check fails -> pam skips the u2f line.
    rules.auth.touch-window = {
      order = config.security.pam.services.hyprlock.rules.auth.u2f.order - 100;
      control = "[success=ignore default=1]";
      modulePath = "${pkgs.linux-pam}/lib/security/pam_exec.so";
      args = [ "quiet" "${pkgs.writeShellScript "touch-allowed" ''
        PATH=${pkgs.coreutils}/bin
        run=/run/user/$(id -u "$PAM_USER")
        [ ! -e "$run/password-only" ] || exit 1
        at=$(cat "$run/locked-at" 2>/dev/null) || exit 1
        [ $(( $(date +%s) - at )) -le 600 ]
      ''}" ];
    };
  };
  environment.sessionVariables = sessionVars;
}
