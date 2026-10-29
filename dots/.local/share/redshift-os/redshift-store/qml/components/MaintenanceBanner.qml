import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Rectangle {
    id: root

    // --- Contratos de Propriedades e Sinais ---
    property var theme: null
    property var storeBridge: null

    readonly property bool maintenanceActive: storeBridge ? storeBridge.maintenanceRequired : false
    readonly property bool isRepairing: storeBridge ? storeBridge.isRepairing : false
    readonly property string bannerTitle: (storeBridge && storeBridge.maintenanceTitle) ?
                                          storeBridge.maintenanceTitle : "Atenção: Componente requer manutenção"
    readonly property string bannerMessage: (storeBridge && storeBridge.maintenanceMessage) ?
                                            storeBridge.maintenanceMessage :
                                            "Um componente do Redshift OS precisa de reparo após a atualização. O frontend Caelestia está temporariamente indisponível."

    signal viewDetailsClicked()
    signal runDoctorClicked()
    signal repairClicked()

    // --- Helpers de Tema Material You M3 Expressive ---
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

    // Visibilidade e Dimensões
    visible: root.maintenanceActive
    implicitHeight: visible ? contentLayout.implicitHeight + 28 : 0
    radius: root.getToken("radiusNormal", 14)
    clip: true

    Behavior on implicitHeight {
        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
    }
    Behavior on opacity {
        NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
    }

    // Fundo com Gradiente de Alerta Sofisticado (Warning Container -> Surface Container High)
    gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop {
            position: 0.0
            color: Qt.alpha(root.getToken("warningContainer", "#594800"), 0.55)
        }
        GradientStop {
            position: 0.70
            color: Qt.alpha(root.getToken("surfaceContainerHigh", "#2b2a2a"), 0.90)
        }
        GradientStop {
            position: 1.0
            color: Qt.alpha(root.getToken("errorContainer", "#8c1d18"), 0.35)
        }
    }

    border.width: 1
    border.color: Qt.alpha(root.getToken("warning", "#fbc02d"), 0.45)

    RowLayout {
        id: contentLayout
        anchors.fill: parent
        anchors.margins: 14
        spacing: 14

        // Ícone de Status
        Rectangle {
            width: 44
            height: 44
            radius: root.getToken("radiusNormal", 14)
            color: Qt.alpha(root.getToken("warningContainer", "#594800"), 0.8)
            border.width: 1
            border.color: root.getToken("warning", "#fbc02d")
            Layout.alignment: Qt.AlignVCenter

            Text {
                anchors.centerIn: parent
                text: "warning"
                font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                font.pixelSize: 24
                color: root.getToken("warning", "#fbc02d")
            }
        }

        // Textos: Título e Mensagem
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 3

            Text {
                text: root.bannerTitle
                font.family: root.getToken("fontFamily", "Google Sans Flex")
                font.pixelSize: 14
                font.weight: Font.DemiBold
                color: root.getToken("onSurface", "#e6e1e1")
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Text {
                text: root.bannerMessage
                font.family: root.getToken("fontFamily", "Google Sans Flex")
                font.pixelSize: 13
                color: root.getToken("onSurfaceVariant", "#cbc5ca")
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }

        // Ações Acionáveis
        RowLayout {
            Layout.alignment: Qt.AlignVCenter
            spacing: 8

            // 1. Botão "Ver detalhes"
            Rectangle {
                implicitWidth: 105
                implicitHeight: 34
                radius: root.getToken("radiusFull", 9999)
                color: btnDetailsArea.containsMouse ? root.getToken("surfaceContainerHighest", "#363435") : Qt.alpha(root.getToken("surfaceContainerLowest", "#0f0e0e"), 0.5)
                border.width: 1
                border.color: root.getToken("outlineVariant", "#49454f")

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        text: "info"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 15
                        color: root.getToken("onSurfaceVariant", "#cbc5ca")
                    }

                    Text {
                        text: "Ver detalhes"
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        color: root.getToken("onSurface", "#e6e1e1")
                    }
                }

                MouseArea {
                    id: btnDetailsArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.viewDetailsClicked()
                }
            }

            // 2. Botão "Executar diagnóstico"
            Rectangle {
                implicitWidth: 145
                implicitHeight: 34
                radius: root.getToken("radiusFull", 9999)
                color: btnDiagArea.containsMouse ? root.getToken("secondaryContainer", "#4a4458") : Qt.alpha(root.getToken("surfaceContainerHighest", "#363435"), 0.7)
                border.width: 1
                border.color: root.getToken("outlineVariant", "#49454f")

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        text: "health_and_safety"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 15
                        color: root.getToken("secondary", "#ccc2dc")
                    }

                    Text {
                        text: "Executar diagnóstico"
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        color: root.getToken("onSurface", "#e6e1e1")
                    }
                }

                MouseArea {
                    id: btnDiagArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runDoctorClicked()
                }
            }

            // 3. Botão "Reparar componente"
            Rectangle {
                implicitWidth: 140
                implicitHeight: 34
                radius: root.getToken("radiusFull", 9999)
                color: root.isRepairing ? root.getToken("surfaceContainerHighest", "#363435") :
                       btnRepairArea.containsMouse ? Qt.darker(root.getToken("primary", "#d0bcff"), 1.1) : root.getToken("primary", "#d0bcff")

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 5

                    BusyIndicator {
                        running: root.isRepairing
                        visible: root.isRepairing
                        implicitWidth: 16
                        implicitHeight: 16
                    }

                    Text {
                        visible: !root.isRepairing
                        text: "build"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 15
                        color: root.getToken("onPrimary", "#381e72")
                    }

                    Text {
                        text: root.isRepairing ? "Reparando..." : "Reparar"
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: root.getToken("onPrimary", "#381e72")
                    }
                }

                MouseArea {
                    id: btnRepairArea
                    anchors.fill: parent
                    enabled: !root.isRepairing
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.repairClicked()
                }
            }
        }
    }
}
