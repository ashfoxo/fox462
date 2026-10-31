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
# fox-amber dials it and fox-blue only accepts.
#
# Only NetBird is used: no LAN discovery, no global discovery, no relays.
{
  fox-amber = {
    id = "HKKMYM6-CYFPSSJ-NB2EQX7-XOS2TP7-N5ZPRFZ-F5TYIY7-QYKV3GE-SRLDTAJ";
    address = ""; # it dials fox-blue; its NetBird IP is 100.73.113.106
  };
  fox-blue = {
    id = "TQSKPYI-PE26SDB-2ILNBQB-ZYKH3AR-U4ACAGE-M7DBQHZ-6DRQVBN-WAEADQ3";
    address = "100.73.59.52";
  };
}
