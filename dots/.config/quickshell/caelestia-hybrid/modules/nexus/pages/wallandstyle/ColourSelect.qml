pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    title: Tr.tr("Colours")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.large

        // Full Palette Variant Selector
        PaletteVariantSelector {
            Layout.fillWidth: true
        }

        // Theme Mode Options
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.extraSmall / 2

            SectionHeader {
                first: true
                text: Tr.tr("Appearance")
            }

            ToggleRow {
                first: true
                text: Tr.tr("Dark theme")
                subtext: Tr.tr("Switch between light and dark Material You tones")
                checked: !Colours.light
                onToggled: Colours.setMode(checked ? "dark" : "light")
            }

            ToggleRow {
                last: true
                text: Tr.tr("Transparency")
                subtext: Tr.tr("Base %1, layers %2").arg(Colours.transparency.base).arg(Colours.transparency.layers)
                checked: Colours.transparency.enabled
                onToggled: GlobalConfig.appearance.transparency.enabled = checked
            }
        }

        // Detailed Material You Roles
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.small

            SectionHeader {
                text: Tr.tr("System Material 3 Roles")
            }

            ConnectedRect {
                Layout.fillWidth: true
                first: true
                last: true
                implicitHeight: rolesGrid.implicitHeight + Tokens.padding.medium * 2
                color: Colours.tPalette.m3surfaceContainer

                GridLayout {
                    id: rolesGrid
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.medium
                    columns: 2
                    rowSpacing: Tokens.spacing.small
                    columnSpacing: Tokens.spacing.medium

                    Repeater {
                        model: [
                            { name: Tr.tr("Primary"), bg: Colours.palette.m3primary, fg: Colours.palette.m3onPrimary },
                            { name: Tr.tr("Primary Container"), bg: Colours.palette.m3primaryContainer, fg: Colours.palette.m3onPrimaryContainer },
                            { name: Tr.tr("Secondary"), bg: Colours.palette.m3secondary, fg: Colours.palette.m3onSecondary },
                            { name: Tr.tr("Secondary Container"), bg: Colours.palette.m3secondaryContainer, fg: Colours.palette.m3onSecondaryContainer },
                            { name: Tr.tr("Tertiary"), bg: Colours.palette.m3tertiary, fg: Colours.palette.m3onTertiary },
                            { name: Tr.tr("Tertiary Container"), bg: Colours.palette.m3tertiaryContainer, fg: Colours.palette.m3onTertiaryContainer },
                            { name: Tr.tr("Surface"), bg: Colours.palette.m3surface, fg: Colours.palette.m3onSurface },
                            { name: Tr.tr("Surface Container High"), bg: Colours.palette.m3surfaceContainerHigh, fg: Colours.palette.m3onSurface },
                            { name: Tr.tr("Outline"), bg: Colours.palette.m3surfaceContainer, fg: Colours.palette.m3outline },
                            { name: Tr.tr("Error Container"), bg: Colours.palette.m3errorContainer, fg: Colours.palette.m3onErrorContainer }
                        ]

                        delegate: RowLayout {
                            id: roleRow
                            required property var modelData

                            Layout.fillWidth: true
                            spacing: Tokens.spacing.small

                            StyledRect {
                                implicitWidth: 32
                                implicitHeight: 32
                                radius: Tokens.rounding.small
                                color: roleRow.modelData.bg
                                border.width: 1
                                border.color: Qt.alpha(Colours.palette.m3outline, 0.2)

                                Behavior on color {
                                    Anim {
                                        type: Anim.DefaultEffects
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                StyledText {
                                    text: roleRow.modelData.name
                                    color: Colours.palette.m3onSurface
                                    font: Tokens.font.label.medium
                                }

                                StyledText {
                                    text: roleRow.modelData.bg.toString().toUpperCase()
                                    color: Colours.palette.m3onSurfaceVariant
                                    font: Tokens.font.body.small
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
