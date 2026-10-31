# qutebrowser config. Baked into the sandboxed package by sandboxes.nix
# (the sandbox can't see ~/.config), so edit this file and rebuild.
#
# Settings reference: https://qutebrowser.org/doc/help/settings.html
# Inside qutebrowser:  :help   or press  ?  ... most-used keys:
#   o / O        open URL in this tab / new tab
#   f / F        follow link (hints) in this tab / new tab
#   H / L        back / forward
#   J / K        previous / next tab
#   d / u        close tab / undo close
#   / then n     search page, next match
#   :            command line (tab-complete everything)

# pylint: disable=undefined-variable
config.load_autoconfig(False)  # ignore settings changed via :set; this file wins

# --- Colors (palette.nix) -------------------------------------------------
bg     = "#131A16"
surf   = "#1C2621"
fg     = "#E6E1D6"
dim    = "#9AA59C"
forest = "#255C2B"
teal   = "#25565C"
rust   = "#5C2B25"

c.colors.webpage.preferred_color_scheme = "dark"

c.colors.statusbar.normal.bg = surf
c.colors.statusbar.normal.fg = fg
c.colors.statusbar.insert.bg = forest
c.colors.statusbar.insert.fg = fg
c.colors.statusbar.command.bg = bg
c.colors.statusbar.command.fg = fg
c.colors.statusbar.passthrough.bg = teal
c.colors.statusbar.url.fg = fg
c.colors.statusbar.url.success.https.fg = dim

c.colors.tabs.bar.bg = bg
c.colors.tabs.even.bg = surf
c.colors.tabs.odd.bg = surf
c.colors.tabs.even.fg = dim
c.colors.tabs.odd.fg = dim
c.colors.tabs.selected.even.bg = forest
c.colors.tabs.selected.odd.bg = forest
c.colors.tabs.selected.even.fg = fg
c.colors.tabs.selected.odd.fg = fg

c.colors.hints.bg = forest
c.colors.hints.fg = fg
c.colors.hints.match.fg = dim
c.hints.border = "1px solid " + bg

c.colors.completion.fg = fg
c.colors.completion.odd.bg = bg
c.colors.completion.even.bg = surf
c.colors.completion.category.bg = teal
c.colors.completion.category.fg = fg
c.colors.completion.item.selected.bg = forest
c.colors.completion.item.selected.fg = fg
c.colors.completion.item.selected.border.top = forest
c.colors.completion.item.selected.border.bottom = forest
c.colors.completion.match.fg = "#6FB57A"

c.colors.messages.error.bg = rust
c.colors.messages.error.border = rust
c.colors.messages.info.bg = surf

c.fonts.default_family = "JetBrainsMono Nerd Font"
c.fonts.default_size = "11pt"

# --- Privacy --------------------------------------------------------------
c.url.searchengines = {"DEFAULT": "https://search.brave.com/search?q={}"}
c.url.start_pages = ["about:blank"]
c.url.default_page = "about:blank"
c.content.cookies.accept = "no-3rdparty"
c.content.headers.do_not_track = True
c.content.webrtc_ip_handling_policy = "default-public-interface-only"
c.content.geolocation = False
c.content.notifications.enabled = False
c.content.blocking.method = "both"  # host lists + Brave's adblock engine

# --- Downloads ------------------------------------------------------------
# ~/Shared inside the sandbox = ~/sandbox_folders/qutebrowser outside it.
c.downloads.location.directory = "/home/arlo/Shared"
c.downloads.location.prompt = False
