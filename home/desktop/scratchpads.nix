# Scratchpads: hidden workspaces that slide over whatever you're on.
# Plain list, like session-vars.nix. One place for all of them:
#   - hyprland.nix writes it to ~/.config/hypr/arlo/scratchpads.lua, which
#     binds.lua (the keys) and rules.lua (the window rules) read
#   - quickshell.nix passes it to the bar (the tags and the chat menu)
#
# Fields:
#   name   the scratchpad, and its tag on the bar
#   key    normal ones: Super + key. Chat ones: Super + C, then key.
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

  { name = "signal";   chat = true; key = "S"; class = "^signal$"; cmd = "signal-desktop"; notify = "^signal"; }
  # Telegram's sandbox leaves its class empty, so it's matched by title.
  { name = "telegram"; chat = true; key = "T"; class = "^$"; title = "^Telegram"; cmd = "Telegram"; notify = "telegram"; }
  { name = "discord";  chat = true; key = "D"; class = "^vesktop$"; cmd = "vesktop"; notify = "vesktop|discord"; }
  # Google Messages web app (webapps.nix); Chromium names its window after
  # the site, e.g. chrome-messages.google.com__web-Default.
  { name = "messages"; chat = true; key = "M"; class = ".*messages\\.google\\.com.*"; cmd = "webapp-messages"; notifyBody = "messages\\.google\\.com"; }
]
