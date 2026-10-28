import QtQuick
import Quickshell

import qs.services
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

    PopupToolTip {
        id: tooltip
        text: Translation.tr("Switch to Caelestia")
        extraVisibleCondition: root.hovered
        alternativeVisibleCondition: extraVisibleCondition
        anchorEdges: {
            if (Config.options.bar.vertical) {
                return Config.options.bar.bottom ? Edges.Left : Edges.Right;
            }
            return Config.options.bar.bottom ? Edges.Top : Edges.Bottom;
        }
    }
}
