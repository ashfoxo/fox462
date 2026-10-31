// Volume dropdown: volume and brightness sliders, which output plays the
// sound (speakers, headphones...), and mic mute. Click the speaker icon to
// mute or unmute.
import QtQuick
import Quickshell.Services.Pipewire

Dropdown {
    id: menu

    readonly property var c: Config.colors
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool micMuted: source?.audio?.muted ?? false
    // Real output devices (not app streams).
    readonly property var outputs: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream && n.audio)

    function label(node) {
        return (node.description || node.nickname || node.name).toLowerCase();
    }

    onVisibleChanged: {
        if (visible)
            Brightness.refresh();
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    // ---- volume ----
    Row {
        width: parent.width
        spacing: 12

        MouseArea {
            width: 24
            height: 24
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (menu.sink?.audio)
                    menu.sink.audio.muted = !menu.muted;
            }

            BarText {
                anchors.centerIn: parent
                text: menu.muted ? "\u{F0581}" : "\u{F057E}"
                color: menu.muted ? menu.c.amber : menu.c.dim
            }
        }
        Slider {
            width: parent.width - 24 - 64 - 24
            value: menu.volume
            dimmed: menu.muted
            onMoved: v => {
                if (menu.sink?.audio)
                    menu.sink.audio.volume = v;
            }
        }
        BarText {
            width: 64
            horizontalAlignment: Text.AlignRight
            anchors.verticalCenter: parent.verticalCenter
            text: menu.muted ? "muted" : `${Math.round(menu.volume * 100)}%`
            color: menu.muted ? menu.c.amber : menu.c.fg
        }
    }

    // ---- brightness (laptop screen only) ----
    Row {
        visible: Brightness.available
        width: parent.width
        spacing: 12

        BarText {
            width: 24
            horizontalAlignment: Text.AlignHCenter
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{F00DF}"
            color: menu.c.dim
        }
        Slider {
            width: parent.width - 24 - 64 - 24
            value: Brightness.value
            onMoved: v => Brightness.set(v)
        }
        BarText {
            width: 64
            horizontalAlignment: Text.AlignRight
            anchors.verticalCenter: parent.verticalCenter
            text: `${Math.round(Brightness.value * 100)}%`
        }
    }

    Divider {}

    // ---- output ----
    BarText {
        text: "output"
        color: menu.c.dim
    }
    Column {
        width: parent.width

        Repeater {
            model: menu.outputs

            MouseArea {
                id: row

                required property var modelData
                readonly property bool current: modelData === menu.sink

                width: parent.width
                height: 38
                cursorShape: Qt.PointingHandCursor
                onClicked: Pipewire.preferredDefaultAudioSink = modelData

                Rectangle {
                    anchors.fill: parent
                    color: row.current ? menu.c.surf : "transparent"
                }
                Row {
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter

                    BarText {
                        text: row.current ? "● " : "○ "
                        color: row.current ? menu.c.forest_text : menu.c.faint
                    }
                    BarText {
                        width: menu.panelWidth - 100
                        elide: Text.ElideRight
                        text: menu.label(row.modelData)
                        color: row.current ? menu.c.fg : menu.c.dim
                    }
                }
            }
        }
    }

    // ---- mic (hidden if the default input has no volume controls) ----
    Item {
        visible: (menu.source?.audio ?? null) !== null
        width: parent.width
        height: micButton.height

        Row {
            anchors.verticalCenter: parent.verticalCenter

            BarText {
                text: (menu.micMuted ? "\u{F036D}" : "\u{F036C}") + " "
                color: menu.micMuted ? menu.c.rust_text : menu.c.dim
            }
            BarText {
                text: "mic"
            }
        }
        PopButton {
            id: micButton
            anchors.right: parent.right
            small: true
            kind: "plain"
            text: menu.micMuted ? "unmute" : "mute"
            onClicked: {
                if (menu.source?.audio)
                    menu.source.audio.muted = !menu.micMuted;
            }
        }
    }
}
