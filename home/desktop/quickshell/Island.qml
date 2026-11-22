// The island: a pill in the middle of the bar, home of the clock. Things
// that last sit in it: a voice note recording left of the clock, what's
// playing (here or on your other devices) right of it, as just its icon
// until you hover the island. Things that come and go pop out under it
// instead (Popups.qml): notifications, and Osd.qml's volume, brightness and
// quick events. The pill grows and shrinks as things come and go.
// Click what's playing for its dropdown; click "● rec" to stop and transcribe.
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: island

    required property var bar
    // The most the island may take without running into either side.
    property real room: 400
    readonly property Item playingItem: playing

    implicitWidth: pill.width
    implicitHeight: Config.bar.height

    HoverHandler {
        id: hover
    }

    Rectangle {
        id: pill
        anchors.centerIn: parent
        width: row.implicitWidth + 12
        height: parent.height - 6
        radius: height / 2
        color: Config.colors.surf
        // Content shows as the pill grows to it, rather than spilling out.
        clip: true

        Behavior on width {
            NumberAnimation {
                duration: 180
                easing.type: Easing.OutCubic
            }
        }

        Row {
            id: row
            anchors.centerIn: parent

            // ---- voice note recording (voicenotes.nix) ----
            BarButton {
                id: rec
                property bool recording: false

                visible: recording
                text: "● rec"
                bold: true
                color: Config.colors.rust_text
                onClicked: Quickshell.execDetached(["voice-note"])

                Process {
                    id: recCheck
                    command: ["voice-note-status"]
                    stdout: StdioCollector {
                        onStreamFinished: rec.recording = text.includes('"recording"')
                    }
                }
                Timer {
                    interval: 1000
                    running: true
                    repeat: true
                    onTriggered: recCheck.running = true
                }
            }

            BarButton {
                id: clock
                text: Qt.formatTime(clockSource.date, "HH:mm")
                bold: true
                interactive: false
            }

            // ---- what's playing: here, paused here, or on your other devices ----
            // Just the icon until you hover the island (or its dropdown is
            // open). The title then gets what's left of `room` (at most
            // 400px), cut with "…"; under 60px it stays hidden.
            BarButton {
                id: playing
                readonly property bool expanded: (hover.hovered || open) && maxTextWidth >= 60

                visible: Playing.label !== ""
                icon: Playing.barIcon
                text: expanded ? Playing.label : ""
                maxTextWidth: Math.min(400, island.room - clock.width - (rec.visible ? rec.width : 0) - 60)
                color: Playing.playing ? Config.colors.fg : Config.colors.faint
                iconColor: Playing.playing ? Config.colors.forest_text : Config.colors.faint
                open: island.bar.open === "playing"
                onClicked: island.bar.toggle("playing")
            }
        }
    }

    SystemClock {
        id: clockSource
        precision: SystemClock.Minutes
    }
}
