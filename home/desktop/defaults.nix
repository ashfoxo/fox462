{ pkgs, lib, ... }:

# Default apps: what opens when you click a link or a file (xdg-open,
# links in other apps). Writes ~/.config/mimeapps.list.
#
# The viewers are keyboard-driven:
#   zathura  PDFs    j/k scroll, / search, + - zoom, Ctrl + R dark pages
#   imv      images  arrows next/prev in the folder, + - zoom, f fullscreen
#   mpv      media   space pause, arrows seek, [ ] speed
#   yazi     files   hjkl move, enter open, q quit (also Super + E, a
#                    scratchpad: scratchpads.nix)
# Archives have no default: unpack them in the terminal.
# VLC stays installed as a backup player (apps.nix), not as a default.
#
# Check what opens a file type:  xdg-mime query default application/pdf
# Find a type for a file:        xdg-mime query filetype somefile.pdf

let
  c = (import ../../lib/palette.nix).for "zathura";

  browser = "mullvad-browser.desktop";
  # zathura's PDF support is a plugin with its own entry; same zathura.
  pdf     = "org.pwmt.zathura-pdf-mupdf.desktop";
  image   = "imv-dir.desktop";   # opens the whole folder: arrows flip through it
  media   = "mpv.desktop";
  text    = "codium.desktop";
  folder  = "yazi-folder.desktop";   # defined below

  # One app for a whole list of file types.
  forAll = app: types: lib.genAttrs types (_: app);
in
{
  programs.imv.enable = true;
  programs.mpv.enable = true;
  programs.yazi.enable = true;

  # Your colours around the page; the pages themselves keep their own
  # colours. Ctrl + R toggles dark pages, drawn in the same palette.
  programs.zathura = {
    enable = true;
    options = {
      default-bg = "#${c.bg}";
      default-fg = "#${c.fg}";
      statusbar-bg = "#${c.surf}";
      statusbar-fg = "#${c.fg}";
      inputbar-bg = "#${c.bg}";
      inputbar-fg = "#${c.fg}";
      notification-bg = "#${c.surf}";
      notification-fg = "#${c.fg}";
      notification-error-bg = "#${c.rust}";
      notification-error-fg = "#${c.fg}";
      notification-warning-bg = "#${c.surf}";
      notification-warning-fg = "#${c.amber}";
      completion-bg = "#${c.surf}";
      completion-fg = "#${c.fg}";
      completion-highlight-bg = "#${c.forest}";
      completion-highlight-fg = "#${c.fg}";
      highlight-color = "rgba(111,181,122,0.4)";         # forest_text, see-through
      highlight-active-color = "rgba(217,168,91,0.5)";   # amber, see-through
      index-bg = "#${c.bg}";
      index-fg = "#${c.fg}";
      index-active-bg = "#${c.forest}";
      index-active-fg = "#${c.fg}";

      recolor = false;               # pages in their normal colours
      recolor-darkcolor = "#${c.fg}";
      recolor-lightcolor = "#${c.bg}";
      recolor-keephue = true;        # keep images and coloured text recognisable
    };
  };

  # Opening a folder from another app ("show in folder" and so on): yazi at
  # that folder, in its own ghostty window. yazi's own entry asks for "a
  # terminal", which apps outside a full desktop often can't find, so this
  # names ghostty outright. Its class differs from the files scratchpad's,
  # so it opens as a normal window instead of being pulled into the pad.
  xdg.desktopEntries.yazi-folder = {
    name = "yazi (ghostty)";
    comment = "Open a folder in yazi";
    exec = "ghostty --class=dev.arlo.yazi --gtk-single-instance=false -e yazi %f";
    terminal = false;
    mimeType = [ "inode/directory" ];
    noDisplay = true;   # the launcher already has yazi; this is only for opening folders
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications =
      forAll browser [
        "x-scheme-handler/http"
        "x-scheme-handler/https"
        "text/html"
        "application/xhtml+xml"
      ]
      // forAll pdf [ "application/pdf" ]
      // forAll image [
        "image/png"
        "image/jpeg"
        "image/gif"
        "image/webp"
        "image/avif"
        "image/heic"
        "image/bmp"
        "image/tiff"
        "image/svg+xml"
      ]
      // forAll media [
        "video/mp4"
        "video/x-matroska"
        "video/webm"
        "video/quicktime"
        "video/x-msvideo"
        "audio/mpeg"
        "audio/ogg"
        "audio/opus"
        "audio/flac"
        "audio/x-wav"
        "audio/mp4"
        "audio/aac"
      ]
      // forAll text [
        "text/plain"
        "text/x-shellscript"
        "text/x-python"
        "text/x-csrc"
        "application/json"
        "application/x-yaml"
        "application/toml"
        "text/x-nix"
      ]
      // forAll "typora.desktop" [ "text/markdown" ]
      // forAll "writer.desktop" [
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        "application/msword"
        "application/vnd.oasis.opendocument.text"
        "application/rtf"
      ]
      // forAll "calc.desktop" [
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        "application/vnd.ms-excel"
        "application/vnd.oasis.opendocument.spreadsheet"
        "text/csv"
      ]
      // forAll "impress.desktop" [
        "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        "application/vnd.ms-powerpoint"
        "application/vnd.oasis.opendocument.presentation"
      ]
      // forAll folder [ "inode/directory" ]
      // forAll "webapp-tuta.desktop" [ "x-scheme-handler/mailto" ];
  };

  # Apps (browsers, file managers) rewrite mimeapps.list when you pick "always open
  # with". This file is the source of truth, so overwrite their changes on
  # rebuild instead of failing over a stale mimeapps.list.hm-backup. To keep
  # a default you set by clicking, add it above.
  xdg.configFile."mimeapps.list".force = true;

  # KDE apps (kdenlive) find installed apps through a menu file that only a
  # KDE desktop provides, so without one they think nothing can open
  # anything ("no default program"). This is the plain menu they look for:
  # every installed app, no categories. If kdenlive still shows nothing
  # after a rebuild, run `kbuildsycoca6` once.
  xdg.configFile."menus/applications.menu".text = ''
    <!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
      "http://www.freedesktop.org/standards/menu-spec/1.0/menu.dtd">
    <Menu>
      <Name>Applications</Name>
      <DefaultAppDirs/>
      <DefaultDirectoryDirs/>
      <Include><All/></Include>
    </Menu>
  '';
}
