import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Item {
    id: root

    // --- Contratos de Propriedades e Sinais ---
    property bool isOpen: false
    property var theme: null
    property string title: "Diagnóstico de Manutenção do Redshift OS"
    property string causeText: ""
    property bool isRepairing: false

    signal closed()
    signal runDoctorRequested()
    signal repairRequested()

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

    anchors.fill: parent
    visible: opacity > 0
    opacity: root.isOpen ? 1.0 : 0.0
    z: 150

    Behavior on opacity {
        NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
    }

    // 1. Fundo Escurecido (Scrim / Backdrop)
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: root.isOpen ? 0.65 : 0.0

        Behavior on opacity {
            NumberAnimation { duration: 200 }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                root.isOpen = false;
                root.closed();
            }
        }
    }

    // 2. Janela / Card Modal Centralizado
    Rectangle {
        id: modalContent
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 700)
        height: Math.min(parent.height - 64, 520)
        radius: root.getToken("radiusLarge", 20)
        color: root.getToken("surfaceContainerHigh", "#2b2a2a")
        border.width: 1
        border.color: root.getToken("outlineVariant", "#49454f")
        clip: true

        scale: root.isOpen ? 1.0 : 0.95
        Behavior on scale {
            NumberAnimation { duration: 220; easing.type: Easing.OutBack }
        }

        MouseArea {
            anchors.fill: parent
            // Interceptar cliques para não fechar o modal
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 16

            // Cabeçalho do Modal
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Rectangle {
                    width: 42
                    height: 42
                    radius: root.getToken("radiusNormal", 14)
                    color: Qt.alpha(root.getToken("warningContainer", "#594800"), 0.8)
                    border.width: 1
                    border.color: root.getToken("warning", "#fbc02d")

                    Text {
                        anchors.centerIn: parent
                        text: "build"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 22
                        color: root.getToken("warning", "#fbc02d")
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: root.title || "Diagnóstico de Manutenção do Redshift OS"
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                        color: root.getToken("onSurface", "#e6e1e1")
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: "Análise de integridade de plugins e componentes essenciais"
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 12
                        color: root.getToken("onSurfaceVariant", "#cbc5ca")
                    }
                }

                // Botão Fechar
                Rectangle {
                    width: 34
                    height: 34
                    radius: root.getToken("radiusFull", 9999)
                    color: closeArea.containsMouse ? root.getToken("surfaceContainerHighest", "#363435") : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "close"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 20
                        color: root.getToken("onSurfaceVariant", "#cbc5ca")
                    }

                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.isOpen = false;
                            root.closed();
                        }
                    }
                }
            }

            // Separador
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: root.getToken("outlineVariant", "#49454f")
                opacity: 0.5
            }

            // Descrição e Alerta
            Text {
                text: "O sistema detectou uma pendência ou anomalia operacional no frontend Caelestia. Abaixo constam os detalhes técnicos apurados pelo diagnóstico:"
                font.family: root.getToken("fontFamily", "Google Sans Flex")
                font.pixelSize: 13
                color: root.getToken("onSurface", "#e6e1e1")
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            // Caixa Monospace com Causa Real Detectada
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: root.getToken("radiusNormal", 14)
                color: root.getToken("surfaceContainerLowest", "#0f0e0e")
                border.width: 1
                border.color: root.getToken("outlineVariant", "#49454f")
                clip: true

                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 14
                    clip: true

                    TextArea {
                        id: causeArea
                        text: root.causeText || "Nenhum detalhe adicional informado."
                        font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                        font.pixelSize: 12
                        color: root.getToken("onSurfaceVariant", "#cbc5ca")
                        readOnly: true
                        selectByMouse: true
                        wrapMode: Text.WrapAnywhere
                        background: null
                    }
                }
            }

            // Rodapé com Ações Acionáveis
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                Item { Layout.fillWidth: true }

                // Botão "Fechar"
                Rectangle {
                    implicitWidth: 90
                    implicitHeight: 38
                    radius: root.getToken("radiusFull", 9999)
                    color: btnCloseArea.containsMouse ? root.getToken("surfaceContainerHighest", "#363435") : "transparent"
                    border.width: 1
                    border.color: root.getToken("outlineVariant", "#49454f")

                    Text {
                        anchors.centerIn: parent
                        text: "Fechar"
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        color: root.getToken("onSurface", "#e6e1e1")
                    }

                    MouseArea {
                        id: btnCloseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.isOpen = false;
                            root.closed();
                        }
                    }
                }

                // Botão "Executar diagnóstico"
                Rectangle {
                    implicitWidth: 170
                    implicitHeight: 38
                    radius: root.getToken("radiusFull", 9999)
                    color: btnDiagArea.containsMouse ? root.getToken("secondaryContainer", "#4a4458") : root.getToken("surfaceContainerHighest", "#363435")
                    border.width: 1
                    border.color: root.getToken("outlineVariant", "#49454f")

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: "health_and_safety"
                            font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                            font.pixelSize: 16
                            color: root.getToken("secondary", "#ccc2dc")
                        }

                        Text {
                            text: "Executar diagnóstico"
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            color: root.getToken("onSurface", "#e6e1e1")
                        }
                    }

                    MouseArea {
                        id: btnDiagArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.runDoctorRequested()
                    }
                }

                // Botão "Reparar componente"
                Rectangle {
                    implicitWidth: 160
                    implicitHeight: 38
                    radius: root.getToken("radiusFull", 9999)
                    color: root.isRepairing ? root.getToken("surfaceContainerHighest", "#363435") :
                           btnRepairArea.containsMouse ? Qt.darker(root.getToken("primary", "#d0bcff"), 1.1) : root.getToken("primary", "#d0bcff")

                    RowLayout {
                        anchors.centerIn: parent
                        spacing: 6

                        BusyIndicator {
                            running: root.isRepairing
                            visible: root.isRepairing
                            implicitWidth: 18
                            implicitHeight: 18
                        }

                        Text {
                            visible: !root.isRepairing
                            text: "build"
                            font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                            font.pixelSize: 16
                            color: root.getToken("onPrimary", "#381e72")
                        }

                        Text {
                            text: root.isRepairing ? "Reparando..." : "Reparar componente"
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 13
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
                        onClicked: root.repairRequested()
                    }
                }
            }
        }
    }
}
