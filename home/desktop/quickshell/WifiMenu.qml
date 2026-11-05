// Wi-Fi dropdown: on/off switch, nearby networks (connected first, then
// saved, then by signal). Click a saved or open network to join it; a new
// secured one (lock icon) opens nmtui to type its password.
import QtQuick
import Quickshell
import Quickshell.Networking

Dropdown {
    id: menu

    readonly property var c: Config.colors
    readonly property var device: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var networks: device ? device.networks.values.slice()
        .sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength))
        .slice(0, 8) : []

    function secured(n) {
        return n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe;
    }
    function strengthIcon(s) {
        return s > 0.75 ? "\u{F0928}" : s > 0.5 ? "\u{F0925}" : s > 0.25 ? "\u{F0922}" : "\u{F091F}";
    }
    function nmtui() {
        Quickshell.execDetached(["ghostty", "-e", "nmtui"]);
        menu.dismissed();
    }
    function pick(n) {
        if (n.connected)
            return;
        if (n.known || !secured(n))
            n.connect();
        else
            nmtui();
    }

    // Scan only while the dropdown is open.
    onVisibleChanged: {
        if (device)
            device.scannerEnabled = visible;
    }

    MenuHeader {
        icon: "\u{F0928}"
        title: "wi-fi"

        PopButton {
            small: true
            kind: Networking.wifiEnabled ? "fill" : "plain"
            text: Networking.wifiEnabled ? "on" : "off"
            onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
        }
    }

    Column {
        width: parent.width

        BarText {
            visible: !Networking.wifiEnabled
            text: "wi-fi is off"
            color: menu.c.dim
        }
        BarText {
            visible: Networking.wifiEnabled && menu.networks.length === 0
            text: "scanning…"
            color: menu.c.teal_text
        }

        Repeater {
            model: Networking.wifiEnabled ? menu.networks : []

            ListRow {
                required property var modelData

                selected: modelData.connected
                cursorShape: modelData.connected ? Qt.ArrowCursor : Qt.PointingHandCursor
                icon: menu.strengthIcon(modelData.signalStrength)
                iconColor: modelData.connected ? menu.c.forest_text : menu.c.dim
                text: modelData.name + (menu.secured(modelData) && !modelData.known ? " \u{F033E}" : "")
                note: modelData.connected ? "connected"
                    : modelData.stateChanging ? "connecting…"
                    : modelData.known ? "saved"
                    : !menu.secured(modelData) ? "open" : ""
                noteColor: modelData.connected ? menu.c.forest_text
                    : modelData.stateChanging ? menu.c.teal_text
                    : menu.c.faint
                onClicked: menu.pick(modelData)
            }
        }
    }

    Divider {}

    MouseArea {
        width: parent.width
        height: more.implicitHeight
        cursorShape: Qt.PointingHandCursor
        onClicked: menu.nmtui()

        BarText {
            id: more
            text: "more in nmtui \u{F0142}"
            color: menu.c.dim
        }
    }
}
