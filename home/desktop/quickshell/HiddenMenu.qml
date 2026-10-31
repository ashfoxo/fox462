// Hidden windows (Super + X): click one to bring it back onto the
// workspace you're on.
import QtQuick
import Quickshell

Dropdown {
    id: menu

    readonly property var c: Config.colors

    MenuHeader {
        icon: "\u{F0209}"
        title: "hidden"
        note: "super + x hides"
    }

    Column {
        width: parent.width

        Repeater {
            model: Pads.hidden

            MouseArea {
                id: row

                required property var modelData

                width: parent.width
                height: 42
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Pads.unhide(modelData);
                    if (Pads.hidden.length <= 1)
                        menu.dismissed();
                }

                Rectangle {
                    anchors.fill: parent
                    color: row.containsMouse ? menu.c.surf : "transparent"
                }
                BarText {
                    x: 10
                    width: parent.width - 20
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideRight
                    textFormat: Text.StyledText
                    // App in green, then the window title. Escaped: titles
                    // are plain text going into markup.
                    text: `<font color="${menu.c.forest_text}">${(row.modelData.wayland?.appId ?? row.modelData.lastIpcObject?.class ?? "").toLowerCase()}</font> `
                        + row.modelData.title.replace(/&/g, "&amp;").replace(/</g, "&lt;")
                }
            }
        }
    }
}
