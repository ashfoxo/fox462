// A few little bars that bounce while `running` and lie flat while not:
// "this is playing". Decoration only, it doesn't follow the sound.
import QtQuick

Row {
    id: root

    property bool running: false
    readonly property real low: height * 0.25

    height: 14
    spacing: 2

    Repeater {
        model: 4

        Rectangle {
            id: bar

            required property int index
            property real level: root.low

            anchors.bottom: parent.bottom
            width: 3
            height: root.running ? level : root.low
            color: root.running ? Config.colors.forest_text : Config.colors.faint

            // Each bar at its own speed, so they don't move in step.
            SequentialAnimation on level {
                running: root.running
                loops: Animation.Infinite
                NumberAnimation { to: root.height; duration: 280 + bar.index * 90; easing.type: Easing.InOutSine }
                NumberAnimation { to: root.low; duration: 280 + bar.index * 90; easing.type: Easing.InOutSine }
            }
        }
    }
}
