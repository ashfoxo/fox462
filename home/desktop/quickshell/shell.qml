//@ pragma UseQApplication
// UseQApplication: tray icons' right-click menus need it.

// Entry point. Puts one bar on the monitor picked by Config.barMonitors.
import QtQuick
import Quickshell
import Quickshell.Hyprland

ShellRoot {
    id: root

    // Start the notification daemon right away, even with no bar showing.
    readonly property bool notifications: Notifs.dnd !== undefined

    // The first entry of Config.barMonitors that matches a connected screen
    // (by port name, or part of Hyprland's description of it), else the
    // laptop panel, else whatever screen there is. Re-evaluates when
    // monitors come and go, so the bar follows.
    readonly property var barScreen: {
        const screens = Quickshell.screens;
        const monitors = Hyprland.monitors.values;
        const describe = s => {
            const m = monitors.find(m => m.name === s.name);
            return m ? m.description : `${s.model} ${s.serialNumber}`;
        };
        for (const want of Config.barMonitors) {
            const match = screens.find(s => s.name === want || describe(s).includes(want));
            if (match)
                return match;
        }
        return screens.find(s => s.name.startsWith("eDP")) ?? screens[0] ?? null;
    }

    Variants {
        model: root.barScreen ? [root.barScreen] : []

        Bar {
            required property var modelData
            screen: modelData
        }
    }
}
