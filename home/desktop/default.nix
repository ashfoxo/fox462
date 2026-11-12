{
  imports = [
    ./apps.nix
    ./dev.nix
    ./hyprland.nix   # compositor; Lua config lives in ./hypr/
    ./helpers.nix    # idle, wallpaper, launcher, automount
    ./lockscreen.nix # hyprlock
    ./quickshell.nix # bar and notifications
    ./webapps.nix    # sandboxed ungoogled-chromium web apps
    ./voicenotes.nix # Super + Shift + R: record and transcribe
    ./defaults.nix   # default apps (what opens links and files)
    ./theme.nix      # GTK, Qt and cursor look
    ./filen.nix
    ./gpg-unlock.nix # one YubiKey touch at login unlocks pass
    ./syncthing.nix  # Minecraft instances, synced over NetBird
    ./displays.nix   # Super + Shift + P: pick the main display
    ./health         # `health`: Gadgetbridge data as charts, no server
    ./copper.nix     # `copper pull` / `copper done`: fox-copper's DVD rips into Filen
    ./push.nix       # `push`: copy ~/drop to Filen with rclone, at full speed
  ];
}
