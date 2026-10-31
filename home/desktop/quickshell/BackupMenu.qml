// Backup dropdown: last good backup, next scheduled run, the error if the
// last run failed, and a "back up now" button (asks for your password).
import QtQuick

Dropdown {
    id: menu

    readonly property var c: Config.colors
    readonly property bool failed: Backup.state === "failed"
    readonly property bool running: Backup.state === "running"
    readonly property var look: ({
            ok: ["● ok", c.forest_text],
            running: ["● running…", c.teal_text],
            overdue: ["● overdue", c.amber],
            failed: ["● failed", c.rust_text],
            none: ["● no backup yet", c.amber],
            unknown: ["● unknown", c.dim]
        })[Backup.state] ?? ["● " + Backup.state, c.dim]

    onVisibleChanged: {
        if (visible)
            Backup.refresh();
    }

    MenuHeader {
        icon: "\u{F006F}"
        iconColor: menu.failed ? menu.c.rust_text : menu.c.dim
        title: "backup"

        BarText {
            text: menu.look[0]
            color: menu.look[1]
        }
    }

    Column {
        spacing: 8

        Field {
            label: menu.failed ? "last ok" : "last"
            value: Backup.last ? Fmt.ago(Backup.last * 1000) : "never"
            extra: Backup.last ? `(${Fmt.time(Backup.last * 1000)})` : ""
        }
        Field {
            label: "next"
            value: Backup.next ? Fmt.day(Backup.next * 1000) : "—"
        }
        Field {
            label: "to"
            value: "s3"
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
            text: Backup.error
        }
    }

    PopButton {
        width: parent.width
        enabled: !menu.running
        kind: menu.running ? "plain" : "accent"
        icon: "\u{F0167}"
        text: menu.running ? "backing up…" : "back up now"
        onClicked: Backup.start()
    }
}
