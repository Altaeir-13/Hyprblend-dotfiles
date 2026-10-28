import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../components"

Rectangle {
    id: root

    // --- Contratos de Propriedades e Sinais ---
    property var theme: null
    property var storeBridge: null

    signal packageSelected(string pkgName, string repository)
    signal actionRequested(string action, string pkgName, string repository)
    signal categorySelected(string categoryId)
    signal sourceFilterSelected(string sourceFilter)
    signal switchSourceRequested(string targetSource)

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

    readonly property bool isBusy: (root.storeBridge && root.storeBridge.isBusy) ||
                                   (root.storeBridge && root.storeBridge.operationState === "searching")
    readonly property int resultCount: (root.storeBridge && root.storeBridge.catalogModel && root.storeBridge.catalogModel.count !== undefined) ?
                                        root.storeBridge.catalogModel.count : 0
    readonly property string currentSource: (root.storeBridge && root.storeBridge.activeSourceFilter) ?
                                            root.storeBridge.activeSourceFilter : "all"
    readonly property string currentQuery: (root.storeBridge && root.storeBridge.searchQuery) ?
                                           root.storeBridge.searchQuery : ""
    readonly property string currentCategory: (root.storeBridge && root.storeBridge.activeCategory) ?
                                              root.storeBridge.activeCategory : "all"

    color: getToken("surface", "#141313")

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 14

        // 1. Cabeçalho do Catálogo
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: root.currentQuery.length > 0 ?
                        ("Resultados para \"" + root.currentQuery + "\"") : "Explorar Catálogo"
                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                    font.pixelSize: 22
                    font.weight: Font.Bold
                    color: root.getToken("onSurface", "#e6e1e1")
                }

                RowLayout {
                    spacing: 6

                    Text {
                        text: {
                            let srcName = root.currentSource === "official" ? "Oficial Pacman" :
                                          root.currentSource === "aur" ? "AUR" : "Todas as fontes";
                            let catName = root.currentCategory === "all" ? "Todas as categorias" : root.currentCategory;
                            return root.resultCount + " pacote(s) encontrado(s) • " + srcName + " • " + catName;
                        }
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 12
                        color: root.getToken("onSurfaceVariant", "#cbc5ca")
                    }

                    // Indicador de busca ativa
                    Rectangle {
                        visible: root.isBusy
                        width: 14
                        height: 14
                        radius: 7
                        color: "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "sync"
                            font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                            font.pixelSize: 14
                            color: root.getToken("primary", "#d0bcff")

                            RotationAnimation on rotation {
                                running: root.isBusy
                                loops: Animation.Infinite
                                from: 0
                                to: 360
                                duration: 1000
                            }
                        }
                    }
                }
            }
        }

        // 2. Barra de Categorias Horizontal
        CategoryChipBar {
            Layout.fillWidth: true
            theme: root.theme
            selectedCategory: root.currentCategory
            onCategorySelected: (catId) => root.categorySelected(catId)
        }

        // Divisor sutil
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: root.getToken("outlineVariant", "#49454f")
            opacity: 0.25
        }

        // 3. Área de Conteúdo: Grade de Resultados ou Estado Vazio
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Grade de Pacotes
            GridView {
                id: catalogGridView
                anchors.fill: parent
                clip: true
                cellWidth: 334
                cellHeight: 196
                boundsBehavior: Flickable.StopAtBounds
                visible: !root.isBusy && root.resultCount > 0

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    active: catalogGridView.moving || catalogGridView.flicking
                }

                model: root.storeBridge ? root.storeBridge.catalogModel : null

                delegate: Item {
                    width: catalogGridView.cellWidth
                    height: catalogGridView.cellHeight

                    PackageCard {
                        anchors.centerIn: parent
                        width: 320
                        height: 184
                        theme: root.theme
                        isBusy: root.isBusy

                        pkgName: (model && model.name !== undefined) ? model.name : ""
                        displayName: (model && model.displayName !== undefined) ? model.displayName : ""
                        summary: (model && model.summary !== undefined) ? model.summary : ""
                        version: (model && model.version !== undefined) ? model.version : ""
                        installedVersion: (model && model.installedVersion !== undefined) ? model.installedVersion : ""
                        repository: (model && model.repository !== undefined) ? model.repository : "extra"
                        source: (model && model.source !== undefined) ? model.source : "official"
                        installed: (model && model.installed !== undefined) ? model.installed : false
                        updateAvailable: (model && model.updateAvailable !== undefined) ? model.updateAvailable : false
                        category: (model && model.category !== undefined) ? model.category : "utilities"
                        iconName: (model && model.iconName !== undefined) ? model.iconName : ""
                        votes: (model && model.votes !== undefined) ? model.votes : 0

                        onClicked: root.packageSelected(pkgName, repository)
                        onActionTriggered: (action, pName, pRepo) => root.actionRequested(action, pName, pRepo)
                    }
                }
            }

            // Estado de Carregamento
            ColumnLayout {
                anchors.centerIn: parent
                visible: root.isBusy
                spacing: 12

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "progress_activity"
                    font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                    font.pixelSize: 42
                    color: root.getToken("primary", "#d0bcff")

                    RotationAnimation on rotation {
                        running: root.isBusy
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 1100
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Pesquisando e indexando repositórios..."
                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                    font.pixelSize: 14
                    color: root.getToken("onSurfaceVariant", "#cbc5ca")
                }
            }

            // Estado Vazio (Nenhum resultado)
            ColumnLayout {
                anchors.centerIn: parent
                visible: !root.isBusy && root.resultCount === 0
                spacing: 14
                width: 420

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 72
                    height: 72
                    radius: 36
                    color: root.getToken("surfaceContainerHigh", "#2b2a2a")

                    Text {
                        anchors.centerIn: parent
                        text: "search_off"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 36
                        color: root.getToken("outline", "#938f99")
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Nenhum pacote encontrado"
                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                    color: root.getToken("onSurface", "#e6e1e1")
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.currentQuery.length > 0 ?
                        ("Não foram encontrados pacotes para \"" + root.currentQuery + "\". Verifique o termo ou tente outra fonte.") :
                        "Nenhum pacote disponível para a categoria selecionada."
                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                    font.pixelSize: 13
                    color: root.getToken("onSurfaceVariant", "#cbc5ca")
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                // Sugestão de buscar no AUR se estiver no oficial
                Rectangle {
                    visible: root.currentSource !== "aur" && root.currentQuery.length > 0
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: aurSuggestRow.implicitWidth + 24
                    height: 38
                    radius: root.getToken("radiusFull", 9999)
                    color: aurSuggestMouse.containsMouse ?
                        root.getToken("tertiary", "#efb8c8") :
                        root.getToken("tertiaryContainer", "#633b48")
                    border.width: 1
                    border.color: root.getToken("tertiary", "#efb8c8")

                    Behavior on color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        id: aurSuggestRow
                        anchors.centerIn: parent
                        spacing: 8

                        Text {
                            text: "cloud_download"
                            font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                            font.pixelSize: 18
                            color: aurSuggestMouse.containsMouse ?
                                root.getToken("onTertiary", "#492532") :
                                root.getToken("onTertiaryContainer", "#ffd8e4")
                        }

                        Text {
                            text: "Buscar no Repositório Comunitário AUR"
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: aurSuggestMouse.containsMouse ?
                                root.getToken("onTertiary", "#492532") :
                                root.getToken("onTertiaryContainer", "#ffd8e4")
                        }
                    }

                    MouseArea {
                        id: aurSuggestMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.switchSourceRequested("aur")
                    }
                }
            }
        }
    }
}
