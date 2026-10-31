# Single source of truth for colors. Plain attrset, like session-vars.nix.
#
# Usage in any module:
#   colors = (import ../../lib/palette.nix).for "fuzzel";
#   colors.forest   # -> "255C2B"
#
# Values are bare hex (no #). Each consumer adds whatever wrapper its format
# wants ("#255C2B" for CSS, "rgb(255C2B)" for hypr*, "255C2Bff" for fuzzel).
#
# Contrast notes (checked against WCAG):
#   - fg on forest / teal / rust: 6:1 or better, so the accents work as
#     *backgrounds* behind fg text (bar pills, selected items).
#   - forest / teal / rust on bg: 1.5-2.2:1. Too dark for text. Use them
#     for borders and fills only, never as text color on bg.
#   - The *_text colors and amber are the light versions for text and icons
#     on bg (6:1 or better).
rec {
  base = {
    # Accents
    forest = "255C2B"; # primary: active border, focused workspace, selection
    teal   = "25565C"; # secondary: hover, inactive-but-notable, bar modules
    rust   = "5C2B25"; # alert: urgent, low battery, critical notifications

    # Text versions of the accents, light enough to read on bg
    forest_text = "6FB57A"; # on / connected
    teal_text   = "74B6BE"; # notable: counts, do not disturb
    rust_text   = "E0866F"; # something's wrong
    amber       = "D9A85B"; # heads-up: needs attention soon

    # Neutrals (green-tinted so they sit with the accents)
    bg     = "131A16"; # base background
    surf   = "1C2621"; # raised surfaces: bar, popups, inactive borders
    fg     = "E6E1D6"; # main text (warm off-white)
    dim    = "9AA59C"; # secondary text, placeholders
  };

  # Per-app overrides. Each attrset is merged over `base`, so list only the
  # keys that change. For a completely different palette, give every key.
  #   fuzzel = { forest = "2E7036"; };
  apps = {
    hyprland = { };
    fuzzel   = { };
    zathura  = { };
    # Lock screen extra: a brighter rust for the failed-unlock border.
    hyprlock = {
      rust_glow = "9A4637";
    };
    # Bar extras: a grey between dim and bg for things that are off, and a
    # border for outlined buttons in the dropdowns.
    quickshell = {
      faint = "87938A";
      line  = "3A463F";
    };
  };

  for = app: base // (apps.${app} or { });
}
