{ pkgs, config, ... }:

# How apps look outside the compositor: GTK, Qt and the mouse cursor, all
# dark and coloured from lib/palette.nix where the toolkit allows it.
#
#   GTK   Adwaita-dark, plus the "prefer dark" setting that the GTK portal
#         passes on to browsers, Electron and libadwaita apps.
#   Qt    qt5ct / qt6ct with the Fusion style and a colour scheme made from
#         the palette (fox.conf below). Hyprland points Qt at them
#         (QT_QPA_PLATFORMTHEME in hyprland.nix).
#   Icons Breeze, for kdenlive and other Qt apps that expect its icon names.
#   Cursor Bibata Modern Classic. hyprland.nix reads it from here.
#
# Sandboxed apps (sandboxes.nix) force GTK_THEME=Adwaita:dark themselves and
# find the cursor through the per-user profile.

let
  c = (import ../../lib/palette.nix).for "quickshell";  # base + faint/line

  # Qt colour scheme: one colour per palette role, in Qt's fixed order:
  # WindowText, Button, Light, Midlight, Dark, Mid, Text, BrightText,
  # ButtonText, Base, Window, Shadow, Highlight, HighlightedText, Link,
  # LinkVisited, AlternateBase, NoRole, ToolTipBase, ToolTipText,
  # PlaceholderText.
  roles = { text, muted }: builtins.concatStringsSep ", " (map (x: "#${x}") [
    text     # WindowText
    c.surf   # Button
    c.line   # Light
    c.line   # Midlight
    "0B100D" # Dark: a shade below bg
    c.line   # Mid
    text     # Text
    "FFFFFF" # BrightText
    text     # ButtonText
    c.bg     # Base: text fields, lists
    c.surf   # Window
    "000000" # Shadow
    c.forest # Highlight: selection
    c.fg     # HighlightedText
    c.teal_text   # Link
    c.forest_text # LinkVisited
    "18201C" # AlternateBase: every other list row, between bg and surf
    c.bg     # NoRole
    c.surf   # ToolTipBase
    c.fg     # ToolTipText
    muted    # PlaceholderText
  ]);

  colorScheme = ''
    [ColorScheme]
    active_colors=${roles { text = c.fg; muted = c.dim; }}
    inactive_colors=${roles { text = c.fg; muted = c.dim; }}
    disabled_colors=${roles { text = c.faint; muted = c.faint; }}
  '';

  qtct = name: {
    Appearance = {
      style = "Fusion";
      custom_palette = true;
      color_scheme_path = "${config.xdg.configHome}/${name}/colors/fox.conf";
      icon_theme = "breeze-dark";
      standard_dialogs = "default";
    };
  };
in
{
  ##### Cursor #####
  home.pointerCursor = {
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Classic";
    size = 24;
    gtk.enable = true;
  };

  ##### GTK #####
  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    gtk3.extraConfig = {
      gtk-application-prefer-dark-theme = 1;
      gtk-recent-files-enabled = false;   # no "recent files" list
    };
    gtk4.extraConfig.gtk-recent-files-enabled = false;
  };

  # GTK 4 / libadwaita apps, and the GTK portal's dark-mode answer to every
  # other app, read these instead of the files above.
  dconf.settings."org/gnome/desktop/interface" = {
    color-scheme = "prefer-dark";
    gtk-theme = "Adwaita-dark";
    cursor-theme = config.home.pointerCursor.name;
    cursor-size = config.home.pointerCursor.size;
  };
  dconf.settings."org/gnome/desktop/privacy".remember-recent-files = false;

  ##### Qt #####
  qt = {
    enable = true;
    platformTheme.name = "qtct";   # installs qt5ct and qt6ct
    qt5ctSettings = qtct "qt5ct";
    qt6ctSettings = qtct "qt6ct";
  };
  xdg.configFile."qt5ct/colors/fox.conf".text = colorScheme;
  xdg.configFile."qt6ct/colors/fox.conf".text = colorScheme;

  home.packages = [ pkgs.kdePackages.breeze-icons ];
}
