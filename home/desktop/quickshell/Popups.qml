// What pops out under the island's clock (Island.qml), centred: first
// Osd.qml's card (volume, brightness, quick events), then notifications,
// newest at the bottom.
// Each notification goes after Config.notifications.popupSeconds (the timer
// waits while the mouse is on it); critical ones stay. Click: open it (see
// Notifs.activate). Right-click: close it.
import QtQuick
import Quickshell
import Quickshell.Wayland

PanelWindow {
    id: root

    required property var bar
    readonly property var c: Config.colors

    screen: bar.screen
    visible: Notifs.popups.length > 0 || Osd.shown
    // Anchored to the top only: layer shell centres it, under the island.
    anchors.top: true
    margins.top: bar.height + 6
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notifications"
    implicitWidth: 440
    implicitHeight: Math.max(1, stack.implicitHeight)
    color: "transparent"
    mask: Region {
        item: stack
    }

    Column {
        id: stack
        width: parent.width
        spacing: 10

        Rectangle {
            visible: Osd.shown
            anchors.horizontalCenter: parent.horizontalCenter
            width: osdRow.implicitWidth + 32
            height: 40
            radius: height / 2
            color: root.c.bg
            border.width: 1
            border.color: root.c.forest

            Row {
                id: osdRow
                anchors.centerIn: parent
                spacing: 10

                BarText {
                    text: Osd.icon
                    color: root.c.dim
                }
                Rectangle {
                    visible: Osd.level >= 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: 140
                    height: 6
                    radius: 3
                    color: root.c.surf

                    Rectangle {
                        width: parent.width * Math.max(0, Osd.level)
                        height: parent.height
                        radius: 3
                        color: root.c.forest_text
                    }
                }
                BarText {
                    text: Osd.text
                }
            }
        }

        Repeater {
            // ScriptModel keeps each popup (and its timer) as others come and go.
            model: ScriptModel {
                values: Notifs.popups
            }

            Rectangle {
                id: popup

                required property var modelData

                width: stack.width
                height: card.implicitHeight
                color: root.c.bg
                border.width: 1
                border.color: modelData.critical ? root.c.rust_text : root.c.forest

                MessageCard {
                    id: card
                    anchors {
                        fill: parent
                        margins: 1
                    }
                    m: popup.modelData
                    highlight: false
                    lines: 3
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton)
                            popup.modelData.n.dismiss();
                        else
                            Notifs.activate(popup.modelData);
                    }
                }

                Timer {
                    interval: Config.notifications.popupSeconds * 1000
                    running: !popup.modelData.critical && !card.containsMouse
                    onTriggered: popup.modelData.n.expire()
                }
            }
        }
    }
}
