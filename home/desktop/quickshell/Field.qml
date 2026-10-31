// A "label   value" line in a dropdown, e.g. "server   se-sto-wg-004".
import QtQuick

Row {
    property string label: ""
    property string value: ""
    property color valueColor: Config.colors.fg
    property string extra: ""  // dim text after the value

    BarText {
        width: 110
        text: parent.label
        color: Config.colors.dim
    }
    BarText {
        text: parent.value
        color: parent.valueColor
    }
    BarText {
        visible: parent.extra !== ""
        text: " " + parent.extra
        color: Config.colors.dim
    }
}
