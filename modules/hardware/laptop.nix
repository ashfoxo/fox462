{ pkgs, ... }:
let
  # Suspend is allowed, by hand only, and for at most this long.
  maxSuspend = 3600;
  deadline = "/run/suspend-deadline";
  rtcwake = "${pkgs.util-linux}/bin/rtcwake";

  # Before every suspend: an RTC alarm maxSuspend from now, and the time it fires.
  arm = pkgs.writeShellScript "suspend-limit-arm" ''
    echo $(( $(date +%s) + ${toString maxSuspend} )) > ${deadline}
    ${rtcwake} -m no -s ${toString maxSuspend}
  '';

  # After every resume: woken by the alarm means nobody came back, so power off.
  # Otherwise clear the alarm, and make the lock screen want the password
  # (modules/desktop/session.nix).
  check = pkgs.writeShellScript "suspend-limit-check" ''
    [ -e ${deadline} ] || exit 0
    due=$(cat ${deadline}); rm -f ${deadline}
    # 60 s of slack: the RTC and the clock don't agree to the second.
    if [ "$(date +%s)" -ge $(( due - 60 )) ]; then
      exec ${pkgs.systemd}/bin/systemctl poweroff --force
    fi
    ${rtcwake} -m disable || true
    uid=$(${pkgs.coreutils}/bin/id -u arlo)
    if [ -d /run/user/$uid ]; then
      install -o arlo -m 0600 /dev/null /run/user/$uid/password-only
    fi
  '';
in
{
  # Things that only make sense on a machine that travels. Idle and the lid
  # power off, because a suspended machine keeps the disk key in RAM and there
  # is no swap to hibernate to. Suspend from the power menu is the one
  # exception, and it powers off by itself after maxSuspend.
  services.logind.settings.Login = {
    IdleAction = "poweroff";
    IdleActionSec = "1h";
    HandleLidSwitch = "poweroff";
    HandleLidSwitchExternalPower = "poweroff";
  };

  systemd.sleep.settings.Sleep = {
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  };

  systemd.services.suspend-limit-arm = {
    description = "Wake and power off ${toString maxSuspend}s after suspend";
    wantedBy = [ "suspend.target" ];
    before = [ "systemd-suspend.service" ];
    serviceConfig = { Type = "oneshot"; ExecStart = arm; };
  };
  systemd.services.suspend-limit-check = {
    description = "Power off if the suspend limit woke the machine";
    wantedBy = [ "suspend.target" ];
    after = [ "systemd-suspend.service" ];
    serviceConfig = { Type = "oneshot"; ExecStart = check; };
  };

  services.thermald.enable = true;  # Intel thermal management
}
