// Now playing dropdown: each player here (cover, title, artist · player,
// previous and next, play-pause on the icon, seekable progress), then what's
// playing on your other devices (Navidrome, Audiobookshelf, Jellyfin), read-only.
// The little bars bounce while a track plays.
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
                height: Math.max(art.height, names.implicitHeight, buttons.implicitHeight)

                Image {
                    id: art
                    visible: status === Image.Ready
                    width: visible ? 48 : 0
                    height: width
                    anchors.verticalCenter: parent.verticalCenter
                    source: player.p.trackArtUrl ?? ""
                    sourceSize: Qt.size(96, 96)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                Column {
                    id: names
                    x: art.width > 0 ? art.width + 12 : 0
                    width: parent.width - x - buttons.width - 12
                    anchors.verticalCenter: parent.verticalCenter

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

                    Bounce {
                        anchors.verticalCenter: parent.verticalCenter
                        running: menu.visible && player.p.isPlaying
                    }
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

        Item {
            id: remote

            required property var modelData

            width: parent.width
            height: Math.max(remoteArt.height, remoteNames.implicitHeight)

            Image {
                id: remoteArt
                visible: status === Image.Ready
                width: visible ? 48 : 0
                height: width
                anchors.verticalCenter: parent.verticalCenter
                source: remote.modelData.cover ? "file://" + remote.modelData.cover : ""
                sourceSize: Qt.size(96, 96)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            Column {
                id: remoteNames
                x: remoteArt.width > 0 ? remoteArt.width + 12 : 0
                width: parent.width - x - remoteBounce.width - 12
                anchors.verticalCenter: parent.verticalCenter

                BarText {
                    width: parent.width
                    elide: Text.ElideRight
                    font.bold: true
                    text: Playing.icon(remote.modelData.src) + " " + remote.modelData.title
                }
                BarText {
                    width: parent.width
                    elide: Text.ElideRight
                    color: menu.c.dim
                    text: [
                        remote.modelData.artist,
                        (remote.modelData.player || remote.modelData.src).toLowerCase(),
                        remote.modelData.position >= 0 ? `${Fmt.clock(remote.modelData.position)} / ${Fmt.clock(remote.modelData.duration)}` : ""
                    ].filter(x => x).join(" · ")
                }
            }
            // Everything listed here is playing (paused ones drop off the server's list).
            Bounce {
                id: remoteBounce
                anchors {
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                running: menu.visible
            }
        }
    }
}
