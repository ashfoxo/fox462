-- Window rules: which app opens where.
-- Window rules: https://wiki.hypr.land/Configuring/Basics/Window-Rules/
--
-- Find an app's class: open it, then run
--   hyprctl clients | grep -E "class|title"
-- Classes are regex, so anchor them (^...$) to avoid surprise matches.

-- Send each app to its workspace role. The terminal and file manager are
-- deliberately not pinned: you want those on whatever workspace you're using.
local workspaces = {
    [2] = { "^librewolf$", "^Mullvad Browser$", "^fluent-reader$",
            "^org\\.qutebrowser\\.qutebrowser$" },                          -- Web
    [3] = { "^codium$" },                                                      -- Dev
    [4] = { "^typora$", "^lockbook-desktop$", "^libreoffice-.*$" }, -- Writing
    [5] = { "^zoom$" },                                                        -- Comms (chat apps are scratchpads)
    [6] = { "^darktable$", "^org\\.kde\\.kdenlive$" },                           -- Creative
    [7] = { "^CHIRP$", "^WSJT-X$" },                                           -- Radio
    [8] = { "^steam$", "^org\\.prismlauncher\\.PrismLauncher$" },                -- Entertainment
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
-- The list is scratchpads.nix (via hyprland.nix). Telegram's sandbox leaves
-- its class empty, so it also matches on title; both must match, so a
-- browser tab titled "Telegram" won't count.

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
