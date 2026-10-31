// NetBird dropdown: up/down switch, then each peer (online first) with how
// it's reached, or what's wrong when NetBird is down.
import QtQuick

Dropdown {
    id: menu

    readonly property var c: Config.colors
    readonly property int maxPeers: 10

    onVisibleChanged: {
        if (visible)
            NetBird.refresh();
    }

    MenuHeader {
        icon: "\u{F06F3}"
        iconColor: NetBird.down ? menu.c.amber : menu.c.dim
        title: "netbird"
        note: NetBird.status === "unknown" ? "" : `${NetBird.online}/${NetBird.total} peers`

        PopButton {
            visible: NetBird.status !== "unknown"
            small: true
            kind: NetBird.up ? "fill" : "plain"
            text: NetBird.up ? "up" : NetBird.off ? "off" : "down"
            onClicked: NetBird.setUp(!NetBird.up)
        }
    }

    // ---- up: the peers ----
    Column {
        visible: NetBird.up
        width: parent.width
        spacing: 10

        Repeater {
            model: NetBird.peers.slice(0, menu.maxPeers)

            Item {
                required property var modelData

                width: parent.width
                height: name.implicitHeight

                Row {
                    BarText {
                        text: modelData.online ? "● " : "○ "
                        color: modelData.online ? menu.c.forest_text : menu.c.faint
                    }
                    BarText {
                        id: name
                        text: modelData.name
                        color: modelData.online ? menu.c.fg : menu.c.dim
                    }
                }
                BarText {
                    anchors.right: parent.right
                    text: modelData.online ? modelData.kind : (modelData.since ? "offline " + Fmt.duration((Date.now() - modelData.since) / 1000) : "offline")
                    color: modelData.online ? menu.c.dim : menu.c.faint
                }
            }
        }

        BarText {
            visible: NetBird.peers.length > menu.maxPeers
            text: `+${NetBird.peers.length - menu.maxPeers} more`
            color: menu.c.dim
        }
    }

    BarText {
        visible: NetBird.up && NetBird.ip !== ""
        text: "this device <font color=\"" + menu.c.fg + "\">" + NetBird.ip + "</font>"
        textFormat: Text.StyledText
        color: menu.c.dim
    }

    // ---- switched off ----
    BarText {
        visible: NetBird.off
        text: "switched off"
        color: menu.c.dim
    }

    // ---- down: what's wrong ----
    Rectangle {
        visible: NetBird.down
        width: parent.width
        height: problem.implicitHeight + 20
        color: menu.c.surf

        BarText {
            id: problem
            x: 10
            y: 10
            width: parent.width - 20
            wrapMode: Text.Wrap
            color: menu.c.amber
            text: NetBird.needsLogin ? "needs login: run netbird-wt0 up in a terminal"
                : NetBird.error !== "" ? NetBird.error
                : "status: " + NetBird.status.toLowerCase()
        }
    }
    Field {
        visible: NetBird.down
        label: "last up"
        value: NetBird.lastUp ? Fmt.ago(NetBird.lastUp) : "—"
    }
    PopButton {
        visible: NetBird.down
        width: parent.width
        kind: "accent"
        icon: "\u{F0450}"
        text: "retry now"
        onClicked: NetBird.setUp(true)
    }

    // ---- not answering ----
    BarText {
        visible: NetBird.status === "unknown"
        text: "netbird isn't answering"
        color: menu.c.dim
    }
}
