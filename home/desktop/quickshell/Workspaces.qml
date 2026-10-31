// The prompt and every workspace, always in the same order:
//   arlo@ws  ~ web dev writing comms creative radio entertainment
// The one you're on (on this monitor) is filled green. Ones with windows
// are bright, empty ones faint, and one asking for attention bold rust.
// Click one to go there. Workspaces without a name (9, 10) only show
// while they have windows.
import QtQuick
import Quickshell.Hyprland

Row {
    id: root

    required property var monitor

    readonly property int activeId: monitor?.activeWorkspace?.id ?? -1
    // Named ones always, plus any other normal workspace that exists.
    readonly property var ids: {
        const named = Object.keys(Config.workspaceNames).map(Number);
        const extra = Hyprland.workspaces.values.map(w => w.id).filter(id => id > 0 && !named.includes(id));
        return named.concat(extra).sort((a, b) => a - b);
    }

    function workspace(id) {
        return Hyprland.workspaces.values.find(w => w.id === id) ?? null;
    }

    height: Config.bar.height
    spacing: 18

    BarText {
        anchors.verticalCenter: parent.verticalCenter
        text: Config.prompt
        color: Config.colors.forest_text
        font.bold: true
    }

    Row {
        Repeater {
            model: root.ids

            BarButton {
                required property int modelData
                readonly property var ws: root.workspace(modelData)
                readonly property bool used: ws !== null && ws.toplevels.values.length > 0

                text: Config.workspaceNames[modelData] ?? String(modelData)
                open: modelData === root.activeId
                color: ws?.urgent ? Config.colors.rust_text : used ? Config.colors.fg : Config.colors.faint
                bold: ws?.urgent ?? false
                onClicked: Hyprland.dispatch(Hyprland.usingLua
                    ? `hl.dsp.focus({ workspace = ${modelData} })`
                    : `workspace ${modelData}`)
            }
        }
    }
}
