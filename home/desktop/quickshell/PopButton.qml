// A button inside a dropdown.
//   kind "accent": green outline (the main action, e.g. reconnect)
//   kind "plain":  grey outline, dim text (secondary, or a toggle that's off)
//   kind "fill":   solid green, bold (a toggle that's on, or join)
//   kind "danger": solid rust, bold (armed: click again to do it)
import QtQuick

MouseArea {
    id: button

    property string text: ""
    property string icon: ""
    property string kind: "plain"
    property bool small: false  // the on/off pills in headers

    implicitHeight: small ? 30 : 42
    implicitWidth: label.implicitWidth + (small ? 30 : 36)
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

    Rectangle {
        anchors.fill: parent
        color: button.kind === "fill" ? Config.colors.forest : button.kind === "danger" ? Config.colors.rust : "transparent"
        border.width: button.kind === "fill" || button.kind === "danger" ? 0 : 1
        border.color: button.kind === "accent" ? Config.colors.forest_text : Config.colors.line
    }

    BarText {
        id: label
        anchors.centerIn: parent
        text: (button.icon !== "" ? button.icon + " " : "") + button.text
        color: button.kind === "plain" ? Config.colors.dim : Config.colors.fg
        font.bold: button.kind === "fill" || button.kind === "danger"
    }
}
