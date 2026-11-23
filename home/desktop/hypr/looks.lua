-- Look and feel: gaps, borders, rounding, animations.
-- Colors come from palette.nix (via the generated arlo/palette.lua).
-- Options: https://wiki.hypr.land/Configuring/Basics/Variables/

local c = require("arlo.palette")

hl.config({
    general = {
        gaps_in     = 4,
        gaps_out    = 8,
        border_size = 2,

        col = {
            active_border   = { colors = { c.rgb(c.forest), c.rgb(c.teal) }, angle = 45 },
            inactive_border = c.rgb(c.surf),
        },

        -- Drag a border or gap to resize; easier than Super + right-drag on a touchpad.
        resize_on_border = true,

        layout = "dwindle",
    },

    decoration = {
        rounding = 6,

        shadow = {
            enabled      = true,
            range        = 6,
            render_power = 3,
            color        = c.rgba(c.bg, "cc"),
        },

        -- Off on purpose: costs battery on integrated graphics, and nothing
        -- here is translucent enough to need it.
        blur = {
            enabled = false,
        },
    },

    animations = {
        enabled = true,
    },

    dwindle = {
        preserve_split = true,
    },

    misc = {
        -- The wallpaper comes from hyprpaper. Hide Hyprland's own default
        -- wallpaper, logo and splash text that would show behind it.
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
        disable_splash_rendering = true,
    },
})

-- Animations: snappy. One fast ease-out curve for everything, at about half
-- Hyprland's default durations (speed is in tenths of a second). Windows pop
-- in from 90%, workspaces slide, the bar's dropdowns and popups fade.
-- Curves and leaves: https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
hl.curve("snappy", { type = "bezier", points = { {0.05, 0.9}, {0.1, 1} } })

hl.animation({ leaf = "global",     enabled = true, speed = 4,   bezier = "snappy" })
hl.animation({ leaf = "border",     enabled = true, speed = 3,   bezier = "snappy" })
hl.animation({ leaf = "windows",    enabled = true, speed = 2.5, bezier = "snappy" })
hl.animation({ leaf = "windowsIn",  enabled = true, speed = 2,   bezier = "snappy", style = "popin 90%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.5, bezier = "snappy", style = "popin 90%" })
hl.animation({ leaf = "fade",       enabled = true, speed = 1.5, bezier = "snappy" })
hl.animation({ leaf = "layers",     enabled = true, speed = 1.5, bezier = "snappy", style = "fade" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 2,   bezier = "snappy", style = "slide" })
