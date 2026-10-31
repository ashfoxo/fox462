pragma Singleton

// NetBird state from `netbird-wt0 status --json`, every 5s (and right away
// when its dropdown opens or you switch it up/down).
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // The daemon's own word: Connected | Idle (switched off) | Connecting |
    // NeedsLogin | LoginFailed | SessionExpired. "unknown" if netbird-wt0
    // isn't there or the daemon didn't answer.
    property string status: "unknown"
    property int total: 0
    property int online: 0
    // [{ name, online, kind: "direct" | "relayed", since: unix ms }]
    property var peers: []
    property string ip: ""     // this machine's NetBird address
    property string error: ""  // why management is unreachable, if it is
    // When it was last seen up (unix ms), for the "down" view.
    property real lastUp: 0

    readonly property bool up: status === "Connected"
    readonly property bool off: status === "Idle"
    readonly property bool needsLogin: ["NeedsLogin", "LoginFailed", "SessionExpired"].includes(status)
    // Anything else that isn't up or deliberately off is a problem.
    readonly property bool down: !up && !off && status !== "unknown"

    function refresh() {
        check.running = true;
    }
    function setUp(on) {
        Quickshell.execDetached(["netbird-wt0", on ? "up" : "down"]);
        refreshSoon.restart();
    }

    function parse(text) {
        let s;
        try {
            s = JSON.parse(text);
        } catch (e) {
            status = "unknown";
            return;
        }
        status = s.daemonStatus || (s.management?.connected ? "Connected" : "Idle");
        total = s.peers?.total ?? 0;
        online = s.peers?.connected ?? 0;
        ip = (s.netbirdIp ?? "").split("/")[0];
        error = s.management?.error ?? "";
        peers = (s.peers?.details ?? [])
            .map(p => ({
                name: (p.fqdn || p.netbirdIp || "?").split(".")[0],
                online: p.status === "Connected",
                kind: p.connectionType === "Relayed" ? "relayed" : "direct",
                since: Date.parse(p.lastStatusUpdate) || 0
            }))
            .sort((a, b) => (b.online - a.online) || a.name.localeCompare(b.name));
        if (up)
            lastUp = Date.now();
    }

    Process {
        id: check
        command: ["netbird-wt0", "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }
    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: check.running = true
    }
    Timer {
        id: refreshSoon
        interval: 1500
        onTriggered: check.running = true
    }
}
