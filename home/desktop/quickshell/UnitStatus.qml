// State of a timer-driven root job (the backup, the update), from the
// qs-unit script every 10s. StatusItems makes one per job.
import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    required property string unit
    required property var args     // [stamp file] or [stamp file, result file]

    property string state: "unknown"  // ok | uptodate | running | skipped | failed | overdue | none | absent | unknown
    property real last: 0              // unix seconds of the last good run, 0 = never
    property real next: 0              // unix seconds of the next scheduled run, 0 = unknown
    property string note: ""
    property string error: ""

    function refresh() {
        check.running = true;
    }
    // Runs it now. It runs as root, so your polkit agent asks for your password.
    function start() {
        Quickshell.execDetached(["systemctl", "start", "--no-block", unit]);
        refreshSoon.restart();
    }

    function parse(text) {
        const v = { note: "", error: "" };
        for (const line of text.trim().split("\n")) {
            const space = line.indexOf(" ");
            v[line.slice(0, space)] = line.slice(space + 1);
        }
        state = v.state ?? "unknown";
        last = Number(v.last ?? 0);
        next = Number(v.next ?? 0);
        note = v.note;
        error = v.error;
    }

    Process {
        id: check
        command: [Config.scripts.unit, root.unit].concat(root.args)
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }
    Timer {
        interval: 10000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: check.running = true
    }
    Timer {
        id: refreshSoon
        interval: 3000
        onTriggered: check.running = true
    }
}
