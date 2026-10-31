-- Keyboard, touchpad, gestures.
-- Options: https://wiki.hypr.land/Configuring/Basics/Variables/ (input section)
-- Gestures: https://wiki.hypr.land/Configuring/Advanced-and-Cool/Gestures/

hl.config({
    input = {
        kb_layout = "us",

        -- Focus follows the mouse pointer.
        follow_mouse = 1,

        touchpad = {
            natural_scroll       = true,
            tap_to_click         = true, -- the default, stated so it's visible
            disable_while_typing = true,
        },
    },
})

-- Three-finger swipe left/right switches workspaces.
hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace",
})
