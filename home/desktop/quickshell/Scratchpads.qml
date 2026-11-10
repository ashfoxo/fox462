// After the workspaces: the scratchpads that are running, then +chat, then
// hidden windows. A scratchpad's tag shows only while its app runs (its key
// still starts it), filled green while it's showing on this monitor.
// Click toggles it, same as its key.
// Chat apps don't get tags: they're all behind +chat, with the number of
// messages waiting (see ChatMenu). "hidden N" shows while windows are
// hidden with Super + X; click it to bring one back (see HiddenMenu).
import QtQuick
import Quickshell

Row {
    id: root

    required property var bar
    readonly property string showing: Pads.showingOn(bar.monitor)

    height: Config.bar.height

    Repeater {
        model: Pads.all.filter(p => !p.chat)

        BarButton {
            required property var modelData
            visible: open || Pads.isRunning(modelData)
            text: modelData.name
            open: root.showing === modelData.name
            onClicked: Pads.toggle(modelData)
        }
    }

    BarButton {
        id: chat
        readonly property int count: Notifs.chats.length

        icon: "+chat"
        iconColor: Config.colors.dim
        text: count > 0 ? String(count) : ""
        color: Config.colors.teal_text
        bold: true
        open: root.bar.open === "chat" || Pads.chats.some(p => p.name === root.showing)
        onClicked: root.bar.toggle("chat")
    }

    BarButton {
        id: hidden
        visible: Pads.hidden.length > 0
        icon: "hidden"
        iconColor: Config.colors.dim
        text: String(Pads.hidden.length)
        color: Config.colors.teal_text
        bold: true
        open: root.bar.open === "hidden"
        onClicked: root.bar.toggle("hidden")
    }

    ChatMenu { bar: root.bar; anchorItem: chat; name: "chat" }
    HiddenMenu { bar: root.bar; anchorItem: hidden; name: "hidden" }
}
