#!/usr/bin/env bash
# Lets a VM's window connection through to its waypipe listener, but only if it
# really comes from that VM. Without this, any VM could connect to another VM's
# port and draw windows with that VM's label and border colour.
# Run by a systemd socket unit with Accept=yes (modules/vms.nix), the
# connection on stdin/stdout.
#   $1  systemd's instance name for the connection: <n>-<host CID>:<port>-<peer CID>:<port>
#       The host kernel fills in the peer CID; a VM can't fake it.
#   $2  the only CID allowed through
#   $3  waypipe's Unix socket
set -euo pipefail
peer=${1##*-}
peer=${peer%%:*}
if [ "$peer" != "$2" ]; then
  echo "refused a connection from CID '$peer': only CID $2 may use this port" >&2
  exit 1
fi
exec socat STDIO "UNIX-CONNECT:$3"
