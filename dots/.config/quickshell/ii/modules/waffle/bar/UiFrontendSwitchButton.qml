import QtQuick
import Quickshell

BarIconButton {
    id: root

    padding: 4

    iconName: "arrow-sync"
    iconSize: 18
    iconMonochrome: true

    tooltipText: "Switch to Caelestia"

    onClicked: {
        const configHome =
            Quickshell.env("XDG_CONFIG_HOME")
            || (Quickshell.env("HOME") + "/.config");

        Quickshell.execDetached([
            configHome + "/quickshell/ui-switch.sh",
            "caelestia"
        ]);
    }
}
