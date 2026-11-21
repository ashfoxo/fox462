#!/usr/bin/env bash
# Qubes-style clipboard for the VMs (modules/vms.nix). A VM sees only what you
# hand it, and the host gets only what you take from a VM:
#   vm-clip watch   (user service) focus moves into a VM window: the host's
#                   clipboard is put aside and the clipboard emptied. Back to a
#                   host window: it's put back, and whatever the VM copied is
#                   dropped.
#   vm-clip copy    (Super+Shift+C in a VM window) this VM's clipboard becomes
#                   the one put aside, so host windows get it.
#   vm-clip paste   (Super+Shift+V in a VM window) the one put aside is offered
#                   to this VM until focus leaves it; paste with Ctrl+V.
#   vm-clip domain <title>   which VM a window title belongs to (for the test).
# shortcut: text only; images and files don't cross. Extend copy/paste with
# wl-paste --type if you need them.
# shortcut: Wayland already hides the clipboard from unfocused windows; a VM
# that grabs it the instant it's focused can still beat `watch` to it.
set -euo pipefail

# The VM's name for "[vm] ..." titles (added by the host's waypipe), else host.
# VMs in VM_CLIP_TRUSTED (space-separated) share the host clipboard: "host".
domain() {
  if [[ $1 =~ ^\[([a-z0-9-]+)\]\  ]] && [[ " ${VM_CLIP_TRUSTED:-} " != *" ${BASH_REMATCH[1]} "* ]]; then
    echo "${BASH_REMATCH[1]}"
  else
    echo host
  fi
}

dir=${XDG_RUNTIME_DIR:-/tmp}/vm-clip
saved=$dir/saved
focused() { domain "$(hyprctl activewindow -j | jq -r '.title // ""')"; }

case ${1:-} in
  domain) domain "${2:-}" ;;
  copy)
    d=$(focused); [ "$d" = host ] && exit 0
    mkdir -p "$dir" && chmod 700 "$dir"
    wl-paste -n > "$saved" 2>/dev/null || : > "$saved"
    notify-send "Clipboard" "Copied from $d: host windows can paste it now." ;;
  paste)
    d=$(focused); [ "$d" = host ] && exit 0
    if [ -s "$saved" ]; then
      wl-copy < "$saved"
      notify-send "Clipboard" "Ready to paste into $d with Ctrl+V."
    fi ;;
  watch)
    mkdir -p "$dir" && chmod 700 "$dir"
    sig=${HYPRLAND_INSTANCE_SIGNATURE:-}
    if [ -z "$sig" ]; then for s in "$XDG_RUNTIME_DIR"/hypr/*/; do sig=$(basename "$s"); break; done; fi
    prev=host
    socat -u "UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$sig/.socket2.sock" - | while IFS= read -r line; do
      [[ $line == "activewindow>>"* ]] || continue
      title=${line#activewindow>>}
      title=${title#*,}               # "class,title"
      d=$(domain "$title")
      [ "$d" = "$prev" ] && continue
      if [ "$prev" = host ]; then wl-paste -n > "$saved" 2>/dev/null || : > "$saved"; fi
      if [ "$d" = host ]; then
        if [ -s "$saved" ]; then wl-copy < "$saved"; else wl-copy --clear; fi
      else
        wl-copy --clear
        wl-copy --primary --clear
      fi
      prev=$d
    done ;;
  *) echo "usage: vm-clip watch|copy|paste|domain <title>" >&2; exit 2 ;;
esac
