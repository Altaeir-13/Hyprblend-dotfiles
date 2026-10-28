import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../components"

Rectangle {
    id: root

    // --- Contratos de Propriedades e Sinais ---
    property var theme: null
    property var storeBridge: null
    property bool explicitOnly: true
    property string localFilterText: ""

    signal packageSelected(string pkgName, string repository)
    signal actionRequested(string action, string pkgName, string repository)
    signal explicitFilterToggled(bool explicitOnly)
    signal refreshInstalledRequested()

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

    readonly property bool isBusy: root.storeBridge ? root.storeBridge.isBusy : false
    readonly property int totalCount: (root.storeBridge && root.storeBridge.installedCount !== undefined) ?
                                      root.storeBridge.installedCount : 0
    readonly property int modelCount: (root.storeBridge && root.storeBridge.installedModel && root.storeBridge.installedModel.count !== undefined) ?
                                      root.storeBridge.installedModel.count : 0

    color: getToken("surface", "#141313")

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 14

        // 1. Cabeçalho com Título, Estatística e Ações Rápidas
        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: "Biblioteca de Aplicativos"
                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                    font.pixelSize: 22
                    font.weight: Font.Bold
                    color: root.getToken("onSurface", "#e6e1e1")
                }

                Text {
                    text: (root.totalCount > 0 ? root.totalCount : root.modelCount) +
                          " pacote(s) instalados no sistema" +
                          (root.explicitOnly ? " (instalados explicitamente)" : " (todos os pacotes)")
                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                    font.pixelSize: 12
                    color: root.getToken("onSurfaceVariant", "#cbc5ca")
                }
            }

            // Campo de Filtro Local Instantâneo
            Rectangle {
                width: 220
                height: 38
                radius: root.getToken("radiusFull", 9999)
                color: root.getToken("surfaceContainerHigh", "#2b2a2a")
                border.width: localFilterInput.activeFocus ? 1.5 : 1
                border.color: localFilterInput.activeFocus ?
                    root.getToken("primary", "#d0bcff") : root.getToken("outlineVariant", "#49454f")

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 10
                    spacing: 6

                    Text {
                        text: "filter_list"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 17
                        color: root.getToken("onSurfaceVariant", "#cbc5ca")
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        Text {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            text: "Filtrar instalados..."
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 12
                            color: root.getToken("onSurfaceVariant", "#cbc5ca")
                            opacity: 0.6
                            visible: localFilterInput.text.length === 0
                        }

                        TextInput {
                            id: localFilterInput
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 12
                            color: root.getToken("onSurface", "#e6e1e1")
                            selectByMouse: true
                            clip: true
                            onTextChanged: root.localFilterText = text.toLowerCase().trim()
                        }
                    }

                    // Botão limpar filtro local
                    Text {
                        visible: localFilterInput.text.length > 0
                        text: "close"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 15
                        color: root.getToken("onSurfaceVariant", "#cbc5ca")

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: localFilterInput.text = ""
                        }
                    }
                }
            }

            // Toggle "Apenas Explícitos" vs "Todos"
            Rectangle {
                implicitWidth: toggleRow.implicitWidth + 20
                height: 38
                radius: root.getToken("radiusFull", 9999)
                color: root.explicitOnly ?
                    root.getToken("secondaryContainer", "#4a4458") :
                    root.getToken("surfaceContainer", "#201f20")
                border.width: 1
                border.color: root.explicitOnly ?
                    root.getToken("primary", "#d0bcff") :
                    root.getToken("outlineVariant", "#49454f")

                RowLayout {
                    id: toggleRow
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        text: root.explicitOnly ? "check_circle" : "tune"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 16
                        color: root.explicitOnly ?
                            root.getToken("primary", "#d0bcff") :
                            root.getToken("onSurfaceVariant", "#cbc5ca")
                    }

                    Text {
                        text: root.explicitOnly ? "Apenas Explícitos" : "Todos os Pacotes"
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        color: root.getToken("onSurface", "#e6e1e1")
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.explicitOnly = !root.explicitOnly;
                        root.explicitFilterToggled(root.explicitOnly);
                    }
                }
            }

            // Botão "Atualizar Lista"
            Rectangle {
                width: 38
                height: 38
                radius: root.getToken("radiusNormal", 14)
                color: refreshMouse.containsMouse ?
                    root.getToken("surfaceContainerHigh", "#2b2a2a") :
                    root.getToken("surfaceContainer", "#201f20")
                border.width: 1
                border.color: root.getToken("outlineVariant", "#49454f")

                Text {
                    anchors.centerIn: parent
                    text: "refresh"
                    font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                    font.pixelSize: 19
                    color: root.getToken("onSurfaceVariant", "#cbc5ca")

                    RotationAnimation on rotation {
                        running: root.isBusy
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 1000
                    }
                }

                MouseArea {
                    id: refreshMouse
                    anchors.fill: parent
                    hoverEnabled: !root.isBusy
                    cursorShape: root.isBusy ? Qt.ForbiddenCursor : Qt.PointingHandCursor
                    enabled: !root.isBusy
                    onClicked: root.refreshInstalledRequested()
                }
            }
        }

        // Divisor
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: root.getToken("outlineVariant", "#49454f")
            opacity: 0.25
        }

        // 2. Grade de Pacotes Instalados
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            GridView {
                id: installedGridView
                anchors.fill: parent
                clip: true
                cellWidth: 334
                cellHeight: 196
                boundsBehavior: Flickable.StopAtBounds
                visible: root.modelCount > 0

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    active: installedGridView.moving || installedGridView.flicking
                }

                model: root.storeBridge ? root.storeBridge.installedModel : null

                delegate: Item {
                    id: delegateItem
                    width: installedGridView.cellWidth
                    height: installedGridView.cellHeight

                    readonly property string pName: (model && model.name !== undefined) ? model.name : ""
                    readonly property string dName: (model && model.displayName !== undefined) ? model.displayName : ""
                    readonly property bool matchesFilter: root.localFilterText.length === 0 ||
                                                          pName.toLowerCase().includes(root.localFilterText) ||
                                                          dName.toLowerCase().includes(root.localFilterText)

                    visible: matchesFilter

                    PackageCard {
                        anchors.centerIn: parent
                        width: 320
                        height: 184
                        theme: root.theme
                        isBusy: root.isBusy

                        pkgName: delegateItem.pName
                        displayName: delegateItem.dName
                        summary: (model && model.summary !== undefined) ? model.summary : ""
                        version: (model && model.version !== undefined) ? model.version : ""
                        installedVersion: (model && model.installedVersion !== undefined) ? model.installedVersion : ""
                        repository: (model && model.repository !== undefined) ? model.repository : "extra"
                        source: (model && model.source !== undefined) ? model.source : "official"
                        installed: true
                        updateAvailable: (model && model.updateAvailable !== undefined) ? model.updateAvailable : false
                        category: (model && model.category !== undefined) ? model.category : "utilities"
                        iconName: (model && model.iconName !== undefined) ? model.iconName : ""
                        votes: (model && model.votes !== undefined) ? model.votes : 0

                        onClicked: root.packageSelected(pkgName, repository)
                        onActionTriggered: (action, pkg, repo) => root.actionRequested(action, pkg, repo)
                    }

                    // Badge de Proteção do Sistema (para pacotes críticos)
                    Rectangle {
                        visible: model && model.isProtected === true
                        anchors.top: parent.top
                        anchors.topMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        implicitWidth: shieldRow.implicitWidth + 10
                        height: 20
                        radius: root.getToken("radiusSmall", 8)
                        color: root.getToken("secondaryContainer", "#4a4458")
                        border.width: 1
                        border.color: root.getToken("primary", "#d0bcff")

                        RowLayout {
                            id: shieldRow
                            anchors.centerIn: parent
                            spacing: 3

                            Text {
                                text: "shield"
                                font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                                font.pixelSize: 12
                                color: root.getToken("primary", "#d0bcff")
                            }

                            Text {
                                text: "Protegido"
                                font.family: root.getToken("fontFamily", "Google Sans Flex")
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                color: root.getToken("onSecondaryContainer", "#e8def8")
                            }
                        }
                    }
                }
            }

            // Estado Vazio quando não há pacotes ou filtro não encontrou
            ColumnLayout {
                anchors.centerIn: parent
                visible: root.modelCount === 0 || (root.localFilterText.length > 0 && installedGridView.count === 0)
                spacing: 12

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "inventory_2"
                    font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                    font.pixelSize: 48
                    color: root.getToken("outline", "#938f99")
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.localFilterText.length > 0 ?
                        ("Nenhum pacote corresponde a \"" + root.localFilterText + "\"") :
                        "Nenhum pacote instalado encontrado."
                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    color: root.getToken("onSurface", "#e6e1e1")
                }
            }
        }
    }
}
