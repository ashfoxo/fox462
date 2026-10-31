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
    ./syncthing.nix  # Minecraft instances, synced over NetBird
  ];
}
