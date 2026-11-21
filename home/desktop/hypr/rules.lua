-- Window rules: which app opens where.
-- Window rules: https://wiki.hypr.land/Configuring/Basics/Window-Rules/
--
-- Find an app's class: open it, then run
--   hyprctl clients | grep -E "class|title"
-- Classes are regex, so anchor them (^...$) to avoid surprise matches.

-- Send each app to its workspace role. The terminal and file manager are
-- deliberately not pinned: you want those on whatever workspace you're using.
local workspaces = {
    [2] = { "^librewolf$", "^Mullvad Browser$", "^fluent-reader$" },     -- Web
    [3] = { "^codium$" },                                                      -- Dev
    [4] = { "^typora$", "^libreoffice-.*$" },                       -- Writing
    [5] = { "^zoom$" },                                                        -- Comms (chat apps are scratchpads)
    [6] = { "^darktable$", "^org\\.kde\\.kdenlive$" },                           -- Creative
    [7] = { "^CHIRP$", "^WSJT-X$" },                                           -- Radio
    [8] = { "^steam$", "^org\\.prismlauncher\\.PrismLauncher$",
            "^org\\.jellyfin\\.JellyfinDesktop$" },                            -- Entertainment
}

for ws, classes in pairs(workspaces) do
    for _, class in ipairs(classes) do
        hl.window_rule({
            name      = "ws" .. ws .. "-" .. class:gsub("[^%w]", ""),
            match     = { class = class },
            workspace = tostring(ws),
        })
    end
end

-------------------------------------
---- SCRATCHPAD APPS (binds.lua) ----
-------------------------------------
-- Opened silently into their special workspace, floating and centered,
-- 75% of the screen unless the entry gives a size.
-- The list is scratchpads.nix (via hyprland.nix). An entry with a title
-- must match both class and title.

for _, s in ipairs(require("arlo.scratchpads")) do
    hl.window_rule({
        name      = "scratch-" .. s.name,
        match     = { class = s.class, title = s.title },
        workspace = "special:" .. s.name .. " silent",
        float     = true,
        size      = ("monitor_w*%s monitor_h*%s"):format(s.size or 0.75, s.size or 0.75),
        center    = true,
    })
end

---------------
---- MISC -----
---------------

-- File pickers (the GTK portal's open/save dialogs, used by sandboxed and
-- Electron apps): floating and centered. A new window opens inside a
-- showing scratchpad, but tiled, and tiled windows sit under floating ones,
-- so without this the picker hides behind the scratchpad app.
hl.window_rule({
    name   = "file-picker",
    match  = { class = "^xdg-desktop-portal-gtk$" },
    float  = true,
    size   = "monitor_w*0.6 monitor_h*0.7",
    center = true,
})

-- Apps can't maximize themselves and fight the tiling layout.
hl.window_rule({
    name           = "suppress-maximize-events",
    match          = { class = ".*" },
    suppress_event = "maximize",
})

-- Fix some XWayland drag-and-drop glitches (from the Hyprland example config).
hl.window_rule({
    name     = "fix-xwayland-drags",
    match    = { class = "^$", title = "^$", xwayland = true, float = true,
                 fullscreen = false, pin = false },
    no_focus = true,
})

-- Windows from a VM (modules/vms.nix): the host's waypipe puts "[vm] " in front
-- of every title, so the border colour says which VM drew the window, focused
-- or not. Patterns must match the whole title, hence the trailing .*
local c = require("arlo.palette")
local vm_colours = {
    ["untrusted"] = c.rust_text,
    ["sys-net"]   = c.amber,
    ["portal"]    = c.amber,       -- the Wi-Fi login page: sys-net's helper
    ["calls"]     = c.teal_text,
    ["personal"]  = c.forest_text,
    ["torrent"]   = c.dim,
}
for vm, colour in pairs(vm_colours) do
    hl.window_rule({
        name         = "vm-" .. vm,
        match        = { title = "^\\[" .. vm:gsub("%-", "\\-") .. "\\] .*" },
        border_color = c.rgb(colour) .. " " .. c.rgb(colour),
    })
end
