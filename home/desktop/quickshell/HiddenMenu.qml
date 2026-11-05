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

            ListRow {
                required property var modelData

                selected: containsMouse
                textFormat: Text.StyledText
                // App in green, then the window title. Escaped: titles are
                // plain text going into markup.
                text: `<font color="${menu.c.forest_text}">${(modelData.wayland?.appId ?? modelData.lastIpcObject?.class ?? "").toLowerCase()}</font> `
                    + modelData.title.replace(/&/g, "&amp;").replace(/</g, "&lt;")
                onClicked: {
                    Pads.unhide(modelData);
                    if (Pads.hidden.length <= 1)
                        menu.dismissed();
                }
            }
        }
    }
}
