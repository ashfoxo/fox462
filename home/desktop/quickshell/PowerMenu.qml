// Power dropdown (the button right of the clock). Suspend goes on one
// click; reboot and power off turn rust and ask for a second click, and
// forget it after a few seconds or when the dropdown closes.
import QtQuick
import Quickshell

Dropdown {
    id: menu

    // The action waiting for its second click ("" for none).
    property string armed: ""

    function run(action) {
        menu.armed = "";
        menu.dismissed();
        Quickshell.execDetached(["systemctl", action]);
    }

    panelWidth: 300
    onVisibleChanged: armed = ""

    Timer {
        running: menu.armed !== ""
        interval: 4000
        onTriggered: menu.armed = ""
    }

    MenuHeader {
        icon: "\u{F0425}"
        title: "power"
    }

    PopButton {
        width: parent.width
        icon: "\u{F04B2}"
        text: "suspend"
        onClicked: menu.run("suspend")
    }

    Repeater {
        model: [
            { action: "reboot", icon: "\u{F0709}", label: "reboot" },
            { action: "poweroff", icon: "\u{F0425}", label: "power off" }
        ]

        PopButton {
            required property var modelData
            readonly property bool isArmed: menu.armed === modelData.action

            width: parent.width
            kind: isArmed ? "danger" : "plain"
            icon: modelData.icon
            text: isArmed ? `${modelData.label}? click again` : modelData.label
            onClicked: {
                if (isArmed)
                    menu.run(modelData.action);
                else
                    menu.armed = modelData.action;
            }
        }
    }
}
