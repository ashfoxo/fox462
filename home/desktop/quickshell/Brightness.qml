pragma Singleton

// Screen brightness through brightnessctl (the same tool as the brightness
// keys). Read when the volume dropdown opens; set from its slider.
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property bool available: false
    property real value: 0  // 0–1

    function refresh() {
        read.running = true;
    }
    // Never all the way to 0: a black screen is hard to undo with the mouse.
    function set(v) {
        value = Math.max(0.01, Math.min(1, v));
        Quickshell.execDetached([Config.scripts.brightnessctl, "--quiet", "set", `${Math.round(value * 100)}%`]);
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
            }
        }
    }
}
