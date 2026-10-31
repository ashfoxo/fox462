// Month calendar under the clock, `cal` style. Arrows change month; it
// always opens on the current one.
import QtQuick

Dropdown {
    id: popup

    property int year: 0
    property int month: 0  // 0 = january

    // Day-name row, then blanks up to the 1st, then the days.
    readonly property var cells: {
        const names = ["su", "mo", "tu", "we", "th", "fr", "sa"].map(t => ({ text: t, kind: "head" }));
        const first = new Date(year, month, 1).getDay();
        const days = new Date(year, month + 1, 0).getDate();
        const now = new Date();
        const isThisMonth = now.getFullYear() === year && now.getMonth() === month;
        const blanks = Array.from({ length: first }, () => ({ text: "", kind: "blank" }));
        const dates = Array.from({ length: days }, (_, i) => ({
            text: String(i + 1),
            kind: isThisMonth && now.getDate() === i + 1 ? "today" : "day"
        }));
        return names.concat(blanks, dates);
    }

    function shift(by) {
        const d = new Date(year, month + by, 1);
        year = d.getFullYear();
        month = d.getMonth();
    }

    panelWidth: 360

    onVisibleChanged: {
        if (visible) {
            const d = new Date();
            year = d.getFullYear();
            month = d.getMonth();
        }
    }

    Item {
        width: parent.width
        height: title.implicitHeight

        MouseArea {
            width: 24
            height: parent.height
            cursorShape: Qt.PointingHandCursor
            onClicked: popup.shift(-1)

            BarText {
                text: "\u{F0141}"
                color: Config.colors.dim
            }
        }
        BarText {
            id: title
            anchors.horizontalCenter: parent.horizontalCenter
            text: new Date(popup.year, popup.month, 1)
                .toLocaleDateString(Qt.locale("en_US"), "MMMM yyyy").toLowerCase()
            font.bold: true
        }
        MouseArea {
            anchors.right: parent.right
            width: 24
            height: parent.height
            cursorShape: Qt.PointingHandCursor
            onClicked: popup.shift(1)

            BarText {
                anchors.right: parent.right
                text: "\u{F0142}"
                color: Config.colors.dim
            }
        }
    }

    Grid {
        columns: 7
        rowSpacing: 4

        Repeater {
            model: popup.cells

            Rectangle {
                required property var modelData

                width: popup.panelWidth / 7 - 44 / 7
                height: 26
                color: modelData.kind === "today" ? Config.colors.forest : "transparent"

                BarText {
                    anchors.centerIn: parent
                    text: parent.modelData.text
                    color: parent.modelData.kind === "head" ? Config.colors.dim : Config.colors.fg
                    font.bold: parent.modelData.kind === "today"
                }
            }
        }
    }
}
