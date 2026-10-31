// A dropdown hanging from a bar item: dark panel, thin green border,
// contents stacked top to bottom. Clicking anywhere outside it (other than
// the bar) or pressing Escape closes it.
//
// It's a layer-shell window like the bar (not a popup), placed just under
// the bar at the item's left edge and kept on screen. That way it can take
// the keyboard (the Wi-Fi password box) without the compositor's popup
// rules getting in the way. The window is a fixed `maxHeight` tall and
// see-through so it never resizes while open; the panel inside grows and
// shrinks with its contents, and clicks below the panel pass through (the
// mask) and close it.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

PanelWindow {
    id: dropdown

    required property var bar
    required property Item anchorItem
    property int panelWidth: Config.dropdown.width
    property int maxHeight: 640
    // Take keyboard focus when clicked (for the Wi-Fi password box).
    property bool keyboard: false
    default property alias content: body.data
    signal dismissed

    // Line up with the item's left edge (skipping its group gap), but
    // never past the right edge of the screen.
    function place() {
        const p = anchorItem.mapToItem(null, anchorItem.gap ?? 0, 0);
        margins.left = Math.max(0, Math.min(p.x, bar.width - panelWidth - 4));
    }

    screen: bar.screen
    anchors {
        top: true
        left: true
    }
    margins.top: bar.height
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-dropdown"
    focusable: keyboard
    implicitWidth: panelWidth
    implicitHeight: maxHeight
    color: "transparent"
    mask: Region {
        item: panel
    }

    onVisibleChanged: {
        if (visible)
            place();
    }
    Component.onCompleted: place()

    // The bar is part of the grab so clicking its item again toggles the
    // dropdown shut instead of closing and reopening it.
    HyprlandFocusGrab {
        windows: [dropdown, dropdown.bar]
        active: dropdown.visible
        onCleared: dropdown.dismissed()
    }

    Shortcut {
        sequence: "Escape"
        onActivated: dropdown.dismissed()
    }

    Rectangle {
        id: panel
        width: parent.width
        height: Math.min(body.implicitHeight + 50, dropdown.maxHeight)
        clip: true
        color: Config.colors.bg
        border.color: Config.colors.forest
        border.width: 1

        Column {
            id: body
            x: 22
            y: 25
            width: parent.width - 44
            spacing: 16
        }
    }
}
