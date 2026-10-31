# The few things that differ between personal machines, as options.
# Defaults are the laptop's values, so a host only sets what's different.
# Home Manager modules read these through osConfig.fox.*.
{ lib, config, ... }:

let
  inherit (lib) mkOption types;
in
{
  options.fox = {
    machine = mkOption {
      type = types.str;
      default = config.networking.hostName;
      defaultText = "networking.hostName";
      description = ''
        This machine's name in the repo (hosts/<name>, the flake output,
        lib/syncthing.nix). Defaults to the network host name; set it when
        the two differ.
      '';
    };

    backup = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "Daily restic backup to Scaleway (services/restic.nix).";
      };
      repository = mkOption {
        type = types.str;
        description = "restic repository URL: bucket, then a folder named after the host.";
      };
      s3SecretPrefix = mkOption {
        type = types.str;
        default = "";
        description = ''
          Prefix for this host's Scaleway key names in secrets.yaml, for a
          host with its own API key: "fox-blue-" reads
          fox-blue-s3-access-key-id and fox-blue-s3-secret-access-key.
        '';
      };
      extraExclude = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Paths this host doesn't back up, on top of the shared list.";
      };
    };

    desktop = {
      monitors = mkOption {
        type = types.listOf (types.attrsOf types.anything);
        default = [ ];
        example = [
          { output = "DP-2"; mode = "3440x1440@59.97"; position = "0x0"; scale = 1; }
          { output = "DP-1"; disabled = true; }
        ];
        description = ''
          Extra hl.monitor() rules, one attrset per call, written verbatim as
          Lua tables after the catch-all rule. A rule for a named output
          beats the catch-all.
        '';
      };
      hyprlandEnv = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "Extra environment variables set inside Hyprland only.";
      };
      lockAfter = mkOption {
        type = types.int;
        default = 300;
        description = "Seconds idle before the screen locks.";
      };
      screenOffAfter = mkOption {
        type = types.int;
        default = 330;
        description = "Seconds idle before the screens turn off.";
      };
      barMonitors = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          Screens the Quickshell bar prefers, in order: a port name like
          "DP-2" or part of the monitor's description. Empty means the
          laptop panel, else the first screen.
        '';
      };
      lockMonitor = mkOption {
        type = types.str;
        default = "eDP-1";
        description = ''
          The screen the lock screen draws its clock and password prompt on.
          Every other screen gets the plain background.
        '';
      };
      barHost = mkOption {
        type = types.str;
        default = "ws";
        description = "Host name in the bar's prompt (arlo@<barHost>:~).";
      };
      sandboxGpuEnv = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = ''
          Extra environment variables for the nixpak sandboxes, for the GPU
          driver (e.g. where NVIDIA finds its EGL platform plugins).
        '';
      };
      sandboxGpuDevices = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = ''
          Extra GPU device nodes the nixpak sandboxes get, on top of
          /dev/dri. Missing ones are skipped (bwrap --dev-bind-try).
        '';
      };
    };
  };
}
