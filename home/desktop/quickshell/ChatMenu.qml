// Chat dropdown (+chat on the bar): a button per chat app with its unread
// count (opens its scratchpad, same as Super + C and its letter), then the
// messages that came in, newest first. They stay until you press clear.
import QtQuick
import Quickshell

Dropdown {
    id: menu

    readonly property var c: Config.colors

    function open(pad) {
        Pads.show(pad);
        menu.dismissed();
    }

    Grid {
        width: parent.width
        columns: 2
        spacing: 8

        Repeater {
            model: Pads.chats

            MouseArea {
                id: app

                required property var modelData
                readonly property int count: Notifs.unread(modelData.name)
                readonly property bool running: Pads.isRunning(modelData)

                width: (parent.width - 8) / 2
                height: 38
                cursorShape: Qt.PointingHandCursor
                onClicked: menu.open(modelData)

                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    border.width: 1
                    border.color: menu.c.line
                }
                Row {
                    anchors.centerIn: parent

                    BarText {
                        text: app.modelData.name
                        color: !app.running ? menu.c.faint : app.count > 0 ? menu.c.fg : menu.c.dim
                    }
                    BarText {
                        visible: app.count > 0
                        text: " " + app.count
                        color: menu.c.teal_text
                        font.bold: true
                    }
                }
            }
        }
    }

    Divider {}

    BarText {
        visible: Notifs.chats.length === 0
        text: "no messages"
        color: menu.c.dim
    }

    ListView {
        visible: Notifs.chats.length > 0
        width: parent.width
        height: Math.min(contentHeight, 380)
        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        model: ScriptModel {
            values: Notifs.chats
        }

        delegate: MessageCard {
            required property var modelData
            width: ListView.view.width
            m: modelData
            lines: 1
            onClicked: menu.open(Pads.find(modelData.chat))
        }
    }

    Item {
        visible: Notifs.chats.length > 0
        width: parent.width
        implicitHeight: clear.implicitHeight

        PopButton {
            id: clear
            anchors.right: parent.right
            small: true
            text: "clear"
            onClicked: Notifs.clear()
        }
    }
}
