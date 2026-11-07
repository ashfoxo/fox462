// The bar: prompt, workspaces and scratchpads on the left; now playing,
// status, tray, clock and power on the right.
import QtQuick
import Quickshell
import Quickshell.Hyprland

PanelWindow {
    id: bar

    // Which dropdown is open ("" for none). Its bar button gets the green
    // fill: chat, hidden, power, playing, vpn, netbird, backup, update, wifi, bt, vol.
    property string open: ""
    readonly property var monitor: Hyprland.monitorFor(screen)

    function toggle(name) {
        open = open === name ? "" : name;
    }

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Config.bar.height
    color: Config.colors.bg

    Rectangle {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: 1
        color: Config.colors.surf
    }

    Row {
        id: leftSide
        anchors {
            left: parent.left
            leftMargin: 14
            top: parent.top
        }
        spacing: 24

        Workspaces {
            monitor: bar.monitor
        }
        Scratchpads {
            bar: bar
        }
    }

    Row {
        anchors {
            right: parent.right
            rightMargin: 14
            top: parent.top
        }

        // Shown while something plays here or on your other devices, or is
        // paused here. The title gets whatever space is free between the
        // left side and the status (at most 400px) and is cut with "…".
        BarButton {
            id: playing

            visible: Playing.label !== ""
            icon: "\u{F075A}"
            text: Playing.label
            // 14 + 14 margins, 24 breathing room, 18 spacer, ~40 icon and padding.
            maxTextWidth: Math.max(60, Math.min(400, bar.width - leftSide.width - status.width - tray.width - clock.width - power.width - 110))
            color: Playing.playing ? Config.colors.fg : Config.colors.faint
            iconColor: Playing.playing ? Config.colors.forest_text : Config.colors.faint
            open: bar.open === "playing"
            onClicked: bar.toggle("playing")
        }
        Item {
            visible: playing.visible
            width: 18
            height: 1
        }

        StatusItems {
            id: status
            bar: bar
        }

        Tray {
            id: tray
            bar: bar
        }

        BarButton {
            id: clock
            text: Qt.formatTime(clockSource.date, "HH:mm")
            bold: true
            interactive: false
        }

        BarButton {
            id: power
            icon: "\u{F0425}"
            color: Config.colors.dim
            open: bar.open === "power"
            onClicked: bar.toggle("power")
        }
    }

    SystemClock {
        id: clockSource
        precision: SystemClock.Minutes
    }

    Popups {
        bar: bar
    }

    PowerMenu { bar: bar; anchorItem: power; name: "power" }
    PlayingMenu { bar: bar; anchorItem: playing; name: "playing" }
}
