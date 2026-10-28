import QtQuick
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services
import qs.utils

Item {
    id: root

    // Bar clickable area reference: 36-44px
    implicitWidth: Tokens.sizes.bar.innerWidth
    implicitHeight: Tokens.sizes.bar.innerWidth

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onClicked: {
            const screenState = ShellState.forActive();
            screenState.launcher = !screenState.launcher;
        }
    }

    Item {
        id: iconWrapper
        anchors.centerIn: parent
        width: 28
        height: 28
        transformOrigin: Item.Center

        RotationAnimation on rotation {
            from: 0
            to: 360
            duration: 8000
            direction: RotationAnimation.Clockwise
            loops: Animation.Infinite
            running: root.visible
        }

        Image {
            id: emblemImage
            anchors.centerIn: parent
            width: 28
            height: 28
            source: "file://" + Paths.home + "/.local/share/redshift-os/icons/redshift-symbolic-compact.svg"
            fillMode: Image.PreserveAspectFit
            sourceSize.width: 64
            sourceSize.height: 64
            mipmap: true
            smooth: true
            asynchronous: true
            transformOrigin: Item.Center

            layer.enabled: true
            layer.effect: Colouriser {
                colorizationColor: Colours.palette.m3primary
            }
        }
    }
}
