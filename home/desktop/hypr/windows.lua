-- Scratchpads, hiding windows, and popping a scratchpad out into a normal
-- window. binds.lua puts these on keys; the bar calls the same functions
-- over IPC, e.g. require("arlo.windows").toggle_pad("notes").
-- Each function returns a dispatcher (a function), like hl.dsp.* do.

local pads = require("arlo.scratchpads")
local M = {}

local function find_pad(name)
    for _, p in ipairs(pads) do
        if p.name == name then return p end
    end
end

-- The scratchpad a workspace belongs to ("special:notes" -> the notes pad).
local function pad_of_workspace(ws)
    if ws and ws.special then
        return find_pad((ws.name:gsub("^special:", "")))
    end
end

-- A scratchpad window popped out onto a normal workspace carries the tag
-- "pad-<name>", so it can find its way back.
local function popped_out(name)
    return hl.get_windows({ tag = "pad-" .. name })[1]
end

local function has_tag(w, tag)
    for _, t in ipairs(w.tags or {}) do
        if t == tag then return true end
    end
    return false
end

-- Show or hide a scratchpad, starting its app if needed. If it's popped
-- out, go to it instead.
function M.toggle_pad(name)
    return function()
        local p = find_pad(name)
        if not p then return end
        local out = popped_out(name)
        if out then
            hl.dispatch(hl.dsp.focus({ window = out }))
            return
        end
        if #hl.get_workspace_windows("special:" .. name) == 0 then
            hl.exec_cmd(p.cmd)
        end
        hl.dispatch(hl.dsp.workspace.toggle_special(name))
    end
end

-- Super + O. On a scratchpad: drop it tiled onto the workspace you're on,
-- as a normal window. On a popped-out one: send it back to its scratchpad,
-- floating at its usual size.
function M.pop()
    return function()
        local w = hl.get_active_window()
        if not w then return end

        local p = pad_of_workspace(w.workspace)
        if p then
            local mon = hl.get_active_monitor()
            local here = mon and mon.active_workspace
            if not here then return end
            -- Close the scratchpad first, then move the window out of it.
            hl.dispatch(hl.dsp.workspace.toggle_special(p.name))
            hl.dispatch(hl.dsp.window.move({ workspace = here.id, window = w }))
            hl.dispatch(hl.dsp.window.float({ action = "disable", window = w }))
            hl.dispatch(hl.dsp.window.tag({ tag = "+pad-" .. p.name, window = w }))
            hl.dispatch(hl.dsp.focus({ window = w }))
            return
        end

        for _, q in ipairs(pads) do
            if has_tag(w, "pad-" .. q.name) then
                local mon = hl.get_active_monitor()
                local size = q.size or 0.75
                hl.dispatch(hl.dsp.window.tag({ tag = "-pad-" .. q.name, window = w }))
                hl.dispatch(hl.dsp.window.float({ action = "enable", window = w }))
                if mon then
                    -- width/height are pixels; resize wants layout size.
                    local scale = mon.scale or 1
                    hl.dispatch(hl.dsp.window.resize({
                        x = math.floor(mon.width / scale * size),
                        y = math.floor(mon.height / scale * size),
                        window = w,
                    }))
                end
                hl.dispatch(hl.dsp.window.move({ workspace = "special:" .. q.name, follow = false, window = w }))
                hl.dispatch(hl.dsp.window.center({ window = w }))
                return
            end
        end
    end
end

-- Super + H. Tuck the focused window away; the bar's "hidden" item lists
-- them and brings them back. On a scratchpad it just hides the scratchpad.
function M.hide()
    return function()
        local w = hl.get_active_window()
        if not w then return end
        local p = pad_of_workspace(w.workspace)
        if p then
            hl.dispatch(hl.dsp.workspace.toggle_special(p.name))
        elseif not (w.workspace and w.workspace.name == "special:hidden") then
            hl.dispatch(hl.dsp.window.move({ workspace = "special:hidden", follow = false, window = w }))
        end
    end
end

-- Bring a hidden window back onto the workspace you're on (the bar calls
-- this with the window's address).
function M.unhide(address)
    return function()
        local mon = hl.get_active_monitor()
        local here = mon and mon.active_workspace
        if not here then return end
        local w = "address:" .. address
        hl.dispatch(hl.dsp.window.move({ workspace = here.id, window = w }))
        hl.dispatch(hl.dsp.focus({ window = w }))
    end
end

return M
