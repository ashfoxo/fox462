#!/usr/bin/env bash
# Self-check for vm-clip.sh's window-to-VM mapping: bash scripts/vm-clip-test.sh
set -euo pipefail
c="$(dirname "$0")/vm-clip.sh"
fail=0
is() { got=$(bash "$c" domain "$2"); [ "$got" = "$1" ] && echo "ok    $1 <- '$2'" || { echo "FAIL  want $1, got $got for '$2'"; fail=1; }; }
is untrusted "[untrusted] Mullvad Browser"
is sys-net   "[sys-net] nmtui"
is host      "Mullvad Browser"
is host      "[Untrusted] caps are not a VM label"
is host      "[untrusted]no space after the label"
is host      ""
is host     " [untrusted] leading space"
export VM_CLIP_TRUSTED="personal"
is host      "[personal] LibreWolf"
is untrusted "[untrusted] still gated"
is personal-x "[personal-x] a name that only starts with a trusted one"
exit $fail
