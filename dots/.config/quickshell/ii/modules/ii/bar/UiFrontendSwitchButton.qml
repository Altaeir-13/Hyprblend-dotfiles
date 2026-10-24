import QtQuick
import Quickshell

import qs.modules.common
import qs.modules.common.widgets

RippleButton {
    id: root

    implicitWidth: 36
    implicitHeight: 36

    buttonRadius: Appearance.rounding.full

    colBackground: "transparent"
    colBackgroundHover: Appearance.colors.colLayer1Hover
    colRipple: Appearance.colors.colLayer1Active

    onClicked: {
        const configHome =
            Quickshell.env("XDG_CONFIG_HOME")
            || (Quickshell.env("HOME") + "/.config");

        Quickshell.execDetached([
            configHome + "/quickshell/ui-switch.sh",
            "caelestia"
        ]);
    }

    contentItem: MaterialSymbol {
        text: "swap_horiz"

        iconSize:
            Appearance.font.pixelSize.larger

        color:
            Appearance.colors.colOnLayer0

        horizontalAlignment:
            Text.AlignHCenter

        verticalAlignment:
            Text.AlignVCenter
    }
}
