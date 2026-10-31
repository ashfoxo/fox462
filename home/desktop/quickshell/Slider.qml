// A thin slider: click or drag to set, scroll to nudge by 5%.
// `value` is 0–1; `moved(value)` fires on every change you make.
import QtQuick

MouseArea {
    id: slider

    property real value: 0
    property bool dimmed: false
    signal moved(real value)

    function setFrom(x) {
        const v = Math.max(0, Math.min(1, x / width));
        moved(v);
    }

    implicitHeight: 24
    cursorShape: Qt.PointingHandCursor
    onPressed: mouse => setFrom(mouse.x)
    onPositionChanged: mouse => {
        if (pressed)
            setFrom(mouse.x);
    }
    onWheel: wheel => moved(Math.max(0, Math.min(1, value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 4
        color: Config.colors.surf
        opacity: slider.dimmed ? 0.4 : 1

        Rectangle {
            width: parent.width * slider.value
            height: parent.height
            color: Config.colors.forest_text
        }
    }

    Rectangle {
        x: Math.max(0, Math.min(slider.width - width, slider.width * slider.value - width / 2))
        anchors.verticalCenter: parent.verticalCenter
        width: 6
        height: 16
        color: Config.colors.fg
        opacity: slider.dimmed ? 0.4 : 1
    }
}
