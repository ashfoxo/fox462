// Dropdown for a UnitStatus (backup, update): last good run, next scheduled
// run, what the last run did, the error if it failed, and a run-now button
// (asks for your password).
import QtQuick

Dropdown {
    id: menu

    required property var status
    property string menuIcon: ""
    property string menuTitle: ""
    property string okText: "ok"
    property string actionText: ""
    property string busyText: ""

    readonly property var c: Config.colors
    readonly property bool failed: status.state === "failed"
    readonly property bool running: status.state === "running"
    readonly property bool absent: status.state === "absent"
    readonly property var look: ({
            ok: ["● " + okText, c.forest_text],
            uptodate: ["● up to date", c.forest_text],
            running: ["● running…", c.teal_text],
            skipped: ["● skipped", c.amber],
            overdue: ["● overdue", c.amber],
            failed: ["● failed", c.rust_text],
            none: ["● never run yet", c.amber],
            absent: ["● not set up on this machine", c.dim],
            unknown: ["● unknown", c.dim]
        })[status.state] ?? ["● " + status.state, c.dim]

    onVisibleChanged: {
        if (visible)
            status.refresh();
    }

    MenuHeader {
        icon: menu.menuIcon
        iconColor: menu.failed ? menu.c.rust_text : menu.c.dim
        title: menu.menuTitle

        BarText {
            text: menu.look[0]
            color: menu.look[1]
        }
    }

    Column {
        visible: !menu.absent
        spacing: 8

        Field {
            label: menu.failed ? "last ok" : "last"
            value: menu.status.last ? Fmt.ago(menu.status.last * 1000) : "never"
            extra: menu.status.last ? `(${Fmt.time(menu.status.last * 1000)})` : ""
        }
        Field {
            label: "next"
            value: menu.status.next ? Fmt.day(menu.status.next * 1000) : "—"
        }
        Field {
            visible: menu.status.note !== "" && !menu.failed
            label: "note"
            value: menu.status.note
        }
    }

    Rectangle {
        visible: menu.failed
        width: parent.width
        height: errorText.implicitHeight + 20
        color: menu.c.surf

        BarText {
            id: errorText
            x: 10
            y: 10
            width: parent.width - 20
            wrapMode: Text.Wrap
            color: menu.c.rust_text
            text: menu.status.error
        }
    }

    PopButton {
        visible: !menu.absent
        width: parent.width
        enabled: !menu.running
        kind: menu.running ? "plain" : "accent"
        icon: "\u{F0167}"
        text: menu.running ? menu.busyText : menu.actionText
        onClicked: menu.status.start()
    }
}
