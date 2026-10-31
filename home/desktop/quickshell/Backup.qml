pragma Singleton

// Backup (restic) state from the qs-backup script, every 10s.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string state: "unknown"  // ok | running | overdue | failed | none | unknown
    property real last: 0              // unix seconds of the last good backup, 0 = never
    property real next: 0              // unix seconds of the next scheduled run, 0 = unknown
    property string error: ""

    function refresh() {
        check.running = true;
    }
    // Starts the backup now. It runs as root, so your polkit agent asks
    // for your password.
    function start() {
        Quickshell.execDetached(["systemctl", "start", "--no-block", "restic-backups-s3"]);
        refreshSoon.restart();
    }

    function parse(text) {
        let err = "";
        for (const line of text.trim().split("\n")) {
            const space = line.indexOf(" ");
            const key = line.slice(0, space);
            const value = line.slice(space + 1);
            if (key === "state")
                state = value;
            else if (key === "last")
                last = Number(value);
            else if (key === "next")
                next = Number(value);
            else if (key === "error")
                err = value;
        }
        error = err;
    }

    Process {
        id: check
        command: [Config.scripts.backup]
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
