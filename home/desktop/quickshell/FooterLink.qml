// A dropdown's last line: dim text you click, e.g. "more in nmtui ›".
import QtQuick

MouseArea {
    property alias text: label.text

    width: parent ? parent.width : 0
    height: label.implicitHeight
    cursorShape: Qt.PointingHandCursor

    BarText {
        id: label
        color: Config.colors.dim
    }
}
