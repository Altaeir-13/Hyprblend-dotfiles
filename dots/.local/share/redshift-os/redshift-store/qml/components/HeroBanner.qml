import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    // --- Contratos de Propriedades e Sinais ---
    property var theme: null
    property int installedCount: 0
    property int updatesCount: 0
    property string frontendMode: "end-4"
    property bool isBusy: false

    signal exploreOfficialClicked()
    signal exploreAurClicked()
    signal checkUpdatesClicked()

    // --- Helpers de Tema e Fallbacks M3 Expressive ---
    readonly property var defaultTheme: ({
        surface: "#141313",
        surfaceContainerLowest: "#0f0e0e",
        surfaceContainerLow: "#1c1b1c",
        surfaceContainer: "#201f20",
        surfaceContainerHigh: "#2b2a2a",
        surfaceContainerHighest: "#363435",
        primary: "#d0bcff",
        onPrimary: "#381e72",
        primaryContainer: "#4f378b",
        onPrimaryContainer: "#eaddff",
        secondary: "#ccc2dc",
        onSecondary: "#332d41",
        secondaryContainer: "#4a4458",
        onSecondaryContainer: "#e8def8",
        tertiary: "#efb8c8",
        onTertiary: "#492532",
        tertiaryContainer: "#633b48",
        onTertiaryContainer: "#ffd8e4",
        onSurface: "#e6e1e1",
        onSurfaceVariant: "#cbc5ca",
        outline: "#938f99",
        outlineVariant: "#49454f",
        error: "#f2b8b5",
        onError: "#601410",
        errorContainer: "#8c1d18",
        onErrorContainer: "#f9dedc",
        success: "#b5ccba",
        onSuccess: "#213528",
        successContainer: "#374b3e",
        onSuccessContainer: "#d1e9d6",
        warning: "#fbc02d",
        onWarning: "#332b00",
        warningContainer: "#594800",
        onWarningContainer: "#ffe082",
        fontFamily: "Google Sans Flex",
        monoFontFamily: "JetBrains Mono NF",
        iconFontFamily: "Material Symbols Rounded",
        radiusSmall: 8,
        radiusNormal: 14,
        radiusLarge: 20,
        radiusFull: 9999
    })

    function getToken(prop, fallback) {
        if (root.theme) {
            let snake = prop.replace(/([A-Z])/g, "_$1").toLowerCase();
            if (root.theme.colors) {
                if (root.theme.colors[prop] !== undefined) return root.theme.colors[prop];
                if (root.theme.colors[snake] !== undefined) return root.theme.colors[snake];
            }
            if (root.theme[snake] !== undefined) return root.theme[snake];
            let m3key = "m3" + prop;
            if (root.theme[m3key] !== undefined) return root.theme[m3key];
            if (!prop.startsWith("on") && root.theme[prop] !== undefined) return root.theme[prop];
        }
        return defaultTheme[prop] !== undefined ? defaultTheme[prop] : fallback;
    }

    implicitWidth: 840
    implicitHeight: 210
    radius: root.getToken("radiusLarge", 20)
    clip: true

    // Fundo com Gradiente Linear Material You (primaryContainer -> tertiaryContainer)
    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop {
            position: 0.0
            color: root.getToken("primaryContainer", "#4f378b")
        }
        GradientStop {
            position: 0.65
            color: Qt.alpha(root.getToken("secondaryContainer", "#4a4458"), 0.95)
        }
        GradientStop {
            position: 1.0
            color: root.getToken("tertiaryContainer", "#633b48")
        }
    }

    border.width: 1
    border.color: Qt.alpha(root.getToken("primary", "#d0bcff"), 0.35)

    // Decoração de Fundo com Círculos Translúcidos Suaves
    Rectangle {
        width: 220
        height: 220
        radius: 110
        anchors.right: parent.right
        anchors.rightMargin: -40
        anchors.verticalCenter: parent.verticalCenter
        color: Qt.alpha(root.getToken("tertiary", "#efb8c8"), 0.12)
    }

    Rectangle {
        width: 130
        height: 130
        radius: 65
        anchors.right: parent.right
        anchors.rightMargin: 80
        anchors.top: parent.top
        anchors.topMargin: -30
        color: Qt.alpha(root.getToken("primary", "#d0bcff"), 0.10)
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 16

        // Conteúdo Principal à Esquerda
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 100
            Layout.minimumWidth: 220
            spacing: 10

            // Tag de Destaque
            RowLayout {
                spacing: 6

                Rectangle {
                    implicitWidth: tagRow.implicitWidth + 14
                    height: 24
                    radius: root.getToken("radiusFull", 9999)
                    color: Qt.alpha(root.getToken("surface", "#141313"), 0.45)
                    border.width: 1
                    border.color: Qt.alpha(root.getToken("primary", "#d0bcff"), 0.4)

                    RowLayout {
                        id: tagRow
                        anchors.centerIn: parent
                        spacing: 5

                        Text {
                            text: "auto_awesome"
                            font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                            font.pixelSize: 13
                            color: root.getToken("primary", "#d0bcff")
                        }

                        Text {
                            text: "LOJA NATIVA DO REDSHIFT OS"
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: root.getToken("onPrimaryContainer", "#eaddff")
                        }
                    }
                }

                // Indicador do Modo
                Rectangle {
                    implicitWidth: modeRow.implicitWidth + 14
                    height: 24
                    radius: root.getToken("radiusFull", 9999)
                    color: Qt.alpha(root.getToken("surface", "#141313"), 0.35)

                    RowLayout {
                        id: modeRow
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            text: "palette"
                            font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                            font.pixelSize: 13
                            color: root.getToken("tertiary", "#efb8c8")
                        }

                        Text {
                            text: root.frontendMode === "caelestia" ? "Caelestia UI" : "end-4 UI"
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 11
                            color: root.getToken("onSurface", "#e6e1e1")
                        }
                    }
                }
            }

            // Título Expressivo
            Text {
                text: "Redshift Store"
                font.family: root.getToken("fontFamily", "Google Sans Flex")
                font.pixelSize: 28
                font.weight: Font.Bold
                color: root.getToken("onPrimaryContainer", "#eaddff")
                Layout.fillWidth: true
            }

            // Subtítulo descritivo
            Text {
                text: "Pacotes oficiais Arch Linux (pacman) e comunidade (AUR) com tema dinâmico Matugen em tempo real."
                font.family: root.getToken("fontFamily", "Google Sans Flex")
                font.pixelSize: 13
                color: Qt.alpha(root.getToken("onPrimaryContainer", "#eaddff"), 0.85)
                Layout.fillWidth: true
                Layout.preferredWidth: 100
                elide: Text.ElideRight
                wrapMode: Text.WordWrap
                maximumLineCount: 2
            }

            Item { Layout.fillHeight: true }

            // Botões de Ação Rápida
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                // 1. Explorar Oficiais
                Rectangle {
                    implicitWidth: btn1Row.implicitWidth + 16
                    height: 36
                    radius: root.getToken("radiusFull", 9999)
                    color: btn1Mouse.containsMouse ?
                        root.getToken("primary", "#d0bcff") :
                        Qt.alpha(root.getToken("surface", "#141313"), 0.55)
                    border.width: 1
                    border.color: root.getToken("primary", "#d0bcff")

                    Behavior on color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        id: btn1Row
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: "verified"
                            font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                            font.pixelSize: 17
                            color: btn1Mouse.containsMouse ?
                                root.getToken("onPrimary", "#381e72") :
                                root.getToken("primary", "#d0bcff")
                        }

                        Text {
                            text: "Explorar Oficiais"
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: btn1Mouse.containsMouse ?
                                root.getToken("onPrimary", "#381e72") :
                                root.getToken("onSurface", "#e6e1e1")
                        }
                    }

                    MouseArea {
                        id: btn1Mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.exploreOfficialClicked()
                    }
                }

                // 2. Explorar AUR
                Rectangle {
                    implicitWidth: btn2Row.implicitWidth + 16
                    height: 36
                    radius: root.getToken("radiusFull", 9999)
                    color: btn2Mouse.containsMouse ?
                        root.getToken("tertiary", "#efb8c8") :
                        Qt.alpha(root.getToken("surface", "#141313"), 0.55)
                    border.width: 1
                    border.color: root.getToken("tertiary", "#efb8c8")

                    Behavior on color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        id: btn2Row
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: "cloud_download"
                            font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                            font.pixelSize: 17
                            color: btn2Mouse.containsMouse ?
                                root.getToken("onTertiary", "#492532") :
                                root.getToken("tertiary", "#efb8c8")
                        }

                        Text {
                            text: "Explorar AUR"
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: btn2Mouse.containsMouse ?
                                root.getToken("onTertiary", "#492532") :
                                root.getToken("onSurface", "#e6e1e1")
                        }
                    }

                    MouseArea {
                        id: btn2Mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.exploreAurClicked()
                    }
                }

                // 3. Verificar Atualizações
                Rectangle {
                    implicitWidth: btn3Row.implicitWidth + 16
                    height: 36
                    radius: root.getToken("radiusFull", 9999)
                    color: btn3Mouse.containsMouse ?
                        root.getToken("surfaceContainerHighest", "#363435") :
                        Qt.alpha(root.getToken("surface", "#141313"), 0.40)
                    border.width: 1
                    border.color: root.getToken("outlineVariant", "#49454f")

                    Behavior on color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        id: btn3Row
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: "sync"
                            font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                            font.pixelSize: 17
                            color: root.getToken("onSurface", "#e6e1e1")

                            RotationAnimation on rotation {
                                running: root.isBusy
                                loops: Animation.Infinite
                                from: 0
                                to: 360
                                duration: 1000
                            }
                        }

                        Text {
                            text: "Verificar Atualizações"
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            color: root.getToken("onSurface", "#e6e1e1")
                        }
                    }

                    MouseArea {
                        id: btn3Mouse
                        anchors.fill: parent
                        hoverEnabled: !root.isBusy
                        cursorShape: root.isBusy ? Qt.ForbiddenCursor : Qt.PointingHandCursor
                        enabled: !root.isBusy
                        onClicked: root.checkUpdatesClicked()
                    }
                }
            }
        }

        // Estatísticas Rápidas à Direita
        ColumnLayout {
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: false
            Layout.preferredWidth: 165
            Layout.minimumWidth: 155
            Layout.maximumWidth: 175
            spacing: 10

            // Card Estatística 1: Instalados
            Rectangle {
                Layout.preferredWidth: 165
                Layout.fillWidth: true
                height: 62
                radius: root.getToken("radiusNormal", 14)
                color: Qt.alpha(root.getToken("surface", "#141313"), 0.55)
                border.width: 1
                border.color: Qt.alpha(root.getToken("outlineVariant", "#49454f"), 0.6)

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    Rectangle {
                        width: 38
                        height: 38
                        radius: root.getToken("radiusSmall", 8)
                        color: root.getToken("secondaryContainer", "#4a4458")

                        Text {
                            anchors.centerIn: parent
                            text: "inventory_2"
                            font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                            font.pixelSize: 19
                            color: root.getToken("onSecondaryContainer", "#e8def8")
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: root.installedCount > 0 ? root.installedCount.toString() : "—"
                            font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                            font.pixelSize: 17
                            font.weight: Font.Bold
                            color: root.getToken("onSurface", "#e6e1e1")
                        }

                        Text {
                            text: "Instalados"
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 11
                            color: root.getToken("onSurfaceVariant", "#cbc5ca")
                        }
                    }
                }
            }

            // Card Estatística 2: Atualizações
            Rectangle {
                Layout.preferredWidth: 165
                Layout.fillWidth: true
                height: 62
                radius: root.getToken("radiusNormal", 14)
                color: root.updatesCount > 0 ?
                    Qt.alpha(root.getToken("warningContainer", "#594800"), 0.75) :
                    Qt.alpha(root.getToken("surface", "#141313"), 0.55)
                border.width: 1
                border.color: root.updatesCount > 0 ?
                    root.getToken("warning", "#fbc02d") :
                    Qt.alpha(root.getToken("outlineVariant", "#49454f"), 0.6)

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    Rectangle {
                        width: 38
                        height: 38
                        radius: root.getToken("radiusSmall", 8)
                        color: root.updatesCount > 0 ?
                            root.getToken("warning", "#fbc02d") :
                            root.getToken("surfaceContainerHighest", "#363435")

                        Text {
                            anchors.centerIn: parent
                            text: "system_update_alt"
                            font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                            font.pixelSize: 19
                            color: root.updatesCount > 0 ?
                                root.getToken("onWarning", "#332b00") :
                                root.getToken("onSurfaceVariant", "#cbc5ca")
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Text {
                            text: root.updatesCount > 0 ? root.updatesCount.toString() : "Em dia"
                            font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                            font.pixelSize: root.updatesCount > 0 ? 17 : 14
                            font.weight: Font.Bold
                            color: root.updatesCount > 0 ?
                                root.getToken("onWarningContainer", "#ffe082") :
                                root.getToken("success", "#b5ccba")
                        }

                        Text {
                            text: root.updatesCount > 0 ? "Atualizações" : "Sistema seguro"
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 11
                            color: root.getToken("onSurfaceVariant", "#cbc5ca")
                        }
                    }
                }
            }
        }
    }
}
