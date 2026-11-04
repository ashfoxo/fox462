# fox-green's network, as RackNerd set it up: a static IPv4 address, no DHCP,
# no IPv6 beyond link-local.
{ ... }:
{
  networking = {
    # The interface is eth0 today. Keep that name, or the static address
    # below would point at an interface that doesn't exist.
    usePredictableInterfaceNames = false;
    useDHCP = false;
    interfaces.eth0.ipv4.addresses = [{ address = "198.44.125.25"; prefixLength = 26; }];
    defaultGateway = { address = "198.44.125.1"; interface = "eth0"; };
    nameservers = [ "1.1.1.1" "9.9.9.9" ];
  };
}
