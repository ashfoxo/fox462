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
    SliderRow {
        icon: menu.muted ? "\u{F0581}" : "\u{F057E}"
        iconColor: menu.muted ? menu.c.amber : menu.c.dim
        clickable: true
        value: menu.volume
        dimmed: menu.muted
        valueText: menu.muted ? "muted" : `${Math.round(menu.volume * 100)}%`
        valueColor: menu.muted ? menu.c.amber : menu.c.fg
        onIconClicked: {
            if (menu.sink?.audio)
                menu.sink.audio.muted = !menu.muted;
        }
        onMoved: v => {
            if (menu.sink?.audio)
                menu.sink.audio.volume = v;
        }
    }

    // ---- brightness (laptop screen only) ----
    SliderRow {
        visible: Brightness.available
        icon: "\u{F00DF}"
        value: Brightness.value
        onMoved: v => Brightness.set(v)
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

            ListRow {
                required property var modelData
                readonly property bool current: modelData === menu.sink

                selected: current
                icon: current ? "●" : "○"
                iconColor: current ? menu.c.forest_text : menu.c.faint
                text: menu.label(modelData)
                textColor: current ? menu.c.fg : menu.c.dim
                onClicked: Pipewire.preferredDefaultAudioSink = modelData
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
