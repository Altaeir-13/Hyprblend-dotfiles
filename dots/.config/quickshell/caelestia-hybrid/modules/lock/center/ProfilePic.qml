import QtQuick
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services
import qs.utils

Item {
    id: root

    required property int centerWidth
    // Reference lock screen visual size: ~160-240px in Full HD
    readonly property real visualSize: Math.round(Math.min(240, Math.max(160, centerWidth * 0.42)))

    implicitWidth: root.visualSize
    implicitHeight: root.visualSize

    Item {
        anchors.centerIn: parent
        width: root.visualSize
        height: root.visualSize
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
            id: lockEmblem
            anchors.centerIn: parent
            width: root.visualSize
            height: root.visualSize
            source: "file://" + Paths.home + "/.local/share/redshift-os/icons/redshift-symbolic-compact.svg"
            fillMode: Image.PreserveAspectFit
            sourceSize.width: 512
            sourceSize.height: 512
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
