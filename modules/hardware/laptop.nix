{
  # Things that only make sense on a machine that travels. It powers off
  # instead of suspending: suspend-to-RAM leaves the disk key in memory, and
  # there is no swap to hibernate to.
  services.logind.settings.Login = {
    IdleAction = "poweroff";
    IdleActionSec = "1h";
    HandleLidSwitch = "poweroff";
    HandleLidSwitchExternalPower = "poweroff";
  };

  services.thermald.enable = true;  # Intel thermal management
}
