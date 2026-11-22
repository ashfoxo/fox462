pragma Singleton

// What pops out under the island's clock for a moment (Popups.qml shows it):
// the volume and brightness keys, and quick events (a Bluetooth device
// connects or leaves, the charger goes in or out, the VPN connects or drops,
// "copied"). Notifications pop out there too, but they're Notifs.qml's.
// From outside the bar (the brightness keys, the command picker):
//   qs-island brightness    qs-island flash <text>
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

Singleton {
    id: root

    property bool shown: false
    property string icon: ""
    property string text: ""
    property real level: -1  // 0–1 draws a level bar, -1 none

    // Everything "changes" once while the bar starts up; stay quiet for that.
    property bool ready: false

    function show(icon, text, level) {
        if (!ready)
            return;
        root.icon = icon;
        root.text = text;
        root.level = level;
        shown = true;
        hide.restart();
    }

    Timer {
        interval: 3000
        running: true
        onTriggered: root.ready = true
    }
    Timer {
        id: hide
        interval: 1500
        onTriggered: root.shown = false
    }

    // ---- volume: whatever changed it (keys, scroll on the bar, an app) ----
    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker {
        objects: [root.sink]
    }
    function showVolume() {
        const a = sink.audio;
        if (a.muted)
            show("\u{F0581}", "muted", -1);
        else
            show("\u{F057E}", `${Math.round(a.volume * 100)}%`, Math.min(1, a.volume));
    }
    Connections {
        target: root.sink?.audio ?? null
        function onVolumeChanged() { root.showVolume(); }
        function onMutedChanged() { root.showVolume(); }
    }

    // ---- brightness: only the keys change it, and they call brightness() ----
    property bool brightnessAsked: false
    Connections {
        target: Brightness
        function onUpdated() {
            if (!root.brightnessAsked)
                return;
            root.brightnessAsked = false;
            root.show("\u{F00DF}", `${Math.round(Brightness.value * 100)}%`, Brightness.value);
        }
    }

    // ---- bluetooth: a device connects or leaves ----
    readonly property var btConnected: (Bluetooth.defaultAdapter?.devices.values ?? []).filter(d => d.connected).map(d => d.name.toLowerCase())
    property var btBefore: []
    onBtConnectedChanged: {
        const added = btConnected.filter(n => !btBefore.includes(n));
        const gone = btBefore.filter(n => !btConnected.includes(n));
        if (added.length)
            show("\u{F00B1}", `${added[0]} connected`, -1);
        else if (gone.length)
            show("\u{F00AF}", `${gone[0]} disconnected`, -1);
        btBefore = btConnected;
    }

    // ---- charger in or out ----
    readonly property var battery: UPower.displayDevice
    readonly property bool charging: battery.state === UPowerDeviceState.Charging
        || battery.state === UPowerDeviceState.PendingCharge
        || battery.state === UPowerDeviceState.FullyCharged
    onChargingChanged: {
        if (battery.isLaptopBattery)
            show(charging ? "\u{F0084}" : "\u{F0079}", charging ? "charging" : "on battery", -1);
    }

    // ---- vpn connects or drops (not the in-between states) ----
    property string vpnBefore: "unknown"
    readonly property string vpn: Mullvad.state
    onVpnChanged: {
        if (vpnBefore !== "unknown" && vpn === "connected")
            show("\u{F0483}", "vpn on", -1);
        else if (vpnBefore !== "unknown" && (vpn === "disconnected" || vpn === "error"))
            show("\u{F0483}", "vpn off", -1);
        vpnBefore = vpn;
    }

    IpcHandler {
        target: "island"

        function brightness(): void {
            root.brightnessAsked = true;
            Brightness.refresh();
        }
        function flash(text: string): void {
            root.show("\u{F018F}", text, -1);
        }
    }
}
