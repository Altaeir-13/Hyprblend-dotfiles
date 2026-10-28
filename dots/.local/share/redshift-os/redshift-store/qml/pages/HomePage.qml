import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../components"

Rectangle {
    id: root

    // --- Contratos de Propriedades e Sinais ---
    property var theme: null
    property var storeBridge: null
    property var themeBridge: null

    signal packageSelected(string pkgName, string repository)
    signal actionRequested(string action, string pkgName, string repository)
    signal exploreRequested(string sourceFilter)
    signal categorySelected(string categoryId)
    signal navigateUpdatesRequested()

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

    color: getToken("surface", "#141313")

    Flickable {
        id: scrollArea
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight + 40
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
            active: scrollArea.moving || scrollArea.flicking
        }

        ColumnLayout {
            id: contentColumn
            width: scrollArea.width - 32
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 16
            spacing: 24

            // 1. Hero Banner Principal
            HeroBanner {
                Layout.fillWidth: true
                theme: root.theme
                installedCount: root.storeBridge ? root.storeBridge.installedCount : 0
                updatesCount: root.storeBridge ? root.storeBridge.updatesCount : 0
                frontendMode: (root.themeBridge && root.themeBridge.frontendMode) ? root.themeBridge.frontendMode : "end-4"
                isBusy: root.storeBridge ? root.storeBridge.isBusy : false

                onExploreOfficialClicked: root.exploreRequested("official")
                onExploreAurClicked: root.exploreRequested("aur")
                onCheckUpdatesClicked: root.navigateUpdatesRequested()
            }

            // 2. Seção de Categorias Populares
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "category"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 20
                        color: root.getToken("primary", "#d0bcff")
                    }

                    Text {
                        text: "Categorias Populares"
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                        color: root.getToken("onSurface", "#e6e1e1")
                    }
                }

                CategoryChipBar {
                    Layout.fillWidth: true
                    theme: root.theme
                    selectedCategory: root.storeBridge ? root.storeBridge.activeCategory : "all"
                    onCategorySelected: (catId) => root.categorySelected(catId)
                }
            }

            // 3. Seção de Aplicativos em Destaque
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "auto_awesome"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 20
                        color: root.getToken("tertiary", "#efb8c8")
                    }

                    Text {
                        text: "Destaques e Recomendações"
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 18
                        font.weight: Font.DemiBold
                        color: root.getToken("onSurface", "#e6e1e1")
                    }

                    Item { Layout.fillWidth: true }

                    // Botão "Ver todos"
                    Rectangle {
                        implicitWidth: verTodosRow.implicitWidth + 16
                        height: 30
                        radius: root.getToken("radiusFull", 9999)
                        color: verTodosMouse.containsMouse ?
                            root.getToken("surfaceContainerHigh", "#2b2a2a") : "transparent"

                        RowLayout {
                            id: verTodosRow
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                text: "Ver todos"
                                font.family: root.getToken("fontFamily", "Google Sans Flex")
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                color: root.getToken("primary", "#d0bcff")
                            }

                            Text {
                                text: "arrow_forward"
                                font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                                font.pixelSize: 15
                                color: root.getToken("primary", "#d0bcff")
                            }
                        }

                        MouseArea {
                            id: verTodosMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.exploreRequested("all")
                        }
                    }
                }

                // Grade Fluida de Cartões
                Flow {
                    id: cardsFlow
                    Layout.fillWidth: true
                    spacing: 14

                    Repeater {
                        model: root.storeBridge ? root.storeBridge.featuredModel : null

                        delegate: PackageCard {
                            width: 320
                            height: 184
                            theme: root.theme
                            isBusy: root.storeBridge ? root.storeBridge.isBusy : false

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
            }
        }
    }
}
