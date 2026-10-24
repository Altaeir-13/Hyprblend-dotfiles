import QtQuick
import Quickshell

import Caelestia.Config

import qs.components
import qs.services

Item {
    id: root

    implicitWidth:
        icon.implicitHeight + Tokens.padding.small

    implicitHeight:
        icon.implicitHeight

    StateLayer {
        anchors.fill: undefined
        anchors.centerIn: parent

        implicitWidth: implicitHeight

        implicitHeight:
            icon.implicitHeight + Tokens.padding.small

        radius:
            Tokens.rounding.full

        onClicked: {
            const configHome =
                Quickshell.env("XDG_CONFIG_HOME")
                || (Quickshell.env("HOME") + "/.config");

            Quickshell.execDetached([
                configHome + "/quickshell/ui-switch.sh",
                "end4"
            ]);
        }
    }

    MaterialIcon {
        id: icon

        anchors.centerIn: parent

        text: "swap_horiz"

        color:
            Colours.palette.m3tertiary

        fontStyle:
            Tokens.font.icon.builders.small
                .weight(Font.Bold)
                .build()
    }
}
