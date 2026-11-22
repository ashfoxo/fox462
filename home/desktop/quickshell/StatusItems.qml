// Status on the right, in groups:
//   load (only when high) | vpn netbird backup update | wifi bt volume profile battery | dnd
// While things are fine an item is just its icon; text shows up only when
// it needs you. vpn, netbird, backup and update go away entirely while fine,
// and come back while the mouse is over the status. Amber = heads-up, rust =
// something's wrong, teal = notable.
// Click vpn, netbird, backup or update for its dropdown. Wifi opens nmtui in
// the sys-net VM, bluetooth opens bluetui, volume opens pavucontrol.
// Volume also scrolls; the power profile cycles on click; the bell turns
// do not disturb on and off. Recording is in the island (Island.qml).
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

    HoverHandler {
        id: hover
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
    // vpn, netbird and backup hide while healthy; hovering the status shows
    // them (and an open dropdown keeps its item).
    Item {
        visible: root.loadShown && (vpnItem.visible || netbirdItem.visible || backupItem.visible || updateItem.visible)
        width: root.groupGap
        height: 1
    }
    BarButton {
        id: vpnItem
        visible: Mullvad.state !== "connected" || hover.hovered || open
        icon: "\u{F0483}"
        text: ({ disconnected: "vpn off", connecting: "connecting", disconnecting: "disconnecting", error: "vpn error" })[Mullvad.state] ?? ""
        color: ({ connected: root.c.forest_text, disconnected: root.c.rust_text, error: root.c.rust_text,
                  connecting: root.c.amber, disconnecting: root.c.amber })[Mullvad.state] ?? root.c.dim
        open: root.bar.open === "vpn"
        onClicked: root.bar.toggle("vpn")
    }
    BarButton {
        id: netbirdItem
        visible: !NetBird.up || hover.hovered || open
        icon: "\u{F06F3}"
        text: NetBird.needsLogin ? "login" : NetBird.down ? "down" : ""
        color: NetBird.down ? root.c.amber : NetBird.off ? root.c.faint : root.c.dim
        open: root.bar.open === "netbird"
        onClicked: root.bar.toggle("netbird")
    }
    UnitStatus {
        id: backupStatus
        unit: "restic-backups-s3"
        args: ["/var/lib/restic-status/last-success"]   // stamped by modules/services/restic.nix
    }
    UnitStatus {
        id: updateStatus
        unit: "nixos-update"
        args: ["/var/lib/nixos-update/last-success", "/var/lib/nixos-update/result"]
    }

    BarButton {
        id: backupItem
        visible: backupStatus.state !== "ok" || hover.hovered || open
        icon: "\u{F006F}"
        text: ({ failed: "failed", overdue: "overdue", none: "none yet" })[backupStatus.state] ?? ""
        color: ({ failed: root.c.rust_text, overdue: root.c.amber, none: root.c.amber,
                  running: root.c.teal_text })[backupStatus.state] ?? root.c.dim
        open: root.bar.open === "backup"
        onClicked: root.bar.toggle("backup")
    }
    BarButton {
        id: updateItem
        visible: updateStatus.state !== "absent" && (updateStatus.state !== "uptodate" || hover.hovered || open)
        icon: updateStatus.state === "reboot" ? "\u{F0709}" : "\u{F06B0}"
        text: ({ failed: "update failed", overdue: "update overdue" })[updateStatus.state] ?? ""
        color: ({ failed: root.c.rust_text, overdue: root.c.amber, skipped: root.c.amber, none: root.c.amber,
                  running: root.c.teal_text, ok: root.c.teal_text, reboot: root.c.teal_text })[updateStatus.state] ?? root.c.dim
        open: root.bar.open === "update"
        onClicked: root.bar.toggle("update")
    }

    // ---- wi-fi ----------------------------------------------------------------
    // The card lives in the sys-net VM (modules/vms.nix), so the host only
    // sees a route out through it: online, but no network name or signal.
    // Those show only after `sudo wifi-to-host`.
    BarButton {
        id: wifiItem
        readonly property var wired: Networking.devices.values.find(d => d.type === DeviceType.Wired && d.connected) ?? null
        readonly property var wifi: Networking.devices.values.find(d => d.type === DeviceType.Wifi) ?? null
        readonly property var network: wifi ? wifi.networks.values.find(n => n.connected) ?? null : null
        readonly property bool online: wired !== null || network !== null || Networking.connectivity === NetworkConnectivity.Full

        gap: root.groupGap
        icon: wired ? "\u{F0200}"
            : network ? (network.signalStrength > 0.75 ? "\u{F0928}"
                : network.signalStrength > 0.5 ? "\u{F0925}"
                : network.signalStrength > 0.25 ? "\u{F0922}"
                : "\u{F091F}")
            : online ? "\u{F05A9}"
            : "\u{F092D}"
        text: online ? "" : "offline"
        color: online ? root.c.dim : root.c.amber
        // 4 = sys-net's vsock cid in modules/vms.nix.
        onClicked: Quickshell.execDetached(["vm-open", "sys-net", "4", "wifi"])
    }

    // ---- bluetooth: off / on / something connected ----------------------------
    BarButton {
        id: btItem
        readonly property var adapter: Bluetooth.defaultAdapter
        readonly property bool on: adapter !== null && adapter.enabled
        readonly property bool connected: on && adapter.devices.values.some(d => d.connected)

        icon: !on ? "\u{F00B2}" : connected ? "\u{F00B1}" : "\u{F00AF}"
        color: !on ? root.c.faint : connected ? root.c.forest_text : root.c.dim
        onClicked: Quickshell.execDetached(["ghostty", "-e", "bluetui"])
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
        onClicked: Quickshell.execDetached(["pavucontrol"])
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
    // Each opens while the bar's `open` is its name (Dropdown.qml).
    MullvadMenu { bar: root.bar; anchorItem: vpnItem; name: "vpn" }
    NetBirdMenu { bar: root.bar; anchorItem: netbirdItem; name: "netbird" }
    UnitMenu {
        bar: root.bar
        anchorItem: backupItem
        name: "backup"
        status: backupStatus
        menuIcon: "\u{F006F}"
        menuTitle: "backup"
        actionText: "back up now"
        busyText: "backing up…"
    }
    UnitMenu {
        bar: root.bar
        anchorItem: updateItem
        name: "update"
        status: updateStatus
        menuIcon: "\u{F06B0}"
        menuTitle: "update"
        okText: "updates available"
        actionText: "check now"
        busyText: "checking…"
        commands: Config.updateCommands
    }
}
