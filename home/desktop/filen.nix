{ pkgs, ... }: {
  # Filen desktop client. Packaged in nixpkgs from the upstream AppImage, so
  # this is the same Electron app as on any other distro -- same UI, same login,
  # same sync and mount tabs.

  home.packages = with pkgs; [
    filen-desktop

    # Optional CLI. Useful for scripted uploads and for checking sync state
    # without opening the GUI. Comment out if `nix search` does not find it.
    # filen-cli
  ];

  systemd.user.services.filen-desktop = {
    Unit = {
      Description = "Filen Desktop";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];

      # ADDED. Restart=on-failure plus a bad ExecStart is an infinite loop:
      # a start-limit-hit unit is loud in the journal and stops; a bare
      # restart loop just quietly eats CPU every 10s forever. These make it
      # give up after 5 tries in 5 minutes so you actually find out.
      StartLimitIntervalSec = 300;
      StartLimitBurst = 5;
    };
    Service = {
      ExecStart = "${pkgs.filen-desktop}/bin/filen-desktop";
      Restart = "on-failure";
      RestartSec = 10;
    };
    # graphical-session.target: starts with whatever graphical session you
    # log into, not only Hyprland.
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
