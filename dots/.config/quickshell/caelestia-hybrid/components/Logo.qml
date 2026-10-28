import QtQuick
import Quickshell
import qs.components.effects
import qs.services
import qs.utils

Item {
    id: root

    readonly property real designWidth: 128
    readonly property real designHeight: 128

    property color topColour: Colours.palette.m3primary
    property color bottomColour: Colours.palette.m3onSurface
    property bool colored: false
    property bool animated: false

    implicitWidth: designWidth
    implicitHeight: designHeight

    Loader {
        anchors.fill: parent
        sourceComponent: root.colored ? coloredLogoComponent : monoLogoComponent
    }

    Component {
        id: coloredLogoComponent

        Item {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height)
            height: width
            transformOrigin: Item.Center

            Image {
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                source: "file://" + Paths.home + "/.local/share/redshift-os/icons/redshift-compact-256.png"
                fillMode: Image.PreserveAspectFit
                sourceSize.width: Math.max(32, Math.min(512, Math.round(width * 2)))
                sourceSize.height: sourceSize.width
                mipmap: true
                smooth: true
                asynchronous: true
                transformOrigin: Item.Center

                RotationAnimation on rotation {
                    from: 0
                    to: 360
                    duration: 8000
                    direction: RotationAnimation.Clockwise
                    loops: Animation.Infinite
                    running: root.animated && root.visible
                }
            }
        }
    }

    Component {
        id: monoLogoComponent

        Item {
            anchors.centerIn: parent
            width: Math.min(parent.width, parent.height)
            height: width
            transformOrigin: Item.Center

            RotationAnimation on rotation {
                from: 0
                to: 360
                duration: 8000
                direction: RotationAnimation.Clockwise
                loops: Animation.Infinite
                running: root.animated && root.visible
            }

            Image {
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                source: "file://" + Paths.home + "/.local/share/redshift-os/icons/redshift-symbolic-compact.svg"
                fillMode: Image.PreserveAspectFit
                sourceSize.width: Math.max(32, Math.min(512, Math.round(width * 2)))
                sourceSize.height: sourceSize.width
                mipmap: true
                smooth: true
                asynchronous: true
                transformOrigin: Item.Center

                layer.enabled: true
                layer.effect: Colouriser {
                    colorizationColor: root.topColour
                }
            }
        }
    }
}
