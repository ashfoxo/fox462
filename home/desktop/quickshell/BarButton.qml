// One clickable item on the bar: an optional icon plus optional text.
// Always the full bar height, so a click at the very top edge of the
// screen still lands. `open` fills it green while its dropdown is open.
import QtQuick

MouseArea {
    id: button

    property string icon: ""
    property string text: ""
    property color color: Config.colors.fg
    property color iconColor: color
    property bool bold: false
    property bool open: false
    // Background when not open (e.g. rust while recording).
    property color fill: "transparent"
    // Extra space on the left, to separate groups of items.
    property int gap: 0
    // Status-only items: no hand cursor.
    property bool interactive: true

    implicitWidth: gap + content.implicitWidth + 12
    implicitHeight: Config.bar.height
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: interactive ? Qt.PointingHandCursor : Qt.ArrowCursor

    Rectangle {
        anchors {
            fill: parent
            leftMargin: button.gap
        }
        color: button.open ? Config.colors.forest : button.fill
    }

    Row {
        id: content
        x: button.gap + 6
        anchors.verticalCenter: parent.verticalCenter

        BarText {
            visible: button.icon !== ""
            text: button.icon
            color: button.open ? Config.colors.fg : button.iconColor
        }
        BarText {
            visible: button.text !== ""
            // A space after the icon, in the same mono font.
            text: (button.icon !== "" ? " " : "") + button.text
            color: button.open ? Config.colors.fg : button.color
            font.bold: button.bold || button.open
        }
    }
}
