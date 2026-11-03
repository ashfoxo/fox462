//@ pragma UseQApplication
// UseQApplication: tray icons' right-click menus need it.

// Entry point. Puts one bar on the main display (displays.nix).
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

ShellRoot {
    id: root

    // Start the notification daemon right away, even with no bar showing.
    readonly property bool notifications: Notifs.dnd !== undefined

    // The display picked with Super + Shift + P: its description, or empty
    // for automatic. Re-read whenever display-main rewrites the file.
    FileView {
        id: choiceFile
        path: Config.displays.choice
        // Read before the bar first appears, so it starts on the right screen.
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }

    readonly property string chosen: choiceFile.text().trim()

    // The chosen display if it's connected, else the first entry of
    // Config.barMonitors that matches a connected screen (by port name, or
    // part of Hyprland's description of it), else the laptop panel, else
    // whatever screen there is. Re-evaluates when monitors come and go or
    // the choice changes, so the bar follows.
    readonly property var barScreen: {
        const screens = Quickshell.screens;
        const monitors = Hyprland.monitors.values;
        const describe = s => {
            const m = monitors.find(m => m.name === s.name);
            return m ? m.description : `${s.model} ${s.serialNumber}`;
        };
        const wanted = (root.chosen ? [root.chosen] : []).concat(Config.barMonitors);
        for (const want of wanted) {
            const match = screens.find(s => s.name === want || describe(s).includes(want));
            if (match)
                return match;
        }
        return screens.find(s => s.name.startsWith("eDP")) ?? screens[0] ?? null;
    }

    // Tells hyprlock which screen gets the clock and prompt: the one the bar
    // is on (lockscreen.nix sources this file).
    FileView {
        id: lockFile
        path: Config.displays.lock
        preload: false
        printErrors: false
    }

    function writeLockFile() {
        if (root.barScreen)
            lockFile.setText("$main = " + root.barScreen.name + "\n");
    }

    onBarScreenChanged: writeLockFile()
    Component.onCompleted: writeLockFile()

    Variants {
        model: root.barScreen ? [root.barScreen] : []

        Bar {
            required property var modelData
            screen: modelData
        }
    }
}
