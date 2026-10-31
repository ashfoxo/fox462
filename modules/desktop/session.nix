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
  # hyprlock: touch yak-olive to unlock (u2f is "sufficient", same as sudo).
  # Typing your password still works as a fallback, and a typed password
  # also unlocks GPG via pam_gnupg. A touch can't unlock GPG, so after a
  # touch unlock, pass / Bitwarden ask for the GPG passphrase themselves.
  # (The u2f and sudo settings themselves are in core/hardening.nix.)
  security.pam.services.hyprlock = {
    u2fAuth = true;
    gnupg.enable = true;
  };
  # A password typed at tuigreet unlocks GPG too. (The boot-time automatic
  # login types none, so there the hyprlock unlock does it.)
  security.pam.services.greetd.gnupg.enable = true;

  environment.sessionVariables = sessionVars;
}
