pragma Singleton

// The scratchpads from scratchpads.nix: which are running, which one is
// showing, and showing/hiding them the same way their keys do. Also the
// windows hidden with Super + X.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

Singleton {
    id: root

    readonly property var all: Config.scratchpads
    readonly property var chats: all.filter(p => p.chat)

    // Names of the scratchpads with a window open. The class and title are
    // the same regexes as Hyprland's window rules.
    readonly property var running: all
        .filter(p => ToplevelManager.toplevels.values.some(t => matches(p, t)))
        .map(p => p.name)

    // When each running scratchpad's window first appeared (ms). Windows
    // that were already open when the shell started (it gets the list a
    // moment after starting) count from the start of the Hyprland session,
    // whose instance signature holds its launch time, so restarting the
    // shell doesn't mute anything.
    property var startedAt: ({})
    readonly property real shellStart: Date.now()
    readonly property real sessionStart: {
        const t = parseInt((Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ?? "").split("_")[1]);
        return isNaN(t) ? Date.now() : t * 1000;
    }

    function matches(p, t) {
        return new RegExp(p.class).test(t.appId ?? "")
            && (!p.title || new RegExp(p.title).test(t.title ?? ""));
    }
    function find(name) {
        return all.find(p => p.name === name) ?? null;
    }
    function isRunning(p) {
        return running.includes(p.name);
    }

    // True for the first Config.notifications.quietSeconds after a chat
    // app's window appears: its notifications then are old messages
    // arriving as it reconnects. (Closing an app's window and opening it
    // again counts as a fresh start too.)
    function quiet(p) {
        const t = startedAt[p.name];
        return t !== undefined && Date.now() - t < Config.notifications.quietSeconds * 1000;
    }

    function track() {
        const now = Date.now() - shellStart < 5000 ? sessionStart : Date.now();
        const next = {};
        for (const n of running)
            next[n] = startedAt[n] ?? now;
        startedAt = next;
    }
    onRunningChanged: track()
    Component.onCompleted: track()

    // The scratchpad showing on a monitor ("special:term" -> "term").
    function showingOn(monitor) {
        const name = monitor?.lastIpcObject?.specialWorkspace?.name ?? "";
        return name.startsWith("special:") ? name.slice(8) : "";
    }

    // Show or hide it, starting the app first if it isn't running; if it's
    // popped out as a normal window, go to it. Same code as its key
    // (hypr/windows.lua).
    function toggle(p) {
        Hyprland.dispatch(`require("arlo.windows").toggle_pad(${JSON.stringify(p.name)})`);
    }
    // Show it (on the focused monitor), leaving it up if it already is.
    function show(p) {
        if (showingOn(Hyprland.focusedMonitor) !== p.name)
            toggle(p);
    }

    // Windows hidden with Super + X (they sit in special:hidden), and
    // bringing one back onto the workspace you're on.
    readonly property var hidden: Hyprland.toplevels.values.filter(t => t.workspace?.name === "special:hidden")
    function unhide(t) {
        Hyprland.dispatch(`require("arlo.windows").unhide("0x${t.address}")`);
    }

    // Hyprland's monitor info doesn't update on its own when a scratchpad
    // is shown or hidden, so ask for it again.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activespecial")
                Hyprland.refreshMonitors();
        }
    }
}
