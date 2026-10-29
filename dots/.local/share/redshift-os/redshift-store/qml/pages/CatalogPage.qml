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

    // Sub-coleção ativa de descoberta AUR ("all", "popular", "curated", "community", "dev", "games", "productivity")
    property string activeAurSubCollection: "all"

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
    readonly property bool isIndexing: root.storeBridge && root.storeBridge.isIndexingCatalog !== undefined ?
                                       root.storeBridge.isIndexingCatalog : false
    readonly property int resultCount: (activeModel && activeModel.count !== undefined) ? activeModel.count : 0
    readonly property int totalCount: (root.storeBridge && root.storeBridge.catalogTotalCount !== undefined) ?
                                       root.storeBridge.catalogTotalCount : resultCount
    readonly property bool canLoadMore: root.storeBridge && root.storeBridge.canLoadMoreCatalog !== undefined ?
                                        root.storeBridge.canLoadMoreCatalog : false
    readonly property string currentSource: (root.storeBridge && root.storeBridge.activeSourceFilter) ?
                                            root.storeBridge.activeSourceFilter : "all"
    readonly property string currentQuery: (root.storeBridge && root.storeBridge.searchQuery) ?
                                           root.storeBridge.searchQuery : ""
    readonly property string currentCategory: (root.storeBridge && root.storeBridge.activeCategory) ?
                                              root.storeBridge.activeCategory : "all"
    readonly property string currentInstalledFilter: (root.storeBridge && root.storeBridge.activeInstalledFilter) ?
                                                     root.storeBridge.activeInstalledFilter : "all"
    readonly property string currentSortBy: (root.storeBridge && root.storeBridge.activeSortBy) ?
                                            root.storeBridge.activeSortBy : "relevance"
    readonly property bool includeSysPackages: root.storeBridge && root.storeBridge.includeSystemPackages !== undefined ?
                                               root.storeBridge.includeSystemPackages : false

    readonly property string catalogStatus: {
        if (root.storeBridge && root.storeBridge.catalogStatus) {
            return root.storeBridge.catalogStatus;
        }
        if (root.isBusy || root.isIndexing) return "loading";
        if (root.resultCount === 0) {
            if (root.currentCategory !== "all") return "empty_category";
            return "no_results";
        }
        return "ready";
    }

    readonly property string catalogStatusMessage: (root.storeBridge && root.storeBridge.catalogStatusMessage) ?
                                                   root.storeBridge.catalogStatusMessage : ""

    // Modelo dinâmico para a grade baseado na sub-coleção AUR quando aplicável
    readonly property var activeModel: {
        if (!root.storeBridge) return null;
        if (root.currentSource === "aur" && root.currentQuery.length === 0) {
            switch (root.activeAurSubCollection) {
                case "popular":
                    return root.storeBridge.aurPopularModel || root.storeBridge.catalogModel;
                case "curated":
                    return root.storeBridge.aurCuratedModel || root.storeBridge.catalogModel;
                case "community":
                    return root.storeBridge.aurCommunityModel || root.storeBridge.catalogModel;
                case "dev":
                    return root.storeBridge.aurDevModel || root.storeBridge.catalogModel;
                case "games":
                    return root.storeBridge.aurGamesModel || root.storeBridge.catalogModel;
                case "productivity":
                    return root.storeBridge.aurProductivityModel || root.storeBridge.catalogModel;
                default:
                    return root.storeBridge.catalogModel;
            }
        }
        return root.storeBridge.catalogModel;
    }

    color: getToken("surface", "#141313")

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // =====================================================================
        // 1. Cabeçalho do Catálogo
        // =====================================================================
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: root.currentQuery.length > 0 ?
                        ("Resultados para \"" + root.currentQuery + "\"") :
                        (root.currentSource === "aur" ? "Descoberta AUR da Comunidade" : "Explorar Catálogo")
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
                            let countLabel = root.totalCount > root.resultCount ?
                                (root.resultCount + " de " + root.totalCount + " pacotes") :
                                (root.resultCount + " pacote(s)");
                            return countLabel + " • " + srcName + " • " + catName;
                        }
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 12
                        color: root.getToken("onSurfaceVariant", "#cbc5ca")
                    }

                    // Indicador de busca ou indexação ativa
                    Rectangle {
                        visible: root.isBusy || root.isIndexing
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
                                running: root.isBusy || root.isIndexing
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

        // =====================================================================
        // 2. Barra de Categorias Horizontal
        // =====================================================================
        CategoryChipBar {
            Layout.fillWidth: true
            theme: root.theme
            selectedCategory: root.currentCategory
            onCategorySelected: (catId) => root.categorySelected(catId)
        }

        // =====================================================================
        // 3. Barra de Filtros Combináveis (Instalação + Ordenação + Pacotes Sistema)
        // =====================================================================
        Flickable {
            id: secondaryFiltersFlickable
            Layout.fillWidth: true
            implicitHeight: 38
            contentWidth: secondaryFiltersRow.implicitWidth + 8
            contentHeight: height
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            WheelHandler {
                orientation: Qt.Horizontal
                onWheel: (event) => {
                    secondaryFiltersFlickable.contentX = Math.max(0, Math.min(secondaryFiltersFlickable.contentWidth - secondaryFiltersFlickable.width, secondaryFiltersFlickable.contentX - event.angleDelta.y));
                }
            }

            RowLayout {
                id: secondaryFiltersRow
                height: parent.height
                spacing: 8

                // --- Grupo 1: Filtro de Instalação ---
                RowLayout {
                    spacing: 4

                    Repeater {
                        model: [
                            { id: "all", label: "Todos" },
                            { id: "not_installed", label: "Não instalados" },
                            { id: "installed", label: "Instalados" }
                        ]

                        delegate: Rectangle {
                            id: instChip
                            required property var modelData
                            readonly property bool isSelected: root.currentInstalledFilter === modelData.id
                            readonly property bool isHovered: instChipMouse.containsMouse

                            implicitWidth: instChipContent.implicitWidth + 18
                            height: 30
                            radius: root.getToken("radiusFull", 9999)

                            color: isSelected ?
                                root.getToken("secondaryContainer", "#4a4458") :
                                (isHovered ? root.getToken("surfaceContainerHigh", "#2b2a2a") : root.getToken("surfaceContainer", "#201f20"))

                            border.width: 1
                            border.color: isSelected ? root.getToken("secondary", "#ccc2dc") : root.getToken("outlineVariant", "#49454f")

                            RowLayout {
                                id: instChipContent
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    text: instChip.modelData.label
                                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                                    font.pixelSize: 11
                                    font.weight: instChip.isSelected ? Font.Medium : Font.Normal
                                    color: instChip.isSelected ? root.getToken("onSecondaryContainer", "#e8def8") : root.getToken("onSurfaceVariant", "#cbc5ca")
                                }
                            }

                            MouseArea {
                                id: instChipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.storeBridge && root.storeBridge.setInstalledFilter) {
                                        root.storeBridge.setInstalledFilter(instChip.modelData.id);
                                    }
                                }
                            }
                        }
                    }
                }

                // Separador vertical sutil
                Rectangle {
                    width: 1
                    height: 20
                    color: root.getToken("outlineVariant", "#49454f")
                    opacity: 0.5
                }

                // --- Grupo 2: Ordenação ---
                RowLayout {
                    spacing: 4

                    Repeater {
                        model: [
                            { id: "relevance", label: "Relevância", icon: "sort" },
                            { id: "popularity", label: "Popularidade", icon: "trending_up" },
                            { id: "name", label: "Nome (A-Z)", icon: "sort_by_alpha" },
                            { id: "recent", label: "Recentes", icon: "schedule" }
                        ]

                        delegate: Rectangle {
                            id: sortChip
                            required property var modelData
                            readonly property bool isSelected: root.currentSortBy === modelData.id
                            readonly property bool isHovered: sortChipMouse.containsMouse

                            implicitWidth: sortChipContent.implicitWidth + 16
                            height: 30
                            radius: root.getToken("radiusFull", 9999)

                            color: isSelected ?
                                root.getToken("primaryContainer", "#4f378b") :
                                (isHovered ? root.getToken("surfaceContainerHigh", "#2b2a2a") : root.getToken("surfaceContainer", "#201f20"))

                            border.width: 1
                            border.color: isSelected ? root.getToken("primary", "#d0bcff") : root.getToken("outlineVariant", "#49454f")

                            RowLayout {
                                id: sortChipContent
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    text: sortChip.modelData.icon
                                    font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                                    font.pixelSize: 13
                                    color: sortChip.isSelected ? root.getToken("onPrimaryContainer", "#eaddff") : root.getToken("onSurfaceVariant", "#cbc5ca")
                                }

                                Text {
                                    text: sortChip.modelData.label
                                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                                    font.pixelSize: 11
                                    font.weight: sortChip.isSelected ? Font.Medium : Font.Normal
                                    color: sortChip.isSelected ? root.getToken("onPrimaryContainer", "#eaddff") : root.getToken("onSurfaceVariant", "#cbc5ca")
                                }
                            }

                            MouseArea {
                                id: sortChipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.storeBridge && root.storeBridge.setSortBy) {
                                        root.storeBridge.setSortBy(sortChip.modelData.id);
                                    }
                                }
                            }
                        }
                    }
                }

                // Separador vertical sutil
                Rectangle {
                    width: 1
                    height: 20
                    color: root.getToken("outlineVariant", "#49454f")
                    opacity: 0.5
                }

                // --- Grupo 3: Toggle Pacotes de Sistema / Bibliotecas ---
                Rectangle {
                    id: sysPackChip
                    readonly property bool isActive: root.includeSysPackages
                    readonly property bool isHovered: sysPackMouse.containsMouse

                    implicitWidth: sysPackContent.implicitWidth + 18
                    height: 30
                    radius: root.getToken("radiusFull", 9999)

                    color: isActive ?
                        root.getToken("tertiaryContainer", "#633b48") :
                        (isHovered ? root.getToken("surfaceContainerHigh", "#2b2a2a") : root.getToken("surfaceContainer", "#201f20"))

                    border.width: 1
                    border.color: isActive ? root.getToken("tertiary", "#efb8c8") : root.getToken("outlineVariant", "#49454f")

                    RowLayout {
                        id: sysPackContent
                        anchors.centerIn: parent
                        spacing: 5

                        Text {
                            text: sysPackChip.isActive ? "check_box" : "check_box_outline_blank"
                            font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                            font.pixelSize: 15
                            color: sysPackChip.isActive ? root.getToken("onTertiaryContainer", "#ffd8e4") : root.getToken("onSurfaceVariant", "#cbc5ca")
                        }

                        Text {
                            text: "Incluir bibliotecas/sistema"
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 11
                            font.weight: sysPackChip.isActive ? Font.Medium : Font.Normal
                            color: sysPackChip.isActive ? root.getToken("onTertiaryContainer", "#ffd8e4") : root.getToken("onSurfaceVariant", "#cbc5ca")
                        }
                    }

                    MouseArea {
                        id: sysPackMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.storeBridge && root.storeBridge.setIncludeSystemPackages) {
                                root.storeBridge.setIncludeSystemPackages(!sysPackChip.isActive);
                            }
                        }
                    }
                }
            }
        }

        // =====================================================================
        // 4. Banner de Descoberta e Segurança do AUR (Seção 4)
        // Exibido quando na aba AUR e sem pesquisa ativa
        // =====================================================================
        Rectangle {
            visible: root.currentSource === "aur" && root.currentQuery.length === 0
            Layout.fillWidth: true
            radius: root.getToken("radiusNormal", 14)
            color: root.getToken("tertiaryContainer", "#633b48")
            border.width: 1
            border.color: root.getToken("tertiary", "#efb8c8")
            implicitHeight: aurDiscoveryCol.implicitHeight + 20

            ColumnLayout {
                id: aurDiscoveryCol
                anchors.fill: parent
                anchors.margins: 12
                spacing: 8

                RowLayout {
                    spacing: 8
                    Text {
                        text: "shield"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 18
                        color: root.getToken("tertiary", "#efb8c8")
                    }
                    Text {
                        text: "Descoberta Comunitária AUR — Transparência & Segurança"
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        color: root.getToken("onTertiaryContainer", "#ffd8e4")
                    }
                }

                Text {
                    text: "Métricas obtidas da API oficial AUR RPC v5 (Votos e Popularidade atual) sobre o universo de pacotes verificados pela curadoria Redshift OS. Popularidade não equivale a auditoria de segurança: sempre inspecione o PKGBUILD antes de instalar."
                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                    font.pixelSize: 11
                    color: root.getToken("onTertiaryContainer", "#ffd8e4")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    lineHeight: 1.25
                }

                // Abas de sub-seções de descoberta AUR
                RowLayout {
                    spacing: 6

                    Repeater {
                        model: [
                            { id: "all", label: "Catálogo Completo AUR" },
                            { id: "popular", label: "Populares no AUR" },
                            { id: "curated", label: "Recomendados Redshift" },
                            { id: "community", label: "Comunidade" },
                            { id: "dev", label: "Desenvolvimento" },
                            { id: "games", label: "Jogos & Launchers" },
                            { id: "productivity", label: "Produtividade" }
                        ]

                        delegate: Rectangle {
                            id: aurTabChip
                            required property var modelData
                            readonly property bool isSelected: root.activeAurSubCollection === modelData.id
                            readonly property bool isHovered: aurTabMouse.containsMouse

                            implicitWidth: aurTabRow.implicitWidth + 14
                            height: 26
                            radius: root.getToken("radiusFull", 9999)
                            color: isSelected ?
                                root.getToken("tertiary", "#efb8c8") :
                                (isHovered ? root.getToken("surfaceContainerHighest", "#363435") : root.getToken("surfaceContainer", "#201f20"))

                            RowLayout {
                                id: aurTabRow
                                anchors.centerIn: parent
                                Text {
                                    text: aurTabChip.modelData.label
                                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                                    font.pixelSize: 10
                                    font.weight: aurTabChip.isSelected ? Font.Bold : Font.Normal
                                    color: aurTabChip.isSelected ? root.getToken("onTertiary", "#492532") : root.getToken("onSurface", "#e6e1e1")
                                }
                            }

                            MouseArea {
                                id: aurTabMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.activeAurSubCollection = aurTabChip.modelData.id
                            }
                        }
                    }
                }
            }
        }

        // Divisor sutil
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: root.getToken("outlineVariant", "#49454f")
            opacity: 0.25
        }

        // =====================================================================
        // 5. Área de Conteúdo: Grade de Resultados ou Estados Vazios / Carregamento
        // =====================================================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Grade de Pacotes
            GridView {
                id: catalogGridView
                anchors.fill: parent
                clip: true
                readonly property int columns: Math.max(1, Math.floor(width / 310))
                cellWidth: Math.floor(width / columns)
                cellHeight: 212
                boundsBehavior: Flickable.StopAtBounds
                visible: !root.isBusy && !root.isIndexing && root.resultCount > 0

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    active: catalogGridView.moving || catalogGridView.flicking
                }

                model: root.activeModel

                // Paginação automática ao atingir fim da rolagem
                onAtYEndChanged: {
                    if (atYEnd && root.canLoadMore && root.storeBridge && root.storeBridge.loadMoreCatalog) {
                        root.storeBridge.loadMoreCatalog();
                    }
                }

                delegate: Item {
                    width: catalogGridView.cellWidth
                    height: catalogGridView.cellHeight

                    PackageCard {
                        anchors.centerIn: parent
                        width: catalogGridView.cellWidth - 12
                        height: 200
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

                // Botão de Paginação Integrado ao Rodapé do Grid
                footer: Item {
                    width: catalogGridView.width
                    height: root.canLoadMore ? 64 : 16
                    visible: !root.isBusy && !root.isIndexing && root.resultCount > 0

                    Rectangle {
                        visible: root.canLoadMore
                        anchors.centerIn: parent
                        implicitWidth: loadMoreRow.implicitWidth + 28
                        height: 38
                        radius: root.getToken("radiusFull", 9999)
                        color: loadMoreMouse.containsMouse ? root.getToken("primary", "#d0bcff") : root.getToken("primaryContainer", "#4f378b")
                        border.width: 1
                        border.color: root.getToken("primary", "#d0bcff")

                        RowLayout {
                            id: loadMoreRow
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                text: "expand_more"
                                font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                                font.pixelSize: 18
                                color: loadMoreMouse.containsMouse ? root.getToken("onPrimary", "#381e72") : root.getToken("onPrimaryContainer", "#eaddff")
                            }

                            Text {
                                text: "Carregar mais aplicativos (mostrando " + root.resultCount + " de " + root.totalCount + ")"
                                font.family: root.getToken("fontFamily", "Google Sans Flex")
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: loadMoreMouse.containsMouse ? root.getToken("onPrimary", "#381e72") : root.getToken("onPrimaryContainer", "#eaddff")
                            }
                        }

                        MouseArea {
                            id: loadMoreMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.storeBridge && root.storeBridge.loadMoreCatalog) {
                                    root.storeBridge.loadMoreCatalog();
                                }
                            }
                        }
                    }
                }
            }

            // =================================================================
            // 6. Estados Diferenciados (Loading, Network Error, Unsynced, etc.)
            // =================================================================

            // 6.1. Estado de Carregamento / Indexação
            ColumnLayout {
                anchors.centerIn: parent
                visible: root.isBusy || root.isIndexing || root.catalogStatus === "loading"
                spacing: 12

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "progress_activity"
                    font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                    font.pixelSize: 42
                    color: root.getToken("primary", "#d0bcff")

                    RotationAnimation on rotation {
                        running: root.isBusy || root.isIndexing || root.catalogStatus === "loading"
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 1100
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.isIndexing ? "Indexando catálogo dos repositórios..." : "Pesquisando e atualizando catálogo..."
                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                    font.pixelSize: 14
                    color: root.getToken("onSurface", "#e6e1e1")
                }

                Text {
                    visible: root.catalogStatusMessage.length > 0
                    Layout.alignment: Qt.AlignHCenter
                    text: root.catalogStatusMessage
                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                    font.pixelSize: 12
                    color: root.getToken("onSurfaceVariant", "#cbc5ca")
                }
            }

            // 6.2. Estado: Falha na Conexão de Rede (network_error)
            ColumnLayout {
                anchors.centerIn: parent
                visible: !root.isBusy && !root.isIndexing && root.catalogStatus === "network_error"
                spacing: 14
                width: 440

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 72
                    height: 72
                    radius: 36
                    color: root.getToken("errorContainer", "#8c1d18")

                    Text {
                        anchors.centerIn: parent
                        text: "cloud_off"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 36
                        color: root.getToken("error", "#f2b8b5")
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Falha na conexão de rede"
                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                    color: root.getToken("onSurface", "#e6e1e1")
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.catalogStatusMessage.length > 0 ?
                        root.catalogStatusMessage :
                        "Metadados remotos (AUR / pkgstats) estão indisponíveis no momento. O catálogo do sistema local está operando com cache."
                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                    font.pixelSize: 12
                    color: root.getToken("onSurfaceVariant", "#cbc5ca")
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: retryRow.implicitWidth + 24
                    height: 36
                    radius: root.getToken("radiusFull", 9999)
                    color: retryMouse.containsMouse ? root.getToken("primary", "#d0bcff") : root.getToken("primaryContainer", "#4f378b")

                    RowLayout {
                        id: retryRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text { text: "refresh"; font.family: root.getToken("iconFontFamily", "Material Symbols Rounded"); font.pixelSize: 16; color: retryMouse.containsMouse ? root.getToken("onPrimary", "#381e72") : root.getToken("onPrimaryContainer", "#eaddff") }
                        Text { text: "Tentar novamente"; font.family: root.getToken("fontFamily", "Google Sans Flex"); font.pixelSize: 12; font.weight: Font.DemiBold; color: retryMouse.containsMouse ? root.getToken("onPrimary", "#381e72") : root.getToken("onPrimaryContainer", "#eaddff") }
                    }

                    MouseArea {
                        id: retryMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.storeBridge && root.storeBridge.refreshCatalog) {
                                root.storeBridge.refreshCatalog();
                            }
                        }
                    }
                }
            }

            // 6.3. Estado: Repositórios Não Sincronizados (unsynced_repos)
            ColumnLayout {
                anchors.centerIn: parent
                visible: !root.isBusy && !root.isIndexing && root.catalogStatus === "unsynced_repos"
                spacing: 14
                width: 440

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 72
                    height: 72
                    radius: 36
                    color: root.getToken("warningContainer", "#594800")

                    Text {
                        anchors.centerIn: parent
                        text: "sync_problem"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 36
                        color: root.getToken("warning", "#fbc02d")
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Repositórios sem metadados sincronizados"
                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                    color: root.getToken("onSurface", "#e6e1e1")
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Os bancos de dados locais do pacman precisam ser sincronizados com os espelhos oficiais do Arch Linux (yay -Syu)."
                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                    font.pixelSize: 12
                    color: root.getToken("onSurfaceVariant", "#cbc5ca")
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }

            // 6.4. Estado: Fonte de Pacotes Indisponível (source_unavailable)
            ColumnLayout {
                anchors.centerIn: parent
                visible: !root.isBusy && !root.isIndexing && root.catalogStatus === "source_unavailable"
                spacing: 14
                width: 440

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 72
                    height: 72
                    radius: 36
                    color: root.getToken("surfaceContainerHighest", "#363435")

                    Text {
                        anchors.centerIn: parent
                        text: "dns"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 36
                        color: root.getToken("outline", "#938f99")
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Fonte de pacotes indisponível"
                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                    color: root.getToken("onSurface", "#e6e1e1")
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.catalogStatusMessage.length > 0 ? root.catalogStatusMessage : "A fonte de pacotes requisitada não respondeu ou não está habilitada no sistema."
                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                    font.pixelSize: 12
                    color: root.getToken("onSurfaceVariant", "#cbc5ca")
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }

            // 6.5. Estado: Categoria Vazia (empty_category)
            ColumnLayout {
                anchors.centerIn: parent
                visible: !root.isBusy && !root.isIndexing && (root.catalogStatus === "empty_category" || (root.resultCount === 0 && root.currentCategory !== "all"))
                spacing: 14
                width: 440

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 72
                    height: 72
                    radius: 36
                    color: root.getToken("surfaceContainerHighest", "#363435")

                    Text {
                        anchors.centerIn: parent
                        text: "category"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 36
                        color: root.getToken("outline", "#938f99")
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Nenhum aplicativo nesta categoria com os filtros atuais"
                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    color: root.getToken("onSurface", "#e6e1e1")
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Não foram encontrados aplicativos visíveis nesta categoria. Você pode limpar os filtros ou incluir bibliotecas e componentes do sistema."
                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                    font.pixelSize: 12
                    color: root.getToken("onSurfaceVariant", "#cbc5ca")
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8

                    Rectangle {
                        implicitWidth: clearCatRow.implicitWidth + 18
                        height: 34
                        radius: root.getToken("radiusFull", 9999)
                        color: clearCatMouse.containsMouse ? root.getToken("surfaceContainerHighest", "#363435") : root.getToken("surfaceContainer", "#201f20")
                        border.width: 1
                        border.color: root.getToken("outlineVariant", "#49454f")

                        RowLayout {
                            id: clearCatRow
                            anchors.centerIn: parent
                            spacing: 4
                            Text { text: "apps"; font.family: root.getToken("iconFontFamily", "Material Symbols Rounded"); font.pixelSize: 15; color: root.getToken("onSurface", "#e6e1e1") }
                            Text { text: "Todas as categorias"; font.family: root.getToken("fontFamily", "Google Sans Flex"); font.pixelSize: 11; color: root.getToken("onSurface", "#e6e1e1") }
                        }

                        MouseArea {
                            id: clearCatMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.categorySelected("all")
                        }
                    }

                    Rectangle {
                        implicitWidth: inclSysRow.implicitWidth + 18
                        height: 34
                        radius: root.getToken("radiusFull", 9999)
                        color: inclSysMouse.containsMouse ? root.getToken("tertiary", "#efb8c8") : root.getToken("tertiaryContainer", "#633b48")

                        RowLayout {
                            id: inclSysRow
                            anchors.centerIn: parent
                            spacing: 4
                            Text { text: "memory"; font.family: root.getToken("iconFontFamily", "Material Symbols Rounded"); font.pixelSize: 15; color: inclSysMouse.containsMouse ? root.getToken("onTertiary", "#492532") : root.getToken("onTertiaryContainer", "#ffd8e4") }
                            Text { text: "Incluir bibliotecas"; font.family: root.getToken("fontFamily", "Google Sans Flex"); font.pixelSize: 11; font.weight: Font.DemiBold; color: inclSysMouse.containsMouse ? root.getToken("onTertiary", "#492532") : root.getToken("onTertiaryContainer", "#ffd8e4") }
                        }

                        MouseArea {
                            id: inclSysMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.storeBridge && root.storeBridge.setIncludeSystemPackages) {
                                    root.storeBridge.setIncludeSystemPackages(true);
                                }
                            }
                        }
                    }
                }
            }

            // 6.6. Estado Vazio Geral: Nenhum resultado (no_results)
            ColumnLayout {
                anchors.centerIn: parent
                visible: !root.isBusy && !root.isIndexing && root.resultCount === 0 && root.catalogStatus === "no_results" && root.currentCategory === "all"
                spacing: 14
                width: 440

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
                        "Nenhum pacote corresponde aos filtros de busca e ordenação atuais."
                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                    font.pixelSize: 12
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
