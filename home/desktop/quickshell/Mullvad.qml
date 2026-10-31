pragma Singleton

// Mullvad VPN state, live. `mullvad status --json listen` prints the tunnel
// state once, then again on every change, so the bar updates the moment
// the VPN connects or drops, without polling. DAITA and multihop come from
// the settings (`mullvad tunnel get` / `relay get`), re-read whenever the
// daemon says its settings changed.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // connected | connecting | disconnected | disconnecting | error | unknown
    // ("unknown": the mullvad command or daemon isn't there).
    property string state: "unknown"
    property string server: ""    // exit relay, e.g. se-sto-wg-004 (kept while off)
    property string entry: ""     // multihop entry relay
    property string location: ""  // e.g. stockholm, sweden
    property string ip: ""        // public IPv4 as the internet sees it
    property bool daita: false
    property bool multihop: false

    readonly property bool connected: state === "connected"

    function command(args) {
        Quickshell.execDetached(["mullvad"].concat(args));
        settingsSoon.restart();
    }
    // When off, "reconnect" connects.
    function reconnect() {
        command(state === "connected" || state === "connecting" ? ["reconnect"] : ["connect"]);
    }
    function setDaita(on) {
        daita = on;
        command(["tunnel", "set", "daita", on ? "on" : "off"]);
    }
    function setMultihop(on) {
        multihop = on;
        command(["relay", "set", "multihop", on ? "on" : "off"]);
    }

    function parseLine(line) {
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            return;  // plain-text warnings, e.g. "not logged in"
        }
        if (msg.state === undefined) {
            // Not a tunnel state: a settings (or other) event.
            settingsSoon.restart();
            return;
        }
        state = msg.state;
        const loc = msg.details?.location;
        if (loc) {
            ip = loc.ipv4 ?? loc.ipv6 ?? "";
            location = [loc.city, loc.country].filter(x => x).join(", ").toLowerCase();
            if (loc.hostname)
                server = loc.hostname;
            entry = loc.entry_hostname ?? "";
        }
    }

    Process {
        id: listen
        command: ["mullvad", "status", "--json", "listen"]
        running: true
        stdout: SplitParser {
            onRead: line => root.parseLine(line)
        }
        // The daemon restarted or isn't running: try again shortly.
        onExited: {
            root.state = "unknown";
            relisten.start();
        }
    }
    Timer {
        id: relisten
        interval: 3000
        onTriggered: listen.running = true
    }

    Process {
        id: settings
        command: ["sh", "-c", "mullvad tunnel get; mullvad relay get"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const daitaLine = text.match(/DAITA:\s+(\w+)/);
                const hopLine = text.match(/Multihop state:\s+(\w+)/);
                if (daitaLine)
                    root.daita = daitaLine[1] === "true";
                if (hopLine)
                    root.multihop = hopLine[1] === "enabled";
            }
        }
    }
    Timer {
        id: settingsSoon
        interval: 800
        onTriggered: settings.running = true
    }
}
