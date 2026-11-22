// The bar: prompt, workspaces and scratchpads on the left; the island
// (clock, what's playing, recording) in the middle; status, tray and power
// on the right.
import QtQuick
import Quickshell
import Quickshell.Hyprland

PanelWindow {
    id: bar

    // Which dropdown is open ("" for none). Its bar button gets the green
    // fill: chat, hidden, power, playing, vpn, netbird, backup, update.
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

    Island {
        id: island
        bar: bar
        anchors.top: parent.top
        // Centred while it fits; when it grows wider than the space either
        // side of the centre allows, it slides over within the gap between
        // the left and right sides (24px breathing room each side).
        x: Math.max(leftSide.x + leftSide.width + 24, Math.min((bar.width - width) / 2, rightSide.x - 24 - width))
        room: rightSide.x - (leftSide.x + leftSide.width) - 48
    }

    Row {
        id: rightSide
        anchors {
            right: parent.right
            rightMargin: 14
            top: parent.top
        }

        StatusItems {
            bar: bar
        }

        Tray {
            bar: bar
        }

        BarButton {
            id: power
            icon: "\u{F0425}"
            color: Config.colors.dim
            open: bar.open === "power"
            onClicked: bar.toggle("power")
        }
    }

    Popups {
        bar: bar
    }

    PowerMenu { bar: bar; anchorItem: power; name: "power" }
    PlayingMenu { bar: bar; anchorItem: island.playingItem; name: "playing" }
}
