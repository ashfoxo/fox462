// One clickable line in a dropdown list (networks, devices, outputs, hidden
// windows): an icon, a name, and a note on the right. `selected` gives it the
// highlight (the connected network, the current output).
import QtQuick

MouseArea {
    id: row

    property string icon: ""
    property color iconColor: Config.colors.dim
    property string text: ""
    property color textColor: Config.colors.fg
    property int textFormat: Text.PlainText
    property string note: ""
    property color noteColor: Config.colors.faint
    property bool selected: false

    width: parent ? parent.width : 0
    height: 40
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    Rectangle {
        anchors.fill: parent
        color: row.selected ? Config.colors.surf : "transparent"
    }
    Row {
        x: 10
        width: parent.width - 20 - noteText.implicitWidth
        anchors.verticalCenter: parent.verticalCenter

        BarText {
            id: iconText
            visible: row.icon !== ""
            text: row.icon + " "
            color: row.iconColor
        }
        BarText {
            width: parent.width - (iconText.visible ? iconText.implicitWidth : 0)
            elide: Text.ElideRight
            textFormat: row.textFormat
            text: row.text
            color: row.textColor
        }
    }
    BarText {
        id: noteText
        anchors {
            right: parent.right
            rightMargin: 10
            verticalCenter: parent.verticalCenter
        }
        text: row.note
        color: row.noteColor
    }
}
