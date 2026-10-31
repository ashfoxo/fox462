// Bluetooth dropdown: on/off switch, then your paired devices; click one to
// connect or disconnect it. Pairing something new happens in bluetui.
import QtQuick
import Quickshell
import Quickshell.Bluetooth

Dropdown {
    id: menu

    readonly property var c: Config.colors
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool on: adapter !== null && adapter.enabled
    // Paired devices, connected first, then by name.
    readonly property var devices: adapter ? adapter.devices.values
        .filter(d => d.paired || d.bonded)
        .sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name)) : []

    // Icon from the device type BlueZ reports.
    function iconFor(d) {
        const i = d.icon ?? "";
        return i.startsWith("audio") ? "\u{F02CB}"
            : i === "input-keyboard" ? "\u{F030C}"
            : i === "input-mouse" ? "\u{F037D}"
            : i === "input-gaming" ? "\u{F0297}"
            : i.startsWith("phone") ? "\u{F011C}"
            : i === "computer" ? "\u{F0322}"
            : "\u{F00AF}";
    }

    MenuHeader {
        icon: "\u{F00AF}"
        title: "bluetooth"

        PopButton {
            visible: menu.adapter !== null
            small: true
            kind: menu.on ? "fill" : "plain"
            text: menu.on ? "on" : "off"
            onClicked: menu.adapter.enabled = !menu.on
        }
    }

    BarText {
        visible: menu.adapter === null
        text: "no bluetooth adapter found"
        color: menu.c.dim
    }
    BarText {
        visible: menu.adapter !== null && !menu.on
        text: "turn on to see paired devices"
        color: menu.c.dim
    }

    Column {
        visible: menu.on
        width: parent.width
        spacing: 6

        BarText {
            text: menu.devices.length > 0 ? "paired" : "nothing paired yet"
            color: menu.c.dim
        }

        Column {
            width: parent.width

            Repeater {
                model: menu.devices

                MouseArea {
                    id: row

                    required property var modelData
                    readonly property bool busy: modelData.state === BluetoothDeviceState.Connecting
                        || modelData.state === BluetoothDeviceState.Disconnecting

                    width: parent.width
                    height: 42
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (modelData.connected)
                            modelData.disconnect();
                        else
                            modelData.connect();
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: row.modelData.connected ? menu.c.surf : "transparent"
                    }
                    Row {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter

                        BarText {
                            text: menu.iconFor(row.modelData) + " "
                            color: row.modelData.connected ? menu.c.forest_text : menu.c.dim
                        }
                        BarText {
                            text: row.modelData.name.toLowerCase()
                        }
                    }
                    BarText {
                        anchors {
                            right: parent.right
                            rightMargin: 10
                            verticalCenter: parent.verticalCenter
                        }
                        text: row.busy ? (row.modelData.connected ? "disconnecting…" : "connecting…")
                            : row.modelData.connected ? "connected"
                            : "connect"
                        color: row.busy ? menu.c.teal_text
                            : row.modelData.connected ? menu.c.forest_text
                            : menu.c.faint
                    }
                }
            }
        }
    }

    Divider {}

    MouseArea {
        width: parent.width
        height: pair.implicitHeight
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            Quickshell.execDetached(["ghostty", "-e", "bluetui"]);
            menu.dismissed();
        }

        BarText {
            id: pair
            text: "pair new device in bluetui \u{F0142}"
            color: menu.c.dim
        }
    }
}
