{ pkgs, lib, osConfig, ... }:

# The Hyprland lock screen (hyprlock): "terminal" layout.
#
#   Plain dark background, everything in JetBrains Mono, bottom-left:
#
#     22:47                  <- big clock, dim colon
#     sun 25 oct  [caps]     <- [caps] only while Caps Lock is on
#
#     ❯ █                    <- prompt; the block is the cursor
#
#   No name, no instructions, no status. States all happen after the ❯:
#     typing      ❯ • • • •
#     checking    ❯ ···       (teal: Enter pressed, touch the key)
#     wrong       ❯ ✕ 2       (rust, with the failed-attempt count)
#
#   Only the laptop screen shows text; every other monitor is plain
#   background. No animations: it cuts in and out.
#
# Unlock works as before: Enter, then touch the YubiKey, or type the
# password (PAM setup is in modules/desktop/session.nix).
#
# How the prompt works: "❯" is a label; everything after it is hyprlock's
# input field with its box made invisible (same color as the background).
# hyprlock centers the field's text in its box, so the cursor and messages
# are padded with no-break spaces until they start right after the ❯.
# Docs: https://wiki.hypr.land/Hypr-Ecosystem/hyprlock/

let
  c = (import ../../lib/palette.nix).for "hyprlock";

  # The screen that gets the text: the built-in panel on the laptop, set
  # per host with fox.desktop.lockMonitor. Check with `hyprctl monitors` if
  # the text doesn't show up; every other monitor gets the background only.
  screen = osConfig.fox.desktop.lockMonitor;

  font = "JetBrainsMono Nerd Font";

  # Sizes and spacing, in hyprlock units at monitor scale 1. The mockup was
  # drawn at 1280x800; these are it scaled for a ~1920px-wide screen.
  # If it all looks too big or small, change these numbers together.
  marginX = 168;     # left edge to the text
  marginY = 156;     # bottom edge to the prompt line
  clockSize = 153;   # big clock
  dateSize = 22;     # date line
  promptSize = 28;   # prompt line (keep even: the typing dots round to even sizes)

  # Text-grid numbers for promptSize 28, measured from a screenshot.
  charWidth = 23;    # width of one character
  promptLine = 49;   # height of one line

  # The input field's box: its text is drawn at height/4, so this makes the
  # field's text the same size as the ❯ label.
  fieldHeight = promptSize * 4;

  # No-break spaces. hyprlock trims normal spaces from the ends of settings.
  nbsp = builtins.fromJSON ''"\u00a0"'';
  pad = lib.concatStrings (lib.replicate 40 nbsp);
  # "##" is a literal # in hyprlock's config; a single # starts a comment.
  span = color: text: ''<span foreground="##${color}">${text}</span>${pad}'';

  # Big clock: bold hours and minutes, light dim colon, tightened a little.
  clock = lib.getExe (pkgs.writeShellApplication {
    name = "lock-clock";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      echo "<span letter_spacing=\"-6900\"><b>$(date +%H)</b><span weight=\"300\" foreground=\"#${c.dim}\">:</span><b>$(date +%M)</b></span>"
    '';
  });

  # "sun 25 oct", plus [caps] in teal while Caps Lock is on.
  date = lib.getExe (pkgs.writeShellApplication {
    name = "lock-date";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      caps=""
      for led in /sys/class/leds/*::capslock/brightness; do
        if [ -r "$led" ] && [ "$(cat "$led")" != "0" ]; then
          caps="  <span foreground=\"#${c.teal_text}\">[caps]</span>"
        fi
      done
      echo "$(date '+%a %-d %b' | tr '[:upper:]' '[:lower:]')$caps"
    '';
  });

  label = attrs: {
    monitor = screen;
    font_family = font;
    halign = "left";
    valign = "bottom";
    text_align = "left";
    zindex = 2; # above the input field's (invisible) box
  } // attrs;

  # Bottom edges of each line, stacked upward from the prompt.
  dateY = marginY + promptLine + 51;
  clockY = dateY + 40 + 15;
in
{
  fonts.fontconfig.enable = true;

  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        hide_cursor = true;
        ignore_empty_input = false; # an empty Enter starts the key-touch check
        immediate_render = true;    # draw at once instead of after fonts load
      };

      animations.enabled = false; # hard cut in and out

      background = [{
        monitor = "";
        color = "rgb(${c.bg})";
      }];

      label = [
        (label {
          text = "cmd[update:1000] ${clock}";
          font_size = clockSize;
          color = "rgb(${c.fg})";
          position = "${toString marginX}, ${toString clockY}";
        })
        (label {
          text = "cmd[update:1000] ${date}";
          font_size = dateSize;
          color = "rgb(${c.dim})";
          position = "${toString (marginX + 6)}, ${toString dateY}";
        })
        (label {
          text = "<b>❯</b>";
          font_size = promptSize;
          color = "rgb(${c.forest_text})";
          position = "${toString (marginX + 6)}, ${toString marginY}";
        })
      ];

      input-field = [{
        monitor = screen;
        # Wide enough for ~18 dots before they start scrolling.
        size = "900, ${toString fieldHeight}";
        halign = "left";
        valign = "bottom";
        # Centered on the prompt line, starting so its text lands two
        # characters after the ❯.
        position = "${toString (marginX + 6 + 2 * charWidth - fieldHeight / 2)}, ${toString (marginY + promptLine / 2 - fieldHeight / 2)}";
        rounding = 0;
        outline_thickness = 0;
        fade_on_empty = false;

        # The box is invisible: background color in every state (with no
        # outline, hyprlock tints the box itself for these).
        inner_color = "rgb(${c.bg})";
        check_color = "rgb(${c.bg})";
        fail_color = "rgb(${c.bg})";
        capslock_color = "rgb(${c.bg})";

        font_family = font;
        font_color = "rgb(${c.fg})";

        # Typing: dots one character apart, starting where the cursor was.
        # hyprlock starts dots half a line further left than other text, so
        # each dot carries a leading space to line up, and the negative
        # spacing overlaps those spaces to keep the dots one character apart.
        dots_text_format = "${nbsp}•";
        dots_size = "0.25"; # dot text = fieldHeight / 4 = promptSize
        dots_spacing = "-0.5";
        dots_center = false;

        placeholder_text = span c.fg "█";
        check_text = span c.teal_text "···";
        fail_text = span c.rust_text "✕ $ATTEMPTS";
        zindex = 1;
      }];
    };
  };
}
