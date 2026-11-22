pragma Singleton

// Screen brightness through brightnessctl (the same tool as the brightness
// keys). Read when the brightness keys tell the island (Osd.qml).
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool available: false
    property real value: 0  // 0–1
    signal updated  // after each read, even when the value didn't change

    function refresh() {
        read.running = true;
    }

    // `brightnessctl -m` prints e.g. "intel_backlight,backlight,12000,63%,19200".
    Process {
        id: read
        command: [Config.scripts.brightnessctl, "-m", "--class=backlight"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const percent = text.trim().split(",")[3];
                root.available = percent !== undefined;
                if (percent !== undefined)
                    root.value = parseInt(percent) / 100;
                root.updated();
            }
        }
    }
}
