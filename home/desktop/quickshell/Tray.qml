// Tray icons, folded away behind an arrow. Click the arrow to show them.
// Left click activates an app (or opens its menu, if that's all it has);
// right click opens its menu.
import QtQuick
import Quickshell.Services.SystemTray
import Quickshell.Widgets

Row {
    id: root

    required property var bar
    property bool expanded: false

    height: Config.bar.height

    Item {
        width: 18
        height: 1
    }

    Rectangle {
        visible: root.expanded
        width: icons.implicitWidth + 20
        height: parent.height
        color: "transparent"

        // Thin dividers either side of the open tray.
        Rectangle {
            width: 1
            height: parent.height
            color: Config.colors.surf
        }
        Rectangle {
            anchors.right: parent.right
            width: 1
            height: parent.height
            color: Config.colors.surf
        }

        Row {
            id: icons
            anchors.centerIn: parent
            spacing: 12

            Repeater {
                model: SystemTray.items

                MouseArea {
                    required property var modelData

                    width: 18
                    height: Config.bar.height
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton || modelData.onlyMenu) {
                            const p = mapToItem(null, 0, height);
                            modelData.display(root.bar, p.x, p.y);
                        } else {
                            modelData.activate();
                        }
                    }

                    IconImage {
                        anchors.centerIn: parent
                        source: parent.modelData.icon
                        implicitSize: 18
                    }
                }
            }
        }
    }

    BarButton {
        icon: root.expanded ? "\u{F0142}" : "\u{F0141}"
        color: Config.colors.dim
        onClicked: root.expanded = !root.expanded
    }
}
