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
            active_border   = c.rgb(c.forest),
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

    -- Hyprland's built-in animation defaults. Tune later, deliberately.
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
