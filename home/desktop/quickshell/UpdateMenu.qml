// Update dropdown: last good run, next scheduled run, why a run was skipped,
// the error if it failed, and an "update now" button (asks for your password).
// The update is built for the next boot; it is never switched to while you work.
import QtQuick

Dropdown {
    id: menu

    readonly property var c: Config.colors
    readonly property bool failed: Update.state === "failed"
    readonly property bool running: Update.state === "running"
    readonly property bool absent: Update.state === "absent"
    readonly property var look: ({
            ok: ["● built, applies at next boot", c.forest_text],
            uptodate: ["● up to date", c.forest_text],
            running: ["● running…", c.teal_text],
            skipped: ["● skipped", c.amber],
            overdue: ["● overdue", c.amber],
            failed: ["● failed", c.rust_text],
            none: ["● no update yet", c.amber],
            absent: ["● not set up on this machine", c.dim],
            unknown: ["● unknown", c.dim]
        })[Update.state] ?? ["● " + Update.state, c.dim]

    onVisibleChanged: {
        if (visible)
            Update.refresh();
    }

    MenuHeader {
        icon: "\u{F06B0}"
        iconColor: menu.failed ? menu.c.rust_text : menu.c.dim
        title: "update"

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
            value: Update.last ? Fmt.ago(Update.last * 1000) : "never"
            extra: Update.last ? `(${Fmt.time(Update.last * 1000)})` : ""
        }
        Field {
            label: "next"
            value: Update.next ? Fmt.day(Update.next * 1000) : "—"
        }
        Field {
            visible: Update.note !== ""
            label: "note"
            value: Update.note
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
            text: Update.error
        }
    }

    PopButton {
        visible: !menu.absent
        width: parent.width
        enabled: !menu.running
        kind: menu.running ? "plain" : "accent"
        icon: "\u{F0167}"
        text: menu.running ? "updating…" : "update now"
        onClicked: Update.start()
    }
}
