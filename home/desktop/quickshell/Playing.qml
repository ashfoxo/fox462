pragma Singleton

// What's playing. Here: every MPRIS player (Feishin, Jellyfin, browsers,
// mpv), which the dropdown can control. Elsewhere: your Navidrome,
// Audiobookshelf and Jellyfin playback on other devices, from the
// qs-nowplaying script every 15s, shown but not controllable.
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
    // [{ src: "music" | "spoken" | "video", title, artist, player, position, duration, cover }]
    property var polled: []
    // Feishin and Jellyfin here report to their servers too, so drop what's playing here.
    readonly property var remote: polled.filter(r => !local.some(p => p.trackTitle === r.title))

    readonly property var playingHere: local.find(p => p.isPlaying) ?? null
    readonly property bool playing: playingHere !== null || remote.length > 0
    // The bar's text: playing here, else elsewhere, else paused here.
    readonly property string label: playingHere ? line(playingHere.trackArtist, playingHere.trackTitle)
        : remote.length > 0 ? line(remote[0].artist, remote[0].title)
        : local.length > 0 ? line(local[0].trackArtist, local[0].trackTitle)
        : ""

    // The bar's icon follows whatever its text shows: a film, a book or a note.
    readonly property string barIcon: icon(playingHere ? srcOf(playingHere)
        : remote.length > 0 ? remote[0].src
        : local.length > 0 ? srcOf(local[0])
        : "music")

    // What a player here is playing. Its server knows (Jellyfin, Navidrome
    // and Audiobookshelf list it too, under the same title); failing that,
    // the Jellyfin app means video and anything else counts as music.
    function srcOf(p) {
        const match = polled.find(r => r.title === p.trackTitle);
        return match ? match.src : /jellyfin/i.test(p.identity) ? "video" : "music";
    }

    function icon(src) {
        return src === "spoken" ? "\u{F02CB}" : src === "video" ? "\u{F0381}" : "\u{F075A}";
    }

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
