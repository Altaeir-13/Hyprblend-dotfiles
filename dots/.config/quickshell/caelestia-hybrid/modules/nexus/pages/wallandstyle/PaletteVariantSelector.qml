import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

ColumnLayout {
    id: root

    spacing: Tokens.spacing.medium

    readonly property var variants: [
        { id: "auto", name: Tr.tr("Auto"), icon: "auto_awesome" },
        { id: "content", name: Tr.tr("Content"), icon: "palette" },
        { id: "expressive", name: Tr.tr("Expressive"), icon: "brush" },
        { id: "fidelity", name: Tr.tr("Fidelity"), icon: "image" },
        { id: "fruitsalad", name: Tr.tr("Fruit Salad"), icon: "restaurant" },
        { id: "monochrome", name: Tr.tr("Monochrome"), icon: "contrast" },
        { id: "neutral", name: Tr.tr("Neutral"), icon: "filter_b_and_w" },
        { id: "rainbow", name: Tr.tr("Rainbow"), icon: "looks" },
        { id: "tonalspot", name: Tr.tr("Tonal Spot"), icon: "lens" },
        { id: "vibrant", name: Tr.tr("Vibrant"), icon: "flare" }
    ]

    function formatVariantName(id: string): string {
        for (let i = 0; i < root.variants.length; ++i) {
            if (root.variants[i].id === id)
                return root.variants[i].name;
        }
        return id;
    }

    // Header & Active Algorithm Indicator
    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: "palette"
            color: Colours.palette.m3primary
            fontStyle: Tokens.font.icon.medium
        }

        StyledText {
            text: Tr.tr("Colour generation style")
            color: Colours.palette.m3onSurface
            font: Tokens.font.title.small
        }

        Item {
            Layout.fillWidth: true
        }

        StyledRect {
            implicitHeight: activeLabel.implicitHeight + Tokens.padding.small * 2
            implicitWidth: activeLabel.implicitWidth + Tokens.padding.medium * 2
            color: Colours.palette.m3secondaryContainer
            radius: Tokens.rounding.full

            StyledText {
                id: activeLabel
                anchors.centerIn: parent
                text: Colours.isAuto
                    ? Tr.tr("Auto (%1)").arg(root.formatVariantName(Colours.variant))
                    : root.formatVariantName(Colours.variantPreference)
                color: Colours.palette.m3onSecondaryContainer
                font: Tokens.font.label.small
            }
        }
    }

    // Interactive Chips
    Flow {
        Layout.fillWidth: true
        Layout.preferredWidth: 0
        width: root.width
        spacing: Tokens.spacing.small

        Repeater {
            model: root.variants

            delegate: IconTextButton {
                id: chip

                required property var modelData

                readonly property bool active: Colours.variantPreference === modelData.id

                icon: active ? "check" : modelData.icon
                text: modelData.name
                isRound: true
                shapeMorph: true
                type: active ? IconTextButton.Filled : IconTextButton.Tonal
                font: Tokens.font.label.large
                horizontalPadding: Tokens.padding.medium
                verticalPadding: Tokens.padding.small

                onClicked: Colours.setVariant(modelData.id)
            }
        }
    }

    // Live Resulting Palette Preview Swatches
    ConnectedRect {
        Layout.fillWidth: true
        first: true
        last: true
        implicitHeight: swatchColumn.implicitHeight + Tokens.padding.medium * 2
        color: Colours.tPalette.m3surfaceContainerLow

        ColumnLayout {
            id: swatchColumn
            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.small

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.extraSmall

                MaterialIcon {
                    text: "tonality"
                    color: Colours.palette.m3outline
                    fontStyle: Tokens.font.icon.small
                }

                StyledText {
                    text: Tr.tr("Resulting Material You palette")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.medium
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                Repeater {
                    model: [
                        { role: Tr.tr("Primary"), color: Colours.palette.m3primary, onColor: Colours.palette.m3onPrimary },
                        { role: Tr.tr("Secondary"), color: Colours.palette.m3secondary, onColor: Colours.palette.m3onSecondary },
                        { role: Tr.tr("Tertiary"), color: Colours.palette.m3tertiary, onColor: Colours.palette.m3onTertiary },
                        { role: Tr.tr("Container"), color: Colours.palette.m3primaryContainer, onColor: Colours.palette.m3onPrimaryContainer },
                        { role: Tr.tr("Surface"), color: Colours.palette.m3surfaceContainerHigh, onColor: Colours.palette.m3onSurface }
                    ]

                    delegate: StyledRect {
                        id: swatchRect
                        required property var modelData

                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        implicitHeight: 46
                        radius: Tokens.rounding.small
                        color: modelData.color
                        border.width: 1
                        border.color: Qt.alpha(Colours.palette.m3outline, 0.2)

                        Behavior on color {
                            Anim {
                                type: Anim.DefaultEffects
                            }
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            width: parent.width - Tokens.padding.extraSmall * 2
                            spacing: 1

                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: swatchRect.modelData.role
                                color: swatchRect.modelData.onColor
                                font: Tokens.font.label.small
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: swatchRect.modelData.color.toString().toUpperCase()
                                color: swatchRect.modelData.onColor
                                font: Tokens.font.body.small
                                opacity: 0.85
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }
    }
}
