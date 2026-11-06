pragma Singleton

// What's playing. Here: every MPRIS player (Feishin, browsers, mpv), which
// the dropdown can control. Elsewhere: your Navidrome and Audiobookshelf
// playback on other devices, from the qs-nowplaying script every 15s,
// shown but not controllable (neither server can pause another device).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

Singleton {
    id: root

    // Players here with a track loaded, playing ones first.
    readonly property var local: Mpris.players.values
        .filter(p => p.trackTitle)
        .sort((a, b) => b.isPlaying - a.isPlaying)
    // [{ src: "music" | "spoken", title, artist, player, position, duration }]
    property var polled: []
    // Feishin here reports to Navidrome too, so drop what's playing here.
    readonly property var remote: polled.filter(r => !local.some(p => p.trackTitle === r.title))

    readonly property var playingHere: local.find(p => p.isPlaying) ?? null
    readonly property bool playing: playingHere !== null || remote.length > 0
    // The bar's text: playing here, else elsewhere, else paused here.
    readonly property string label: playingHere ? line(playingHere.trackArtist, playingHere.trackTitle)
        : remote.length > 0 ? line(remote[0].artist, remote[0].title)
        : local.length > 0 ? line(local[0].trackArtist, local[0].trackTitle)
        : ""

    function line(artist, title) {
        return artist ? `${artist} – ${title}` : title;
    }

    Process {
        id: poll
        command: [Config.scripts.nowplaying]
        stdout: StdioCollector {
            onStreamFinished: root.polled = text.split("\n").filter(l => l !== "").map(l => JSON.parse(l))
        }
    }
    Timer {
        interval: 15000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: poll.running = true
    }
}
