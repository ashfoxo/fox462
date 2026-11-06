// What's wrong, in a shaded box in a dropdown: wrapped text, rust by default.
import QtQuick

Rectangle {
    property alias text: label.text
    property alias textColor: label.color

    width: parent ? parent.width : 0
    height: label.implicitHeight + 20
    color: Config.colors.surf

    BarText {
        id: label
        x: 10
        y: 10
        width: parent.width - 20
        wrapMode: Text.Wrap
        color: Config.colors.rust_text
    }
}
