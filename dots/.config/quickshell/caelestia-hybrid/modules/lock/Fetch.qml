import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.effects
import qs.services
import qs.utils

StyledRect {
    id: root

    required property real rootHeight
    readonly property int cBoxSize: Tokens.font.body.medium.pointSize * 2

    implicitHeight: layout.implicitHeight + layout.anchors.topMargin + layout.anchors.margins
    radius: Tokens.rounding.medium
    color: Colours.tPalette.m3surfaceContainer

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.extraLarge
        anchors.topMargin: Tokens.padding.extraLarge
        anchors.bottomMargin: Tokens.padding.extraLarge

        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacing.medium

            StyledRect {
                implicitWidth: prompt.implicitWidth + Tokens.padding.medium * 2
                implicitHeight: prompt.implicitHeight + Tokens.padding.small * 2

                color: Colours.palette.m3primary
                radius: Tokens.rounding.medium

                MonoText {
                    id: prompt

                    anchors.centerIn: parent
                    text: ">"
                    color: Colours.palette.m3onPrimary
                }
            }

            MonoText {
                Layout.fillWidth: true
                text: "caelestiafetch.sh"
                elide: Text.ElideRight
            }

            WrappedLoader {
                Layout.fillHeight: true
                Layout.preferredWidth: height
                Layout.preferredHeight: 0
                active: !iconLoader.active

                sourceComponent: SysInfo.isDefaultLogo ? caelestiaLogo : distroIcon
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacing.extraLarge

            WrappedLoader {
                id: iconLoader

                Layout.fillHeight: true
                active: root.width > Tokens.sizes.lock.largeLogoWidth

                sourceComponent: SysInfo.isDefaultLogo ? caelestiaLogo : distroIcon
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.padding.medium
                Layout.bottomMargin: iconLoader.active || colourRowLoader.active ? Tokens.padding.medium : 0
                spacing: Tokens.spacing.medium

                Repeater {
                    model: {
                        const items = [];
                        const hasBatt = UPower.displayDevice.isLaptopBattery;
                        const rHeight = root.rootHeight;

                        if (!hasBatt && rHeight > Tokens.sizes.lock.fetch4LinesHeight)
                            // TRANSLATORS: keep the label padded to 4 chars so the column stays aligned
                            items.push(Tr.tr("OS  : %1").arg(SysInfo.osPrettyName || SysInfo.osName));

                        if (rHeight > (hasBatt ? Tokens.sizes.lock.fetch4LinesHeight : Tokens.sizes.lock.fetch3LinesHeight))
                            // TRANSLATORS: keep the label padded to 4 chars so the column stays aligned
                            items.push(Tr.tr("WM  : %1").arg(SysInfo.wm));

                        if (!hasBatt || rHeight > Tokens.sizes.lock.fetch3LinesHeight)
                            // TRANSLATORS: keep the label padded to 4 chars so the column stays aligned
                            items.push(Tr.tr("USER: %1").arg(SysInfo.user));

                        // TRANSLATORS: keep the label padded to 4 chars so the column stays aligned
                        items.push(Tr.tr("UP  : %1").arg(SysInfo.uptime));

                        if (hasBatt) {
                            const charging = [UPowerDeviceState.Charging, UPowerDeviceState.FullyCharged, UPowerDeviceState.PendingCharge].includes(UPower.displayDevice.state);
                            const pct = Math.round(UPower.displayDevice.percentage * 100);
                            // TRANSLATORS: keep the label padded to 4 chars, (+) marks charging
                            items.push(charging ? Tr.tr("BATT: (+) %1%").arg(pct) : Tr.tr("BATT: %1%").arg(pct));
                        }

                        return items;
                    }

                    MonoText {
                        required property string modelData

                        Layout.fillWidth: true
                        text: modelData
                        elide: Text.ElideRight
                    }
                }
            }
        }

        WrappedLoader {
            id: colourRowLoader

            Layout.topMargin: iconLoader.active ? Tokens.spacing.small : 0
            Layout.alignment: Qt.AlignHCenter
            active: root.rootHeight > Tokens.sizes.lock.showColourBoxRowHeight

            sourceComponent: RowLayout {
                id: coloursRow

                spacing: Tokens.spacing.largeIncreased

                Repeater {
                    model: CUtils.clamp(Math.floor((layout.width + coloursRow.spacing) / (root.cBoxSize + coloursRow.spacing)), 0, 8)

                    StyledRect {
                        required property int index

                        implicitWidth: implicitHeight
                        implicitHeight: root.cBoxSize
                        color: Colours.palette[`term${index}`]
                        radius: Tokens.rounding.medium
                    }
                }
            }
        }
    }

    Component {
        id: caelestiaLogo

        Logo {
            width: height
            colored: false
            animated: true
        }
    }

    Component {
        id: distroIcon

        Item {
            anchors.centerIn: parent
            width: height
            height: width
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
                anchors.centerIn: parent
                width: parent.width
                height: parent.height
                source: "file://" + Paths.home + "/.local/share/redshift-os/icons/redshift-symbolic-compact.svg"
                fillMode: Image.PreserveAspectFit
                sourceSize.width: 256
                sourceSize.height: 256
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

    component WrappedLoader: Loader {
        asynchronous: true
        visible: active
    }

    component MonoText: StyledText {
        font: root.width > Tokens.sizes.lock.largeFontWidth ? Tokens.font.mono.medium : Tokens.font.mono.small
    }
}
