// Wi-Fi dropdown: on/off switch, nearby networks (connected first, then
// saved, then by signal). Click a saved or open network to join it; a new
// secured one opens a password box under it. nmtui for anything else.
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
    // The network whose password box is open, and whether its last try failed.
    property var joining: null
    property bool wrong: false

    function secured(n) {
        return n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe;
    }
    function strengthIcon(s) {
        return s > 0.75 ? "\u{F0928}" : s > 0.5 ? "\u{F0925}" : s > 0.25 ? "\u{F0922}" : "\u{F091F}";
    }
    function pick(n) {
        if (n.connected)
            return;
        wrong = false;
        if (n.known || !secured(n)) {
            joining = null;
            n.connect();
        } else {
            joining = joining === n ? null : n;
        }
    }

    keyboard: true

    // Scan only while the dropdown is open.
    onVisibleChanged: {
        if (device)
            device.scannerEnabled = visible;
        if (!visible) {
            joining = null;
            wrong = false;
        }
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

            Column {
                id: entry

                required property var modelData
                readonly property bool open: menu.joining === modelData

                function join() {
                    menu.wrong = false;
                    modelData.connectWithPsk(password.text);
                }

                width: parent.width

                MouseArea {
                    width: parent.width
                    height: 40
                    cursorShape: entry.modelData.connected ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onClicked: menu.pick(entry.modelData)

                    Rectangle {
                        anchors.fill: parent
                        color: entry.modelData.connected ? menu.c.surf : "transparent"
                    }
                    Row {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter

                        BarText {
                            text: menu.strengthIcon(entry.modelData.signalStrength) + " "
                            color: entry.modelData.connected ? menu.c.forest_text : menu.c.dim
                        }
                        BarText {
                            text: entry.modelData.name
                        }
                        BarText {
                            visible: menu.secured(entry.modelData) && !entry.modelData.known
                            text: " \u{F033E}"
                            color: menu.c.dim
                        }
                    }
                    BarText {
                        anchors {
                            right: parent.right
                            rightMargin: 10
                            verticalCenter: parent.verticalCenter
                        }
                        text: entry.modelData.connected ? "connected"
                            : entry.modelData.stateChanging ? "connecting…"
                            : entry.modelData.known ? "saved"
                            : !menu.secured(entry.modelData) ? "open" : ""
                        color: entry.modelData.connected ? menu.c.forest_text
                            : entry.modelData.stateChanging ? menu.c.teal_text
                            : menu.c.faint
                    }
                }

                // Password box for a new secured network.
                Rectangle {
                    visible: entry.open
                    width: parent.width
                    height: visible ? box.implicitHeight + 20 : 0
                    color: "transparent"
                    border.color: menu.c.line

                    Column {
                        id: box
                        x: 10
                        y: 10
                        width: parent.width - 20
                        spacing: 8

                        Row {
                            width: parent.width
                            spacing: 8

                            Rectangle {
                                width: parent.width - joinButton.width - 8
                                height: 38
                                color: "transparent"
                                border.color: menu.wrong ? menu.c.rust_text : menu.c.forest_text

                                Row {
                                    x: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 10

                                    BarText {
                                        text: "pass"
                                        color: menu.c.dim
                                    }
                                    TextInput {
                                        id: password
                                        width: 220
                                        clip: true
                                        echoMode: TextInput.Password
                                        color: menu.c.fg
                                        selectionColor: menu.c.forest
                                        font.family: Config.font.family
                                        font.pixelSize: Config.font.size
                                        focus: entry.open
                                        onAccepted: entry.join()
                                    }
                                }
                            }
                            PopButton {
                                id: joinButton
                                height: 38
                                kind: "fill"
                                text: "join"
                                onClicked: entry.join()
                            }
                        }

                        BarText {
                            visible: menu.wrong
                            text: "wrong password, try again"
                            color: menu.c.rust_text
                        }
                    }
                }

                onOpenChanged: {
                    if (open) {
                        password.text = "";
                        password.forceActiveFocus();
                    }
                }

                Connections {
                    target: entry.modelData
                    function onConnectionFailed(reason) {
                        if (entry.open)
                            menu.wrong = true;
                    }
                    function onConnectedChanged() {
                        if (entry.modelData.connected && entry.open)
                            menu.joining = null;
                    }
                }
            }
        }
    }

    Divider {}

    MouseArea {
        width: parent.width
        height: more.implicitHeight
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            Quickshell.execDetached(["ghostty", "-e", "nmtui"]);
            menu.dismissed();
        }

        BarText {
            id: more
            text: "more in nmtui \u{F0142}"
            color: menu.c.dim
        }
    }
}
