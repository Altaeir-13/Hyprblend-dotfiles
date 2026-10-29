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
    signal sectionExploreRequested(string sectionId)
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

    function triggerSectionExplore(sectionId) {
        if (root.storeBridge && root.storeBridge.exploreSection) {
            root.storeBridge.exploreSection(sectionId);
        }
        root.sectionExploreRequested(sectionId);
    }

    color: getToken("surface", "#141313")

    Flickable {
        id: scrollArea
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight + 48
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
            spacing: 32

            // =================================================================
            // 1. Hero Banner Principal + Barra de Categorias Rápidas
            // =================================================================
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

            // Categorias Populares (Acesso Rápido)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12

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
                        text: "Categorias em Destaque"
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

            // =================================================================
            // 2. Recomendados para Você (Privacidade XDG + Model Local)
            // =================================================================
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12

                // Cabeçalho da Seção com Controles Transparentes de Privacidade
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    Text {
                        text: "recommend"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 22
                        color: root.getToken("primary", "#d0bcff")
                    }

                    ColumnLayout {
                        spacing: 2
                        Text {
                            text: "Recomendados para Você"
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 18
                            font.weight: Font.DemiBold
                            color: root.getToken("onSurface", "#e6e1e1")
                        }
                        Text {
                            text: "Sugestões personalizadas computadas 100% no seu dispositivo sem telemetria remota."
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 11
                            color: root.getToken("onSurfaceVariant", "#cbc5ca")
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Badge de Privacidade: "100% Local (XDG)"
                    Rectangle {
                        implicitWidth: xdgBadgeRow.implicitWidth + 12
                        height: 24
                        radius: root.getToken("radiusFull", 9999)
                        color: root.getToken("surfaceContainerHighest", "#363435")
                        border.width: 1
                        border.color: root.getToken("outlineVariant", "#49454f")

                        RowLayout {
                            id: xdgBadgeRow
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                text: "security"
                                font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                                font.pixelSize: 13
                                color: root.getToken("success", "#b5ccba")
                            }

                            Text {
                                text: "100% Local (XDG)"
                                font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: root.getToken("onSurfaceVariant", "#cbc5ca")
                            }
                        }
                    }

                    // Toggle Chip: Personalização Ativa / Desativada
                    Rectangle {
                        id: persToggleChip
                        readonly property bool isPersActive: root.storeBridge && root.storeBridge.personalizationEnabled !== undefined ?
                                                             root.storeBridge.personalizationEnabled : true

                        implicitWidth: persToggleRow.implicitWidth + 16
                        height: 28
                        radius: root.getToken("radiusFull", 9999)
                        color: isPersActive ? root.getToken("primaryContainer", "#4f378b") : root.getToken("surfaceContainer", "#201f20")
                        border.width: 1
                        border.color: isPersActive ? root.getToken("primary", "#d0bcff") : root.getToken("outlineVariant", "#49454f")

                        RowLayout {
                            id: persToggleRow
                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                text: persToggleChip.isPersActive ? "toggle_on" : "toggle_off"
                                font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                                font.pixelSize: 16
                                color: persToggleChip.isPersActive ? root.getToken("onPrimaryContainer", "#eaddff") : root.getToken("onSurfaceVariant", "#cbc5ca")
                            }

                            Text {
                                text: persToggleChip.isPersActive ? "Personalização Ativa" : "Personalização Desativada"
                                font.family: root.getToken("fontFamily", "Google Sans Flex")
                                font.pixelSize: 11
                                font.weight: Font.Medium
                                color: persToggleChip.isPersActive ? root.getToken("onPrimaryContainer", "#eaddff") : root.getToken("onSurfaceVariant", "#cbc5ca")
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.storeBridge && root.storeBridge.setPersonalizationEnabled) {
                                    root.storeBridge.setPersonalizationEnabled(!persToggleChip.isPersActive);
                                }
                            }
                        }
                    }

                    // Botão "Limpar Histórico" (se hasPersonalizationHistory for true)
                    Rectangle {
                        visible: root.storeBridge && root.storeBridge.hasPersonalizationHistory === true
                        implicitWidth: clearHistRow.implicitWidth + 14
                        height: 28
                        radius: root.getToken("radiusFull", 9999)
                        color: clearHistMouse.containsMouse ? root.getToken("errorContainer", "#8c1d18") : root.getToken("surfaceContainer", "#201f20")
                        border.width: 1
                        border.color: root.getToken("outlineVariant", "#49454f")

                        RowLayout {
                            id: clearHistRow
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                text: "delete_sweep"
                                font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                                font.pixelSize: 14
                                color: clearHistMouse.containsMouse ? root.getToken("onErrorContainer", "#f9dedc") : root.getToken("onSurfaceVariant", "#cbc5ca")
                            }

                            Text {
                                text: "Limpar histórico"
                                font.family: root.getToken("fontFamily", "Google Sans Flex")
                                font.pixelSize: 11
                                color: clearHistMouse.containsMouse ? root.getToken("onErrorContainer", "#f9dedc") : root.getToken("onSurfaceVariant", "#cbc5ca")
                            }
                        }

                        MouseArea {
                            id: clearHistMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.storeBridge && root.storeBridge.clearPersonalizationHistory) {
                                    root.storeBridge.clearPersonalizationHistory();
                                }
                            }
                        }
                    }

                    // Botão "Ver mais"
                    Rectangle {
                        implicitWidth: verMaisRecRow.implicitWidth + 16
                        height: 30
                        radius: root.getToken("radiusFull", 9999)
                        color: verMaisRecMouse.containsMouse ? root.getToken("surfaceContainerHigh", "#2b2a2a") : "transparent"

                        RowLayout {
                            id: verMaisRecRow
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                text: "Ver mais"
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
                            id: verMaisRecMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.triggerSectionExplore("recommended")
                        }
                    }
                }

                // Lista Horizontal de Recomendados
                ListView {
                    id: recListView
                    Layout.fillWidth: true
                    implicitHeight: 204
                    orientation: ListView.Horizontal
                    spacing: 14
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    WheelHandler {
                        orientation: Qt.Horizontal
                        onWheel: (event) => {
                            recListView.contentX = Math.max(0, Math.min(recListView.contentWidth - recListView.width, recListView.contentX - event.angleDelta.y));
                        }
                    }

                    model: (root.storeBridge && root.storeBridge.recommendedModel) ?
                           root.storeBridge.recommendedModel :
                           (root.storeBridge ? root.storeBridge.featuredModel : null)

                    delegate: PackageCard {
                        width: 320
                        height: 200
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
                        popularityLabel: (model && model.popularityLabel !== undefined) ? model.popularityLabel : ""
                        provenanceLabel: (model && model.provenanceLabel !== undefined) ? model.provenanceLabel : ""
                        isFavorite: (model && model.isFavorite !== undefined) ? model.isFavorite : false

                        onClicked: root.packageSelected(pkgName, repository)
                        onActionTriggered: (action, pName, pRepo) => root.actionRequested(action, pName, pRepo)
                        onFavoriteToggled: (pName) => {
                            if (root.storeBridge && root.storeBridge.toggleFavorite) {
                                root.storeBridge.toggleFavorite(pName);
                            }
                        }
                    }
                }
            }

            // =================================================================
            // 3. Populares na Comunidade (Arch pkgstats + AUR RPC)
            // =================================================================
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "trending_up"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 22
                        color: root.getToken("tertiary", "#efb8c8")
                    }

                    ColumnLayout {
                        spacing: 2
                        Text {
                            text: "Populares na Comunidade"
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 18
                            font.weight: Font.DemiBold
                            color: root.getToken("onSurface", "#e6e1e1")
                        }
                        Text {
                            text: "Baseado na amostra voluntária Arch pkgstats (repositórios oficiais) e votos/popularidade do AUR RPC."
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 11
                            color: root.getToken("onSurfaceVariant", "#cbc5ca")
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        implicitWidth: verMaisPopRow.implicitWidth + 16
                        height: 30
                        radius: root.getToken("radiusFull", 9999)
                        color: verMaisPopMouse.containsMouse ? root.getToken("surfaceContainerHigh", "#2b2a2a") : "transparent"

                        RowLayout {
                            id: verMaisPopRow
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                text: "Ver mais"
                                font.family: root.getToken("fontFamily", "Google Sans Flex")
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                color: root.getToken("tertiary", "#efb8c8")
                            }

                            Text {
                                text: "arrow_forward"
                                font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                                font.pixelSize: 15
                                color: root.getToken("tertiary", "#efb8c8")
                            }
                        }

                        MouseArea {
                            id: verMaisPopMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.triggerSectionExplore("popular_community")
                        }
                    }
                }

                ListView {
                    id: popListView
                    Layout.fillWidth: true
                    implicitHeight: 204
                    orientation: ListView.Horizontal
                    spacing: 14
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    WheelHandler {
                        orientation: Qt.Horizontal
                        onWheel: (event) => {
                            popListView.contentX = Math.max(0, Math.min(popListView.contentWidth - popListView.width, popListView.contentX - event.angleDelta.y));
                        }
                    }

                    model: (root.storeBridge && root.storeBridge.popularCommunityModel) ?
                           root.storeBridge.popularCommunityModel :
                           (root.storeBridge ? root.storeBridge.featuredModel : null)

                    delegate: PackageCard {
                        width: 320
                        height: 200
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
                        popularityLabel: (model && model.popularityLabel !== undefined) ? model.popularityLabel : ""
                        provenanceLabel: (model && model.provenanceLabel !== undefined) ? model.provenanceLabel : ""
                        isFavorite: (model && model.isFavorite !== undefined) ? model.isFavorite : false

                        onClicked: root.packageSelected(pkgName, repository)
                        onActionTriggered: (action, pName, pRepo) => root.actionRequested(action, pName, pRepo)
                        onFavoriteToggled: (pName) => {
                            if (root.storeBridge && root.storeBridge.toggleFavorite) {
                                root.storeBridge.toggleFavorite(pName);
                            }
                        }
                    }
                }
            }

            // =================================================================
            // 4. Comece por Aqui (gettingStartedModel)
            // =================================================================
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "flag"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 22
                        color: root.getToken("secondary", "#ccc2dc")
                    }

                    ColumnLayout {
                        spacing: 2
                        Text {
                            text: "Comece por Aqui"
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 18
                            font.weight: Font.DemiBold
                            color: root.getToken("onSurface", "#e6e1e1")
                        }
                        Text {
                            text: "Aplicativos essenciais recomendados após instalar o Redshift OS."
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 11
                            color: root.getToken("onSurfaceVariant", "#cbc5ca")
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        implicitWidth: verMaisStartRow.implicitWidth + 16
                        height: 30
                        radius: root.getToken("radiusFull", 9999)
                        color: verMaisStartMouse.containsMouse ? root.getToken("surfaceContainerHigh", "#2b2a2a") : "transparent"

                        RowLayout {
                            id: verMaisStartRow
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                text: "Ver mais"
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
                            id: verMaisStartMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.triggerSectionExplore("getting_started")
                        }
                    }
                }

                ListView {
                    id: startListView
                    Layout.fillWidth: true
                    implicitHeight: 204
                    orientation: ListView.Horizontal
                    spacing: 14
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    WheelHandler {
                        orientation: Qt.Horizontal
                        onWheel: (event) => {
                            startListView.contentX = Math.max(0, Math.min(startListView.contentWidth - startListView.width, startListView.contentX - event.angleDelta.y));
                        }
                    }

                    model: (root.storeBridge && root.storeBridge.gettingStartedModel) ?
                           root.storeBridge.gettingStartedModel :
                           (root.storeBridge ? root.storeBridge.featuredModel : null)

                    delegate: PackageCard {
                        width: 320
                        height: 200
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
                        popularityLabel: (model && model.popularityLabel !== undefined) ? model.popularityLabel : ""
                        provenanceLabel: (model && model.provenanceLabel !== undefined) ? model.provenanceLabel : ""
                        isFavorite: (model && model.isFavorite !== undefined) ? model.isFavorite : false

                        onClicked: root.packageSelected(pkgName, repository)
                        onActionTriggered: (action, pName, pRepo) => root.actionRequested(action, pName, pRepo)
                        onFavoriteToggled: (pName) => {
                            if (root.storeBridge && root.storeBridge.toggleFavorite) {
                                root.storeBridge.toggleFavorite(pName);
                            }
                        }
                    }
                }
            }

            // =================================================================
            // 5. Para Desenvolver (developmentSectionModel)
            // =================================================================
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "code"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 22
                        color: root.getToken("primary", "#d0bcff")
                    }

                    ColumnLayout {
                        spacing: 2
                        Text {
                            text: "Para Desenvolver"
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 18
                            font.weight: Font.DemiBold
                            color: root.getToken("onSurface", "#e6e1e1")
                        }
                        Text {
                            text: "Editores, IDEs, compiladores, containers e utilitários de código."
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 11
                            color: root.getToken("onSurfaceVariant", "#cbc5ca")
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        implicitWidth: verMaisDevRow.implicitWidth + 16
                        height: 30
                        radius: root.getToken("radiusFull", 9999)
                        color: verMaisDevMouse.containsMouse ? root.getToken("surfaceContainerHigh", "#2b2a2a") : "transparent"

                        RowLayout {
                            id: verMaisDevRow
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                text: "Ver mais"
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
                            id: verMaisDevMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.triggerSectionExplore("development")
                        }
                    }
                }

                ListView {
                    id: devListView
                    Layout.fillWidth: true
                    implicitHeight: 204
                    orientation: ListView.Horizontal
                    spacing: 14
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    WheelHandler {
                        orientation: Qt.Horizontal
                        onWheel: (event) => {
                            devListView.contentX = Math.max(0, Math.min(devListView.contentWidth - devListView.width, devListView.contentX - event.angleDelta.y));
                        }
                    }

                    model: (root.storeBridge && root.storeBridge.developmentSectionModel) ?
                           root.storeBridge.developmentSectionModel :
                           (root.storeBridge ? root.storeBridge.featuredModel : null)

                    delegate: PackageCard {
                        width: 320
                        height: 200
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
                        popularityLabel: (model && model.popularityLabel !== undefined) ? model.popularityLabel : ""
                        provenanceLabel: (model && model.provenanceLabel !== undefined) ? model.provenanceLabel : ""
                        isFavorite: (model && model.isFavorite !== undefined) ? model.isFavorite : false

                        onClicked: root.packageSelected(pkgName, repository)
                        onActionTriggered: (action, pName, pRepo) => root.actionRequested(action, pName, pRepo)
                        onFavoriteToggled: (pName) => {
                            if (root.storeBridge && root.storeBridge.toggleFavorite) {
                                root.storeBridge.toggleFavorite(pName);
                            }
                        }
                    }
                }
            }

            // =================================================================
            // 6. Jogos e Entretenimento (gamesSectionModel)
            // =================================================================
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "sports_esports"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 22
                        color: root.getToken("warning", "#fbc02d")
                    }

                    ColumnLayout {
                        spacing: 2
                        Text {
                            text: "Jogos e Entretenimento"
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 18
                            font.weight: Font.DemiBold
                            color: root.getToken("onSurface", "#e6e1e1")
                        }
                        Text {
                            text: "Launchers, jogos nativos, compatibilidade Proton/Wine e performance."
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 11
                            color: root.getToken("onSurfaceVariant", "#cbc5ca")
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        implicitWidth: verMaisGamesRow.implicitWidth + 16
                        height: 30
                        radius: root.getToken("radiusFull", 9999)
                        color: verMaisGamesMouse.containsMouse ? root.getToken("surfaceContainerHigh", "#2b2a2a") : "transparent"

                        RowLayout {
                            id: verMaisGamesRow
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                text: "Ver mais"
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
                            id: verMaisGamesMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.triggerSectionExplore("games")
                        }
                    }
                }

                ListView {
                    id: gamesListView
                    Layout.fillWidth: true
                    implicitHeight: 204
                    orientation: ListView.Horizontal
                    spacing: 14
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    WheelHandler {
                        orientation: Qt.Horizontal
                        onWheel: (event) => {
                            gamesListView.contentX = Math.max(0, Math.min(gamesListView.contentWidth - gamesListView.width, gamesListView.contentX - event.angleDelta.y));
                        }
                    }

                    model: (root.storeBridge && root.storeBridge.gamesSectionModel) ?
                           root.storeBridge.gamesSectionModel :
                           (root.storeBridge ? root.storeBridge.featuredModel : null)

                    delegate: PackageCard {
                        width: 320
                        height: 200
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
                        popularityLabel: (model && model.popularityLabel !== undefined) ? model.popularityLabel : ""
                        provenanceLabel: (model && model.provenanceLabel !== undefined) ? model.provenanceLabel : ""
                        isFavorite: (model && model.isFavorite !== undefined) ? model.isFavorite : false

                        onClicked: root.packageSelected(pkgName, repository)
                        onActionTriggered: (action, pName, pRepo) => root.actionRequested(action, pName, pRepo)
                        onFavoriteToggled: (pName) => {
                            if (root.storeBridge && root.storeBridge.toggleFavorite) {
                                root.storeBridge.toggleFavorite(pName);
                            }
                        }
                    }
                }
            }

            // =================================================================
            // 7. Criação e Design (designSectionModel)
            // =================================================================
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "palette"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 22
                        color: root.getToken("tertiary", "#efb8c8")
                    }

                    ColumnLayout {
                        spacing: 2
                        Text {
                            text: "Criação e Design"
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 18
                            font.weight: Font.DemiBold
                            color: root.getToken("onSurface", "#e6e1e1")
                        }
                        Text {
                            text: "Edição de imagem, vídeo, modelagem 3D, ilustração vetorial e áudio."
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 11
                            color: root.getToken("onSurfaceVariant", "#cbc5ca")
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        implicitWidth: verMaisDesignRow.implicitWidth + 16
                        height: 30
                        radius: root.getToken("radiusFull", 9999)
                        color: verMaisDesignMouse.containsMouse ? root.getToken("surfaceContainerHigh", "#2b2a2a") : "transparent"

                        RowLayout {
                            id: verMaisDesignRow
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                text: "Ver mais"
                                font.family: root.getToken("fontFamily", "Google Sans Flex")
                                font.pixelSize: 12
                                font.weight: Font.Medium
                                color: root.getToken("tertiary", "#efb8c8")
                            }

                            Text {
                                text: "arrow_forward"
                                font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                                font.pixelSize: 15
                                color: root.getToken("tertiary", "#efb8c8")
                            }
                        }

                        MouseArea {
                            id: verMaisDesignMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.triggerSectionExplore("design")
                        }
                    }
                }

                ListView {
                    id: designListView
                    Layout.fillWidth: true
                    implicitHeight: 204
                    orientation: ListView.Horizontal
                    spacing: 14
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    WheelHandler {
                        orientation: Qt.Horizontal
                        onWheel: (event) => {
                            designListView.contentX = Math.max(0, Math.min(designListView.contentWidth - designListView.width, designListView.contentX - event.angleDelta.y));
                        }
                    }

                    model: (root.storeBridge && root.storeBridge.designSectionModel) ?
                           root.storeBridge.designSectionModel :
                           (root.storeBridge ? root.storeBridge.featuredModel : null)

                    delegate: PackageCard {
                        width: 320
                        height: 200
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
                        popularityLabel: (model && model.popularityLabel !== undefined) ? model.popularityLabel : ""
                        provenanceLabel: (model && model.provenanceLabel !== undefined) ? model.provenanceLabel : ""
                        isFavorite: (model && model.isFavorite !== undefined) ? model.isFavorite : false

                        onClicked: root.packageSelected(pkgName, repository)
                        onActionTriggered: (action, pName, pRepo) => root.actionRequested(action, pName, pRepo)
                        onFavoriteToggled: (pName) => {
                            if (root.storeBridge && root.storeBridge.toggleFavorite) {
                                root.storeBridge.toggleFavorite(pName);
                            }
                        }
                    }
                }
            }

            // =================================================================
            // 8. Comunicação (communicationSectionModel)
            // =================================================================
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "chat"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 22
                        color: root.getToken("primary", "#d0bcff")
                    }

                    ColumnLayout {
                        spacing: 2
                        Text {
                            text: "Comunicação"
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 18
                            font.weight: Font.DemiBold
                            color: root.getToken("onSurface", "#e6e1e1")
                        }
                        Text {
                            text: "Navegadores web, mensageiros instantâneos e clientes de e-mail."
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 11
                            color: root.getToken("onSurfaceVariant", "#cbc5ca")
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        implicitWidth: verMaisCommsRow.implicitWidth + 16
                        height: 30
                        radius: root.getToken("radiusFull", 9999)
                        color: verMaisCommsMouse.containsMouse ? root.getToken("surfaceContainerHigh", "#2b2a2a") : "transparent"

                        RowLayout {
                            id: verMaisCommsRow
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                text: "Ver mais"
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
                            id: verMaisCommsMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.triggerSectionExplore("communication")
                        }
                    }
                }

                ListView {
                    id: commsListView
                    Layout.fillWidth: true
                    implicitHeight: 204
                    orientation: ListView.Horizontal
                    spacing: 14
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    WheelHandler {
                        orientation: Qt.Horizontal
                        onWheel: (event) => {
                            commsListView.contentX = Math.max(0, Math.min(commsListView.contentWidth - commsListView.width, commsListView.contentX - event.angleDelta.y));
                        }
                    }

                    model: (root.storeBridge && root.storeBridge.communicationSectionModel) ?
                           root.storeBridge.communicationSectionModel :
                           (root.storeBridge ? root.storeBridge.featuredModel : null)

                    delegate: PackageCard {
                        width: 320
                        height: 200
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
                        popularityLabel: (model && model.popularityLabel !== undefined) ? model.popularityLabel : ""
                        provenanceLabel: (model && model.provenanceLabel !== undefined) ? model.provenanceLabel : ""
                        isFavorite: (model && model.isFavorite !== undefined) ? model.isFavorite : false

                        onClicked: root.packageSelected(pkgName, repository)
                        onActionTriggered: (action, pName, pRepo) => root.actionRequested(action, pName, pRepo)
                        onFavoriteToggled: (pName) => {
                            if (root.storeBridge && root.storeBridge.toggleFavorite) {
                                root.storeBridge.toggleFavorite(pName);
                            }
                        }
                    }
                }
            }
        }
    }
}
