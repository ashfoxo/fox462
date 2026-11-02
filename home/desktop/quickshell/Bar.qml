// The bar: prompt, workspaces and scratchpads on the left; status, tray,
// clock and power on the right.
import QtQuick
import Quickshell
import Quickshell.Hyprland

PanelWindow {
    id: bar

    // Which dropdown is open ("" for none). Its bar button gets the green
    // fill: chat, hidden, power, vpn, netbird, backup, update, wifi, bt, vol, clock.
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

        StatusItems {
            bar: bar
        }

        Tray {
            bar: bar
        }

        BarButton {
            id: clock
            text: Qt.formatTime(clockSource.date, "HH:mm")
            bold: true
            open: bar.open === "clock"
            onClicked: bar.toggle("clock")
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

    PowerMenu {
        bar: bar
        anchorItem: power
        visible: bar.open === "power"
        onDismissed: bar.open = ""
    }

    CalendarPopup {
        bar: bar
        anchorItem: clock
        visible: bar.open === "clock"
        onDismissed: bar.open = ""
    }
}
