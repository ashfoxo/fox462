// Now playing dropdown: each player here (title, artist · player, previous
// and next, play-pause on the icon, seekable progress), then what's playing
// on your other devices (Navidrome, Audiobookshelf), read-only.
import QtQuick

Dropdown {
    id: menu

    readonly property var c: Config.colors

    // MPRIS doesn't push position changes, so ask while open.
    Timer {
        interval: 1000
        running: menu.visible
        repeat: true
        onTriggered: Playing.local.forEach(p => p.positionChanged())
    }

    MenuHeader {
        icon: "\u{F075A}"
        title: "now playing"
    }

    Repeater {
        model: Playing.local

        Column {
            id: player

            required property var modelData
            readonly property var p: modelData

            width: parent.width
            spacing: 8

            Item {
                width: parent.width
                height: Math.max(names.implicitHeight, buttons.implicitHeight)

                Column {
                    id: names
                    width: parent.width - buttons.width - 12

                    BarText {
                        width: parent.width
                        elide: Text.ElideRight
                        font.bold: true
                        text: player.p.trackTitle
                    }
                    BarText {
                        width: parent.width
                        elide: Text.ElideRight
                        color: menu.c.dim
                        text: [player.p.trackArtist, player.p.identity.toLowerCase()].filter(x => x).join(" · ")
                    }
                }
                Row {
                    id: buttons
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: 8

                    PopButton {
                        visible: player.p.canGoPrevious
                        small: true
                        text: "\u{F04AE}"
                        onClicked: player.p.previous()
                    }
                    PopButton {
                        visible: player.p.canGoNext
                        small: true
                        text: "\u{F04AD}"
                        onClicked: player.p.next()
                    }
                }
            }
            SliderRow {
                icon: player.p.isPlaying ? "\u{F03E4}" : "\u{F040A}"
                iconColor: player.p.isPlaying ? menu.c.forest_text : menu.c.dim
                clickable: player.p.canTogglePlaying
                value: player.p.length > 0 ? player.p.position / player.p.length : 0
                dimmed: !player.p.isPlaying
                valueText: Fmt.clock(player.p.position)
                onIconClicked: player.p.togglePlaying()
                onMoved: v => {
                    if (player.p.canSeek)
                        player.p.position = v * player.p.length;
                }
            }
        }
    }

    Divider {
        visible: Playing.local.length > 0 && Playing.remote.length > 0
    }

    Repeater {
        model: Playing.remote

        Column {
            required property var modelData

            width: parent.width

            BarText {
                width: parent.width
                elide: Text.ElideRight
                font.bold: true
                text: (modelData.src === "spoken" ? "\u{F02CB} " : "\u{F075A} ") + modelData.title
            }
            BarText {
                width: parent.width
                elide: Text.ElideRight
                color: menu.c.dim
                text: [
                    modelData.artist,
                    (modelData.player || modelData.src).toLowerCase(),
                    modelData.position >= 0 ? `${Fmt.clock(modelData.position)} / ${Fmt.clock(modelData.duration)}` : ""
                ].filter(x => x).join(" · ")
            }
        }
    }
}
