# Syncthing devices, by machine name (fox.machine: the hosts/<name> folder).
# Plain attrset, like palette.nix.
#
#   id       the device ID: `syncthing cli show system | grep myID` on that
#            machine (or Actions > Show ID in the web UI, localhost:8384).
#            Not secret. Left empty, the machine is skipped.
#   address  where the others reach it: its NetBird IP
#            (`netbird-wt0 status | grep 'NetBird IP'`, without the /16),
#            or "" if the others should wait for it to call them instead.
#
# Only ONE of a pair may have an address the other dials. If both dial at
# once, port 22000 to port 22000, TCP can merge the two attempts into one
# connection where both sides think they called ("simultaneous open"), and
# Syncthing fails with "unexpected handshake message of type
# *tls.clientHelloMsg". fox-blue stays home and is always reachable, so
# fox-amber dials it and fox-blue only accepts. fox-red is always on, so both
# dial it and it dials nobody (its config ignores the addresses below,
# see hosts/fox-red/configuration.nix). That way the laptop amd the desktop
# sync through fox-red even when they're never on together.
#
# Only NetBird is used: no LAN discovery, no global discovery, no relays.
{
  fox-amber = {
    id = "HKKMYM6-CYFPSSJ-NB2EQX7-XOS2TP7-N5ZPRFZ-F5TYIY7-QYKV3GE-SRLDTAJ";
    address = "";
  };
  fox-blue = {
    id = "TQSKPYI-PE26SDB-2ILNBQB-ZYKH3AR-U4ACAGE-M7DBQHZ-6DRQVBN-WAEADQ3";
    address = "100.73.59.52";
  };
  fox-red = {
    id = "KPXV26X-WCTDXXJ-O5YC6UW-QXPPLWN-4SSMULV-RHN3B4Z-BA5XE6Q-C4DAHQ6";
    address = "100.73.156.82";
  };
}
