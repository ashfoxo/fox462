// Mullvad dropdown: server, location and IP, then reconnect, then DAITA
// and multihop (green = on). Same layout whether connected or not; when
// off, reconnect connects.
import QtQuick

Dropdown {
    id: menu

    readonly property var c: Config.colors
    readonly property var look: ({
            connected: ["● connected", c.forest_text],
            connecting: ["● connecting…", c.amber],
            disconnecting: ["● disconnecting…", c.amber],
            disconnected: ["● off", c.rust_text],
            error: ["● error", c.rust_text],
            unknown: ["● not running", c.dim]
        })[Mullvad.state] ?? ["● " + Mullvad.state, c.dim]

    MenuHeader {
        icon: "\u{F0483}"
        iconColor: menu.look[1]
        title: "mullvad"

        BarText {
            text: menu.look[0]
            color: menu.look[1]
        }
    }

    Column {
        spacing: 8

        Field {
            label: "server"
            value: Mullvad.server || "—"
        }
        Field {
            visible: Mullvad.multihop && Mullvad.entry !== ""
            label: "entry"
            value: Mullvad.entry
        }
        Field {
            label: "location"
            value: Mullvad.location || "—"
        }
        Field {
            label: "ip"
            value: Mullvad.ip || "—"
            // The IP is your real one while the VPN is off.
            extra: Mullvad.connected || Mullvad.ip === "" ? "" : "not hidden"
        }
    }

    Divider {}

    PopButton {
        width: parent.width
        kind: "accent"
        icon: "\u{F0450}"
        text: "reconnect"
        onClicked: Mullvad.reconnect()
    }

    Row {
        width: parent.width
        spacing: 12

        PopButton {
            width: (parent.width - 12) / 2
            kind: Mullvad.daita ? "fill" : "plain"
            text: "daita"
            onClicked: Mullvad.setDaita(!Mullvad.daita)
        }
        PopButton {
            width: (parent.width - 12) / 2
            kind: Mullvad.multihop ? "fill" : "plain"
            text: "multihop"
            onClicked: Mullvad.setMultihop(!Mullvad.multihop)
        }
    }
}
