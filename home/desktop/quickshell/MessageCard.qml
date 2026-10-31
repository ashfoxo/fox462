// One notification: app (green for chat apps, rust if critical) and
// summary, how long ago on the right, the text under it in dim.
// Used by the popups and the chat menu.
import QtQuick

MouseArea {
    id: card

    required property var m
    property bool highlight: containsMouse
    property int lines: 2

    readonly property var c: Config.colors

    implicitHeight: column.implicitHeight + 20
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    Rectangle {
        anchors.fill: parent
        color: card.highlight ? card.c.surf : "transparent"
    }

    Column {
        id: column
        x: 12
        y: 10
        width: parent.width - 24
        spacing: 4

        Item {
            width: parent.width
            implicitHeight: title.implicitHeight

            BarText {
                id: title
                width: parent.width - age.implicitWidth - 12
                elide: Text.ElideRight
                textFormat: Text.StyledText
                // Escape the summary, it's plain text going into markup.
                text: `<font color="${card.m.critical ? card.c.rust_text : card.m.chat ? card.c.forest_text : card.c.dim}">${card.m.app}</font> `
                    + card.m.summary.replace(/&/g, "&amp;").replace(/</g, "&lt;")
            }
            BarText {
                id: age
                anchors.right: parent.right
                text: Notifs.age(card.m)
                color: card.c.dim
            }
        }
        BarText {
            visible: card.m.body !== ""
            width: parent.width
            text: card.m.body
            color: card.c.dim
            wrapMode: Text.Wrap
            maximumLineCount: card.lines
            elide: Text.ElideRight
        }
    }
}
