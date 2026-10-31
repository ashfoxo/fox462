// A dropdown's top line: icon + bold title on the left (with an optional
// dim note after it), anything you put inside on the right.
import QtQuick

Item {
    id: header

    property string icon: ""
    property color iconColor: Config.colors.dim
    property string title: ""
    property string note: ""
    default property alias trailing: rightSide.data

    width: parent ? parent.width : 0
    implicitHeight: Math.max(left.implicitHeight, rightSide.implicitHeight)

    Row {
        id: left
        anchors.verticalCenter: parent.verticalCenter

        BarText {
            text: header.icon + " "
            color: header.iconColor
        }
        BarText {
            text: header.title
            font.bold: true
        }
        BarText {
            visible: header.note !== ""
            text: " " + header.note
            color: Config.colors.dim
        }
    }

    Row {
        id: rightSide
        anchors {
            right: parent.right
            verticalCenter: parent.verticalCenter
        }
    }
}
