pragma Singleton

// VPN, NetBird and backup state, checked every 5s by the qs-health script.
// "unknown" means the tool isn't there or didn't answer.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string vpn: "unknown"      // on | off | unknown
    property string netbird: "unknown"  // up | down | unknown
    property string peers: ""           // "4/5"
    property string backup: "unknown"   // ok | running | overdue | failed | none | unknown
    property int backupAge: 0           // seconds since the last good backup

    function parse(out) {
        for (const line of out.trim().split("\n")) {
            const [key, value, extra] = line.split(" ");
            if (key === "vpn") {
                vpn = value;
            } else if (key === "netbird") {
                netbird = value;
                peers = extra ?? "";
            } else if (key === "backup") {
                backup = value;
                backupAge = Number(extra ?? 0);
            }
        }
    }

    Process {
        id: check
        command: [Config.scripts.health]
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
}
