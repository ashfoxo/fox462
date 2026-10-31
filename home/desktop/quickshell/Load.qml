pragma Singleton

// CPU, RAM and temperature, sampled every 2s by the qs-load script.
// Each has a state: "ok", "warn" or "crit" (limits in Config.load).
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property real cpu: 0   // %
    property real ram: 0   // %
    property real temp: 0  // °C

    property string cpuState: "ok"
    readonly property string ramState: level(ram, Config.load.ram)
    readonly property string tempState: level(temp, Config.load.temp)

    // Previous CPU counters, and when CPU first went over each limit.
    property var lastCpu: null
    property real warnSince: 0
    property real critSince: 0

    function level(value, limits) {
        return value >= limits.crit ? "crit" : value >= limits.warn ? "warn" : "ok";
    }

    function parse(out) {
        for (const line of out.trim().split("\n")) {
            const [name, ...rest] = line.split(" ");
            const v = rest.map(Number);
            if (name === "cpu") {
                const [total, idle] = v;
                if (lastCpu && total > lastCpu.total)
                    cpu = 100 * (1 - (idle - lastCpu.idle) / (total - lastCpu.total));
                lastCpu = { total, idle };
            } else if (name === "mem" && v[0] > 0) {
                ram = 100 * (1 - v[1] / v[0]);
            } else if (name === "temp") {
                temp = v[0] / 1000;
            }
        }

        // CPU only counts once it has stayed over a limit for a while, so a
        // short spike (opening an app) doesn't flash on the bar.
        const now = Date.now();
        const limits = Config.load.cpu;
        warnSince = cpu >= limits.warn ? (warnSince || now) : 0;
        critSince = cpu >= limits.crit ? (critSince || now) : 0;
        const held = since => since && now - since >= limits.seconds * 1000;
        cpuState = held(critSince) ? "crit" : held(warnSince) ? "warn" : "ok";
    }

    Process {
        id: sample
        command: [Config.scripts.load]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: sample.running = true
    }
}
