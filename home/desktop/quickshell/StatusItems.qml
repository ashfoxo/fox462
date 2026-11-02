// Status on the right, in groups:
//   rec | load (only when high) | vpn netbird backup | wifi bt volume profile battery | dnd
// While things are fine an item is just its icon; text shows up only when
// it needs you. Amber = heads-up, rust = something's wrong.
// Click vpn, netbird, backup, wifi, bluetooth or volume for its dropdown.
// Volume also scrolls; the power profile cycles on click; the bell turns
// do not disturb on and off.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

Row {
    id: root

    required property var bar
    readonly property var c: Config.colors
    readonly property int groupGap: 18

    function stateColor(state) {
        return state === "crit" ? c.rust_text : state === "warn" ? c.amber : c.dim;
    }

    readonly property bool loadShown: Load.cpuState !== "ok" || Load.ramState !== "ok" || Load.tempState !== "ok"

    // ---- voice note recording (voicenotes.nix): only while recording --------
    BarButton {
        id: rec
        property bool recording: false

        visible: recording
        text: "● rec"
        bold: true
        fill: Config.colors.rust
        onClicked: Quickshell.execDetached(["voice-note"])

        Process {
            id: recCheck
            command: ["voice-note-status"]
            stdout: StdioCollector {
                onStreamFinished: rec.recording = text.includes('"recording"')
            }
        }
        Timer {
            interval: 1000
            running: true
            repeat: true
            onTriggered: recCheck.running = true
        }
    }
    Item {
        visible: rec.recording
        width: root.groupGap
        height: 1
    }

    // ---- load: only when high ----------------------------------------------
    BarButton {
        visible: Load.cpuState !== "ok"
        interactive: false
        icon: "\u{F0EE0}"
        text: `cpu ${Math.round(Load.cpu)}%`
        color: root.stateColor(Load.cpuState)
    }
    BarButton {
        visible: Load.ramState !== "ok"
        interactive: false
        icon: "\u{F035B}"
        text: `ram ${Math.round(Load.ram)}%`
        color: root.stateColor(Load.ramState)
    }
    BarButton {
        visible: Load.tempState !== "ok"
        interactive: false
        icon: "\u{F050F}"
        text: `${Math.round(Load.temp)}°`
        color: root.stateColor(Load.tempState)
    }

    // ---- vpn, netbird, backup -----------------------------------------------
    BarButton {
        id: vpnItem
        gap: root.loadShown ? root.groupGap : 0
        icon: "\u{F0483}"
        text: ({ disconnected: "vpn off", connecting: "connecting", disconnecting: "disconnecting", error: "vpn error" })[Mullvad.state] ?? ""
        color: Mullvad.state === "connected" ? root.c.forest_text
            : (Mullvad.state === "disconnected" || Mullvad.state === "error") ? root.c.rust_text
            : (Mullvad.state === "connecting" || Mullvad.state === "disconnecting") ? root.c.amber
            : root.c.dim
        open: root.bar.open === "vpn"
        onClicked: root.bar.toggle("vpn")
    }
    BarButton {
        id: netbirdItem
        icon: "\u{F06F3}"
        text: NetBird.needsLogin ? "login" : NetBird.down ? "down" : ""
        color: NetBird.down ? root.c.amber : NetBird.off ? root.c.faint : root.c.dim
        open: root.bar.open === "netbird"
        onClicked: root.bar.toggle("netbird")
    }
    BarButton {
        id: backupItem
        icon: "\u{F006F}"
        text: ({ failed: "failed", overdue: "overdue", none: "none yet" })[Backup.state] ?? ""
        color: Backup.state === "failed" ? root.c.rust_text
            : (Backup.state === "overdue" || Backup.state === "none") ? root.c.amber
            : Backup.state === "running" ? root.c.teal_text
            : root.c.dim
        open: root.bar.open === "backup"
        onClicked: root.bar.toggle("backup")
    }
    BarButton {
        id: updateItem
        visible: Update.state !== "absent"
        icon: "\u{F06B0}"
        text: ({ failed: "update failed", overdue: "update overdue", skipped: "update skipped", ok: "update ready" })[Update.state] ?? ""
        color: Update.state === "failed" ? root.c.rust_text
            : (Update.state === "overdue" || Update.state === "skipped" || Update.state === "none") ? root.c.amber
            : Update.state === "running" ? root.c.teal_text
            : Update.state === "ok" ? root.c.forest_text
            : root.c.dim
        open: root.bar.open === "update"
        onClicked: root.bar.toggle("update")
    }

    // ---- wi-fi ----------------------------------------------------------------
    BarButton {
        id: wifiItem
        readonly property var wired: Networking.devices.values.find(d => d.type === DeviceType.Wired && d.connected) ?? null
        readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
        readonly property var network: wifi ? wifi.networks.values.find(n => n.connected) ?? null : null
        readonly property bool online: wired !== null || network !== null

        gap: root.groupGap
        icon: wired ? "\u{F0200}"
            : !network ? "\u{F092D}"
            : network.signalStrength > 0.75 ? "\u{F0928}"
            : network.signalStrength > 0.5 ? "\u{F0925}"
            : network.signalStrength > 0.25 ? "\u{F0922}"
            : "\u{F091F}"
        text: online ? "" : "offline"
        color: online ? root.c.dim : root.c.amber
        open: root.bar.open === "wifi"
        onClicked: root.bar.toggle("wifi")
    }

    // ---- bluetooth: off / on / something connected ----------------------------
    BarButton {
        id: btItem
        readonly property var adapter: Bluetooth.defaultAdapter
        readonly property bool on: adapter !== null && adapter.enabled
        readonly property bool connected: on && adapter.devices.values.some(d => d.connected)

        icon: !on ? "\u{F00B2}" : connected ? "\u{F00B1}" : "\u{F00AF}"
        color: !on ? root.c.faint : connected ? root.c.forest_text : root.c.dim
        open: root.bar.open === "bt"
        onClicked: root.bar.toggle("bt")
    }

    // ---- volume: scroll to change ---------------------------------------------
    BarButton {
        id: volItem
        readonly property var sink: Pipewire.defaultAudioSink
        readonly property bool ready: sink !== null && sink.audio !== null
        readonly property bool muted: ready && sink.audio.muted
        readonly property real volume: ready ? sink.audio.volume : 0

        visible: ready
        icon: muted ? "\u{F0581}" : volume > 0.66 ? "\u{F057E}" : volume > 0.33 ? "\u{F0580}" : "\u{F057F}"
        text: muted ? "muted" : `${Math.round(volume * 100)}%`
        color: muted ? root.c.amber : root.c.fg
        iconColor: muted ? root.c.amber : root.c.dim
        open: root.bar.open === "vol"
        onClicked: root.bar.toggle("vol")
        onWheel: wheel => {
            const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
            sink.audio.volume = Math.max(0, Math.min(1, volume + step));
        }

        PwObjectTracker {
            objects: [Pipewire.defaultAudioSink]
        }
    }

    // ---- power profile: click to cycle saver > balanced > performance ---------
    BarButton {
        readonly property var profile: PowerProfiles.profile

        icon: profile === PowerProfile.PowerSaver ? "\u{F0F86}"
            : profile === PowerProfile.Performance ? "\u{F04C5}"
            : "\u{F0F85}"
        color: profile === PowerProfile.Performance ? root.c.teal_text : root.c.dim
        onClicked: {
            const order = [PowerProfile.PowerSaver, PowerProfile.Balanced];
            if (PowerProfiles.hasPerformanceProfile)
                order.push(PowerProfile.Performance);
            PowerProfiles.profile = order[(order.indexOf(profile) + 1) % order.length];
        }
    }

    // ---- battery: amber under 25%, rust under 10% (unless charging) -----------
    BarButton {
        readonly property var device: UPower.displayDevice
        readonly property int percent: Math.round(device.percentage * 100)
        readonly property bool charging: device.state === UPowerDeviceState.Charging
            || device.state === UPowerDeviceState.PendingCharge
            || device.state === UPowerDeviceState.FullyCharged
        readonly property string state: charging ? "ok" : percent < 10 ? "crit" : percent < 25 ? "warn" : "ok"

        visible: device.isLaptopBattery
        interactive: false
        icon: charging ? "\u{F0084}"
            : percent >= 90 ? "\u{F0079}"
            : percent >= 70 ? "\u{F0080}"
            : percent >= 50 ? "\u{F007E}"
            : percent >= 30 ? "\u{F007C}"
            : "\u{F007A}"
        text: `${percent}%`
        color: state === "ok" ? root.c.fg : root.stateColor(state)
        iconColor: state === "ok" ? root.c.dim : root.stateColor(state)
    }

    // ---- do not disturb: no popups (critical ones still show) ---------------
    BarButton {
        gap: root.groupGap
        icon: Notifs.dnd ? "\u{F009B}" : "\u{F009A}"
        text: Notifs.dnd ? "dnd" : ""
        color: Notifs.dnd ? root.c.teal_text : root.c.dim
        onClicked: Notifs.dnd = !Notifs.dnd
    }

    // ---- dropdowns ------------------------------------------------------------
    MullvadMenu {
        bar: root.bar
        anchorItem: vpnItem
        visible: root.bar.open === "vpn"
        onDismissed: root.bar.open = ""
    }
    NetBirdMenu {
        bar: root.bar
        anchorItem: netbirdItem
        visible: root.bar.open === "netbird"
        onDismissed: root.bar.open = ""
    }
    BackupMenu {
        bar: root.bar
        anchorItem: backupItem
        visible: root.bar.open === "backup"
        onDismissed: root.bar.open = ""
    }
    UpdateMenu {
        bar: root.bar
        anchorItem: updateItem
        visible: root.bar.open === "update"
        onDismissed: root.bar.open = ""
    }
    WifiMenu {
        bar: root.bar
        anchorItem: wifiItem
        visible: root.bar.open === "wifi"
        onDismissed: root.bar.open = ""
    }
    BluetoothMenu {
        bar: root.bar
        anchorItem: btItem
        visible: root.bar.open === "bt"
        onDismissed: root.bar.open = ""
    }
    VolumeMenu {
        bar: root.bar
        anchorItem: volItem
        visible: root.bar.open === "vol"
        onDismissed: root.bar.open = ""
    }
}
