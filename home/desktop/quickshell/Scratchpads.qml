// After the workspaces: every scratchpad, then +chat, then hidden windows.
// Same look as the workspaces: a scratchpad's tag is bright while its app
// is running, faint while it isn't, and filled green while it's showing
// on this monitor. Click toggles
// it, same as its key (starting the app first if needed).
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
            text: modelData.name
            color: Pads.isRunning(modelData) ? Config.colors.fg : Config.colors.faint
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

    ChatMenu {
        bar: root.bar
        anchorItem: chat
        visible: root.bar.open === "chat"
        onDismissed: root.bar.open = ""
    }
    HiddenMenu {
        bar: root.bar
        anchorItem: hidden
        visible: root.bar.open === "hidden"
        onDismissed: root.bar.open = ""
    }
}
