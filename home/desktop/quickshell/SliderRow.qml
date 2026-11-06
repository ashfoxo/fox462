// A dropdown row: an icon, a slider, and its value on the right (volume,
// brightness, a track's progress). `iconClicked` fires when the icon is
// clicked, if `clickable`; `moved(value)` when you change the slider.
import QtQuick

Row {
    id: row

    property string icon: ""
    property color iconColor: Config.colors.dim
    property bool clickable: false
    property real value: 0
    property bool dimmed: false
    property string valueText: `${Math.round(value * 100)}%`
    property color valueColor: Config.colors.fg
    signal moved(real value)
    signal iconClicked

    width: parent ? parent.width : 0
    spacing: 12

    MouseArea {
        width: 24
        height: 24
        cursorShape: row.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (row.clickable)
                row.iconClicked();
        }

        BarText {
            anchors.centerIn: parent
            text: row.icon
            color: row.iconColor
        }
    }
    Slider {
        width: parent.width - 24 - 64 - 24
        value: row.value
        dimmed: row.dimmed
        onMoved: v => row.moved(v)
    }
    BarText {
        width: 64
        horizontalAlignment: Text.AlignRight
        anchors.verticalCenter: parent.verticalCenter
        text: row.valueText
        color: row.valueColor
    }
}
