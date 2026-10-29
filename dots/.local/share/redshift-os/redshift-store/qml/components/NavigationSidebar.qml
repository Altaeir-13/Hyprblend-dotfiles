import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    // --- Contratos de Propriedades e Sinais ---
    property var theme: null
    property string currentPage: "home"
    property int installedCount: 0
    property int updatesCount: 0
    property bool isBusy: false
    property string schemeVariant: "tonal-spot"
    property bool isDark: true
    property string frontendMode: "end-4"
    property string activeShellMode: frontendMode

    signal pageSelected(string pageId)
    signal toggleLogsRequested()

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

    implicitWidth: 250
    implicitHeight: 700
    color: getToken("surfaceContainerLow", "#1c1b1c")

    // Divisor vertical à direita
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 1
        color: root.getToken("outlineVariant", "#49454f")
        opacity: 0.5
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 16

        // 1. Cabeçalho de Marca da Redshift Store
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Emblema visual
            Rectangle {
                width: 42
                height: 42
                radius: root.getToken("radiusNormal", 14)
                color: root.getToken("primaryContainer", "#4f378b")

                Text {
                    anchors.centerIn: parent
                    text: "shopping_bag"
                    font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                    font.pixelSize: 22
                    color: root.getToken("onPrimaryContainer", "#eaddff")
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: "Redshift Store"
                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    color: root.getToken("onSurface", "#e6e1e1")
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                RowLayout {
                    spacing: 6

                    Rectangle {
                        width: 7
                        height: 7
                        radius: 4
                        color: root.isBusy ? root.getToken("warning", "#fbc02d") : root.getToken("success", "#b5ccba")
                        Behavior on color { ColorAnimation { duration: 250 } }
                    }

                    Text {
                        text: (root.frontendMode === "caelestia" ? "Caelestia Shell" : "end-4 Shell") + (root.isBusy ? " • Ocupado" : " • Pronto")
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 11
                        color: root.getToken("onSurfaceVariant", "#cbc5ca")
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // Divisor horizontal discreto
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: root.getToken("outlineVariant", "#49454f")
            opacity: 0.35
        }

        // 2. Itens de Navegação (Microsoft Store Rail)
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: [
                    { id: "home", label: "Início", icon: "home", badge: 0, highlight: false },
                    { id: "catalog", label: "Explorar", icon: "explore", badge: 0, highlight: false },
                    { id: "installed", label: "Instalados", icon: "inventory_2", badge: root.installedCount, highlight: false },
                    { id: "updates", label: "Atualizações", icon: "system_update_alt", badge: root.updatesCount, highlight: root.updatesCount > 0 }
                ]

                delegate: Rectangle {
                    id: navItem
                    required property var modelData
                    Layout.fillWidth: true
                    height: 44
                    radius: root.getToken("radiusNormal", 14)

                    readonly property bool isSelected: root.currentPage === modelData.id
                    readonly property bool isHovered: itemMouseArea.containsMouse

                    color: {
                        if (isSelected) return root.getToken("secondaryContainer", "#4a4458");
                        if (isHovered) return root.getToken("surfaceContainerHigh", "#2b2a2a");
                        return "transparent";
                    }

                    Behavior on color {
                        ColorAnimation { duration: 180; easing.type: Easing.OutQuad }
                    }

                    // Indicador vertical esquerdo de seleção ativa
                    Rectangle {
                        anchors.left: parent.left
                        anchors.leftMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3.5
                        height: navItem.isSelected ? 20 : 0
                        radius: 2
                        color: root.getToken("primary", "#d0bcff")
                        visible: navItem.isSelected
                        Behavior on height {
                            NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                        }
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 14
                        spacing: 12

                        Text {
                            text: navItem.modelData.icon
                            font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                            font.pixelSize: 20
                            color: navItem.isSelected ?
                                root.getToken("primary", "#d0bcff") :
                                (navItem.isHovered ? root.getToken("onSurface", "#e6e1e1") : root.getToken("onSurfaceVariant", "#cbc5ca"))
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        Text {
                            text: navItem.modelData.label
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 14
                            font.weight: navItem.isSelected ? Font.Medium : Font.Normal
                            color: navItem.isSelected ?
                                root.getToken("onSurface", "#e6e1e1") :
                                (navItem.isHovered ? root.getToken("onSurface", "#e6e1e1") : root.getToken("onSurfaceVariant", "#cbc5ca"))
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        // Badge numérico
                        Rectangle {
                            visible: navItem.modelData.badge > 0
                            implicitWidth: Math.max(badgeText.implicitWidth + 12, 22)
                            height: 20
                            radius: root.getToken("radiusFull", 9999)
                            color: navItem.modelData.highlight ?
                                root.getToken("primary", "#d0bcff") :
                                root.getToken("surfaceContainerHighest", "#363435")

                            Text {
                                id: badgeText
                                anchors.centerIn: parent
                                text: navItem.modelData.badge > 999 ? "999+" : navItem.modelData.badge.toString()
                                font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: navItem.modelData.highlight ?
                                    root.getToken("onPrimary", "#381e72") :
                                    root.getToken("onSurface", "#e6e1e1")
                            }
                        }
                    }

                    MouseArea {
                        id: itemMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.pageSelected(navItem.modelData.id)
                    }
                }
            }
        }

        // Espaço elástico vertical
        Item {
            Layout.fillHeight: true
        }

        // 3. Botão do Console de Operações (com indicador se isBusy)
        Rectangle {
            id: logsBtn
            Layout.fillWidth: true
            height: 44
            radius: root.getToken("radiusNormal", 14)
            color: logsMouseArea.containsMouse ?
                root.getToken("surfaceContainerHigh", "#2b2a2a") :
                (root.isBusy ? root.getToken("primaryContainer", "#4f378b") : root.getToken("surfaceContainer", "#201f20"))
            border.width: 1
            border.color: root.isBusy ? root.getToken("primary", "#d0bcff") : root.getToken("outlineVariant", "#49454f")

            Behavior on color { ColorAnimation { duration: 180 } }
            Behavior on border.color { ColorAnimation { duration: 180 } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 10

                Text {
                    text: root.isBusy ? "sync" : "terminal"
                    font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                    font.pixelSize: 20
                    color: root.isBusy ? root.getToken("primary", "#d0bcff") : root.getToken("onSurfaceVariant", "#cbc5ca")

                    RotationAnimation on rotation {
                        running: root.isBusy
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 1200
                    }
                }

                Text {
                    text: root.isBusy ? "Operação em curso..." : "Console de Logs"
                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                    font.pixelSize: 13
                    font.weight: root.isBusy ? Font.Medium : Font.Normal
                    color: root.isBusy ? root.getToken("onPrimaryContainer", "#eaddff") : root.getToken("onSurface", "#e6e1e1")
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Text {
                    text: "expand_less"
                    font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                    font.pixelSize: 18
                    color: root.getToken("onSurfaceVariant", "#cbc5ca")
                }
            }

            MouseArea {
                id: logsMouseArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleLogsRequested()
            }
        }

        // 4. Card Compacto e Passivo de Status Material You / Matugen (Informativo)
        Rectangle {
            id: themeCard
            Layout.fillWidth: true
            height: 52
            radius: root.getToken("radiusNormal", 14)
            color: root.getToken("surfaceContainerLowest", "#0f0e0e")
            border.width: 1
            border.color: Qt.alpha(root.getToken("outlineVariant", "#49454f"), 0.5)

            Behavior on color { ColorAnimation { duration: 180 } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                anchors.topMargin: 8
                anchors.bottomMargin: 8
                spacing: 10

                // Ícone de paleta / modo
                Rectangle {
                    width: 32
                    height: 32
                    radius: root.getToken("radiusSmall", 8)
                    color: root.getToken("surfaceContainerHigh", "#2b2a2a")

                    Text {
                        anchors.centerIn: parent
                        text: root.isDark ? "dark_mode" : "light_mode"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 18
                        color: root.getToken("primary", "#d0bcff")
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: root.schemeVariant.replace("scheme-", "").replace("-", " ").toUpperCase()
                        font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: root.getToken("primary", "#d0bcff")
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: (root.isDark ? "Modo Escuro" : "Modo Claro") + " • " + (root.activeShellMode === "caelestia" ? "Caelestia" : "end-4")
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 11
                        color: root.getToken("onSurfaceVariant", "#cbc5ca")
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
