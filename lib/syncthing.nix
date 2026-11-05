# Syncthing devices, by machine name (fox.machine: the hosts/<name> folder).
# Plain attrset, like palette.nix.
#
#   id       the device ID: `syncthing cli show system | grep myID` on that
#            machine (or Actions > Show ID in the web UI, localhost:8384).
#            Not secret. Left empty, the machine is skipped.
#   address  where the others reach it: its NetBird IP
#            (`netbird-wt0 status | grep 'NetBird IP'`, without the /16),
#            or "" if the others should wait for it to call them instead.
#   folders  which shared folders it has (the folder IDs below).
#   onlyWith optional: the only machines it pairs with; the others leave it
#            out entirely. Unset, it pairs with every device that shares a
#            folder with it.
#
# Folders:
#   minecraft-instances  Prism Launcher's instances (home/desktop/syncthing.nix)
#   sync                 ~/sync: anything to have on every device. On the
#                        phone it's "sync" in internal storage.
#
# Only ONE of a pair may have an address the other dials. If both dial at
# once, port 22000 to port 22000, TCP can merge the two attempts into one
# connection where both sides think they called ("simultaneous open"), and
# Syncthing fails with "unexpected handshake message of type
# *tls.clientHelloMsg". fox-blue stays home and is always reachable, so
# fox-amber dials it and fox-blue only accepts. fox-red is always on, so both
# dial it and it dials nobody (its config ignores the addresses below,
# see modules/server/services/syncthing.nix). That way the laptop and the desktop
# sync through fox-red even when they're never on together.
#
# The phone has no address: it dials all three (set up by hand in
# Syncthing-Fork, which has no Nix config) and they only accept. It syncs
# with whichever are on: the computers directly when they're around, fox-red
# always.
#
# Only NetBird is used: no LAN discovery, no global discovery, no relays.
{
  fox-amber = {
    id = "HKKMYM6-CYFPSSJ-NB2EQX7-XOS2TP7-N5ZPRFZ-F5TYIY7-QYKV3GE-SRLDTAJ";
    address = "";
    folders = [ "minecraft-instances" "sync" ];
  };
  fox-blue = {
    id = "TQSKPYI-PE26SDB-2ILNBQB-ZYKH3AR-U4ACAGE-M7DBQHZ-6DRQVBN-WAEADQ3";
    address = "100.73.59.52";
    folders = [ "minecraft-instances" "sync" ];
  };
  fox-red = {
    id = "KPXV26X-WCTDXXJ-O5YC6UW-QXPPLWN-4SSMULV-RHN3B4Z-BA5XE6Q-C4DAHQ6";
    address = "100.73.156.82";
    folders = [ "minecraft-instances" "sync" ];
  };
  # The Pixel, running Syncthing-Fork. It dials the others, so no address.
  phone = {
    id = "FAJFOET-4GCQBRZ-A3YYZ4P-HRMOEFN-LDSL3CL-BDRVOAE-4BULMV6-WTNPTAT";
    address = "";
    folders = [ "sync" ];
  };
}
