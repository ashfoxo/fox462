-- Keybinds. Every bind gets a description: Super + / reads them back out of
-- the running Hyprland (hyprctl binds), so the cheat sheet can't drift from
-- what's actually bound.
--
-- Description format is "Category: what it does". Keep quotes and
-- backslashes out of descriptions; they break the cheat sheet's JSON.
--
-- Binds:       https://wiki.hypr.land/Configuring/Basics/Binds/
-- Dispatchers: https://wiki.hypr.land/Configuring/Basics/Dispatchers/

local mod = "SUPER"

-- Small helper so each bind reads as: keys, action, description.
local function bind(keys, action, desc, opts)
    opts = opts or {}
    opts.description = desc
    hl.bind(keys, action, opts)
end

local exec = hl.dsp.exec_cmd

------------------
---- PROGRAMS ----
------------------

bind(mod .. " + Return", exec("ghostty"),                   "Apps: Terminal")
bind(mod .. " + R",      exec("fuzzel"),                    "Apps: Launcher")
bind(mod .. " + slash",  exec("hypr-cheatsheet"),           "Help: This cheat sheet")

-- Focus the app if it's already open, otherwise launch it. `needle` is any
-- piece of the window class (see hyprctl clients), matched as plain text.
local function focus_or_launch(needle, cmd)
    return function()
        for _, w in ipairs(hl.get_windows()) do
            if w.class and string.find(w.class, needle, 1, true) then
                hl.dispatch(hl.dsp.focus({ window = w }))
                return
            end
        end
        hl.exec_cmd(cmd)
    end
end

-- Web apps (webapps.nix) match on their site's host name.
bind(mod .. " + T", focus_or_launch("app.tuta.com", "webapp-tuta"),   "Apps: Tuta mail")

-----------------
---- WINDOWS ----
-----------------

bind(mod .. " + Q",         hl.dsp.window.close(),                               "Window: Close")
bind(mod .. " + F",         hl.dsp.window.fullscreen(),                          "Window: Fullscreen")
bind(mod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "maximized" }),    "Window: Maximize, keep bar and gaps")
bind(mod .. " + V",         hl.dsp.window.float(),                               "Window: Toggle floating")

-- Focus: vim keys and arrows.
for key, dir in pairs({ H = "left", J = "down", K = "up", L = "right",
                        left = "left", down = "down", up = "up", right = "right" }) do
    bind(mod .. " + " .. key,             hl.dsp.focus({ direction = dir }),       "Focus: Move focus " .. dir)
    bind(mod .. " + SHIFT + " .. key,     hl.dsp.window.move({ direction = dir }), "Window: Move " .. dir)
end

-- Mouse: Super + left-drag moves, Super + right-drag resizes.
bind(mod .. " + mouse:272", hl.dsp.window.drag(),   "Mouse: Drag to move window",   { mouse = true })
bind(mod .. " + mouse:273", hl.dsp.window.resize(), "Mouse: Drag to resize window", { mouse = true })

--------------------
---- WORKSPACES ----
--------------------
-- Roles (enforced by rules.lua for the apps listed there):
--   1 Terminal  2 Web  3 Dev  4 Writing  5 Comms
--   6 Creative  7 Radio  8 Games  9 Overflow

for i = 1, 9 do
    bind(mod .. " + " .. i,         hl.dsp.focus({ workspace = i }),       "Workspace: Go to " .. i)
    bind(mod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }), "Workspace: Send window to " .. i)
end

bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }), "Workspace: Next, Super + scroll")
bind(mod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }), "Workspace: Previous, Super + scroll")

---------------------
---- SCRATCHPADS ----
---------------------
-- A scratchpad is a hidden special workspace that slides over whatever
-- you're on. The list is in scratchpads.nix (generated into
-- arlo/scratchpads.lua); rules.lua routes each app's windows into its
-- scratchpad. Pressing the key starts the app if it isn't running yet.
-- The logic lives in windows.lua, which the bar uses too.

local pads = require("arlo.scratchpads")
local win = require("arlo.windows")

for _, pad in ipairs(pads) do
    if not pad.chat then
        bind(mod .. " + " .. pad.key, win.toggle_pad(pad.name), "Scratchpad: " .. pad.name)
    end
end

-- Super + O: scratchpad <-> normal tiled window on this workspace.
bind(mod .. " + O", win.pop(), "Scratchpad: Pop out as a normal window, or back in")
-- Super + X: hide the window (the bar's "hidden" item brings it back).
-- On a scratchpad, just hides the scratchpad.
bind(mod .. " + X", win.hide(), "Window: Hide, bring back from the bar")

-- Chat apps: Super + C, then a letter (s, t, d, m). Escape, or any other
-- key, cancels.
bind(mod .. " + C", hl.dsp.submap("chat"), "Chat: Then a letter for the app, Esc cancels")
hl.define_submap("chat", "reset", function()
    for _, pad in ipairs(pads) do
        if pad.chat then
            bind(pad.key, win.toggle_pad(pad.name), "Chat: " .. pad.name)
        end
    end
    bind("Escape", hl.dsp.submap("reset"), "Chat: Cancel")
    bind("catchall", hl.dsp.submap("reset"), "Chat: Any other key cancels")
end)

-----------------
---- SESSION ----
-----------------

bind(mod .. " + Escape",    exec("loginctl lock-session"), "Session: Lock screen")
-- Panic: power off now, no questions, no grace period.
bind(mod .. " + CTRL + SHIFT + Escape", exec("systemctl poweroff -i"), "Session: PANIC power off")
bind(mod .. " + SHIFT + E", hl.dsp.exit(),                 "Session: Log out of Hyprland")

bind(mod .. " + SHIFT + S", exec('grim -g "$(slurp)" - | wl-copy'), "Screenshot: Region to clipboard")
bind(mod .. " + SHIFT + R", exec("voice-note"), "Voice note: Start or stop and transcribe")

----------------------------
---- HARDWARE / MEDIA ----
----------------------------
-- locked = works on the lock screen; repeating = holds down to repeat.

local hw = { locked = true, repeating = true }

bind("XF86AudioRaiseVolume",  exec("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), "Media: Volume up",        hw)
bind("XF86AudioLowerVolume",  exec("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      "Media: Volume down",      hw)
bind("XF86AudioMute",         exec("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     "Media: Mute",             { locked = true })
bind("XF86AudioMicMute",      exec("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   "Media: Mute microphone",  { locked = true })
bind("XF86MonBrightnessUp",   exec("brightnessctl set 5%+"),                          "Media: Brightness up",    hw)
bind("XF86MonBrightnessDown", exec("brightnessctl set 5%-"),                          "Media: Brightness down",  hw)

-- playerctl talks to whatever is playing (Feishin, browsers, mpv).
bind("XF86AudioPlay",  exec("playerctl play-pause"), "Media: Play or pause", { locked = true })
bind("XF86AudioPause", exec("playerctl play-pause"), "Media: Play or pause", { locked = true })
bind("XF86AudioNext",  exec("playerctl next"),       "Media: Next track",    { locked = true })
bind("XF86AudioPrev",  exec("playerctl previous"),   "Media: Previous track",{ locked = true })
