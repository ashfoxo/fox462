# Scratchpads: hidden workspaces that slide over whatever you're on.
# Plain list, like session-vars.nix. One place for all of them:
#   - hyprland.nix writes it to ~/.config/hypr/arlo/scratchpads.lua, which
#     binds.lua (the keys) and rules.lua (the window rules) read
#   - quickshell.nix passes it to the bar (the tags and the chat menu)
#
# Fields:
#   name   the scratchpad, and its tag on the bar
#   key    Super + key
#   class  window class, as a regex that must match the whole class
#          (hyprctl clients shows it)
#   title  optional: window title regex, for apps with no usable class
#   cmd    how to start it; pressing the key starts it if it isn't running
#   size   optional: part of the screen it takes, 0.75 if left out
#   autostart  optional: start it hidden at login (chat apps always do)
#
# Chat apps (chat = true) also start hidden at login, sit behind the bar's
# chat menu instead of each getting a tag, and have their notifications
# collected there. `notify` matches their notifications' app name (regex,
# any case); `notifyBody` matches the text instead, for web apps, whose
# notifications all come from "Chromium" with the site on the first line.
[
  { name = "term";  key = "grave"; class = "^dev\\.arlo\\.scratchterm$";
    cmd = "ghostty --class=dev.arlo.scratchterm --gtk-single-instance=false"; }
  { name = "vault"; key = "B"; class = "^bitwarden$"; cmd = "bitwarden"; }
  { name = "music"; key = "M"; class = "^feishin$";   cmd = "feishin"; }
  { name = "notes"; key = "N"; class = "^Notesnook$"; cmd = "notesnook"; autostart = true; }
  { name = "files"; key = "E"; class = "^dev\\.arlo\\.files$";
    cmd = "ghostty --class=dev.arlo.files --gtk-single-instance=false -e yazi"; }
  { name = "top";   key = "P"; class = "^dev\\.arlo\\.top$"; size = 0.9;
    cmd = "ghostty --class=dev.arlo.top --gtk-single-instance=false -e btop"; }
  { name = "torrent"; key = "D"; class = "^org\\.qbittorrent\\.qBittorrent$"; cmd = "qbittorrent"; }
  # Tuta web app (webapps.nix), matched on its site.
  { name = "mail"; key = "T"; class = ".*app\\.tuta\\.com.*"; cmd = "webapp-tuta"; }

  { name = "signal";  chat = true; key = "S"; class = "^signal$";  cmd = "signal-desktop";  notify = "^signal"; }
  # Matrix: Telegram, Discord DMs, Instagram and Google Messages come in
  # through the bridges on fox-red, so they have no apps of their own here.
  { name = "element"; chat = true; key = "C"; class = "^element-desktop$"; cmd = "element-desktop"; notify = "element"; }
]
