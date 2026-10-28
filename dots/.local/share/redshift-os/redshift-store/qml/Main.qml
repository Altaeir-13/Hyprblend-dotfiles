import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "theme"
import "components"
import "pages"

ApplicationWindow {
    id: root

    // --- Dimensões e Título da Janela ---
    width: 1220
    height: 800
    minimumWidth: 920
    minimumHeight: 620
    visible: true
    title: "Redshift Store"

    // --- Instanciação do Tema Material 3 Expressive ---
    Theme {
        id: appTheme
    }

    color: appTheme.surface

    // --- Conexão ao Backend PyQt6 (StoreBridge) ---
    readonly property var store: (typeof StoreBridge !== "undefined") ? StoreBridge : null
    readonly property var themeSvc: (typeof ThemeBridge !== "undefined") ? ThemeBridge : null

    property string currentPage: (typeof InitialPage !== "undefined" && InitialPage) ? InitialPage : "home" // "home" | "catalog" | "installed" | "updates"

    // Função para navegação programática (CLI --page ou atalhos)
    function navigateToPage(pageId) {
        if (pageId === "home" || pageId === "catalog" || pageId === "installed" || pageId === "updates") {
            root.currentPage = pageId;
        }
    }

    // Abertura do modal de detalhes
    function openDetail(pkgName, repository) {
        if (root.store && root.store.selectPackage) {
            root.store.selectPackage(pkgName, repository);
        }
        detailDialog.isOpen = true;
    }

    // Execução de transações de pacotes
    function executeAction(action, pkgName, repository) {
        logDrawer.isOpen = true;
        if (root.store) {
            if (action === "install") {
                root.store.installPackage(pkgName, repository);
            } else if (action === "remove") {
                root.store.removePackage(pkgName);
            } else if (action === "update") {
                root.store.updatePackage(pkgName, repository);
            }
        }
    }

    // Exibição de Toast Messages
    function showToast(level, message) {
        toastItem.level = level;
        toastItem.message = message;
        toastItem.visible = true;
        toastTimer.restart();
    }

    // Conexão reativa com os sinais do StoreBridge
    Connections {
        target: root.store
        ignoreUnknownSignals: true

        function onToastMessage(level, message) {
            root.showToast(level, message);
        }

        function onOperationStateChanged() {
            if (root.store && root.store.isBusy) {
                logDrawer.isOpen = true;
            }
        }
    }

    // --- Layout Principal da Aplicação ---
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // 1. Barra Lateral de Navegação (Navigation Rail estilo Microsoft Store)
        NavigationSidebar {
            id: sidebar
            Layout.fillHeight: true
            theme: appTheme
            currentPage: root.currentPage
            installedCount: root.store ? root.store.installedCount : 0
            updatesCount: root.store ? root.store.updatesCount : 0
            isBusy: root.store ? root.store.isBusy : false
            schemeVariant: appTheme.schemeVariant
            isDark: appTheme.isDark
            frontendMode: appTheme.frontendMode
            activeShellMode: appTheme.activeShellMode

            onPageSelected: (pageId) => root.navigateToPage(pageId)
            onToggleLogsRequested: logDrawer.isOpen = !logDrawer.isOpen
            onThemeToggleRequested: {
                if (root.themeSvc && root.themeSvc.togglePreviewMode) {
                    root.themeSvc.togglePreviewMode();
                } else if (root.store && root.store.togglePreviewMode) {
                    root.store.togglePreviewMode();
                }
            }
            onReloadThemeRequested: {
                if (root.themeSvc) {
                    if (root.themeSvc.reloadPalette) root.themeSvc.reloadPalette();
                    else if (root.themeSvc.reloadTheme) root.themeSvc.reloadTheme();
                } else if (root.store) {
                    if (root.store.reloadPalette) root.store.reloadPalette();
                    else if (root.store.reloadTheme) root.store.reloadTheme();
                }
            }
        }

        // 2. Coluna Principal de Conteúdo
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Barra Superior de Pesquisa e Filtros
            TopSearchBar {
                id: searchBar
                Layout.fillWidth: true
                Layout.margins: 14
                theme: appTheme
                searchText: root.store ? root.store.searchQuery : ""
                sourceFilter: root.store ? root.store.activeSourceFilter : "all"
                isDbLocked: root.store ? root.store.isDbLocked : false
                isBusy: root.store ? root.store.isBusy : false

                onSearchTriggered: (query, srcFilter) => {
                    root.currentPage = "catalog";
                    if (root.store) {
                        root.store.search(query, srcFilter, root.store.activeCategory);
                    }
                }

                onSourceFilterSelected: (srcFilter) => {
                    if (root.store) {
                        root.store.setSourceFilter(srcFilter);
                    }
                }

                onRefreshRequested: {
                    if (root.store) {
                        root.store.refreshCatalog();
                    }
                }
            }

            // Divisor Horizontal Sutil
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: appTheme.outlineVariant
                opacity: 0.35
            }

            // Stack de Páginas
            StackLayout {
                id: pagesStack
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: {
                    switch (root.currentPage) {
                        case "catalog": return 1;
                        case "installed": return 2;
                        case "updates": return 3;
                        default: return 0;
                    }
                }

                // Página 0: HomePage
                HomePage {
                    id: homePage
                    theme: appTheme
                    storeBridge: root.store
                    themeBridge: root.themeSvc

                    onPackageSelected: (pkg, repo) => root.openDetail(pkg, repo)
                    onActionRequested: (action, pkg, repo) => root.executeAction(action, pkg, repo)
                    onExploreRequested: (sourceFilter) => {
                        if (root.store) {
                            root.store.setSourceFilter(sourceFilter);
                        }
                        root.currentPage = "catalog";
                    }
                    onCategorySelected: (catId) => {
                        if (root.store) {
                            root.store.setCategory(catId);
                        }
                        root.currentPage = "catalog";
                    }
                    onNavigateUpdatesRequested: root.currentPage = "updates"
                }

                // Página 1: CatalogPage
                CatalogPage {
                    id: catalogPage
                    theme: appTheme
                    storeBridge: root.store

                    onPackageSelected: (pkg, repo) => root.openDetail(pkg, repo)
                    onActionRequested: (action, pkg, repo) => root.executeAction(action, pkg, repo)
                    onCategorySelected: (catId) => {
                        if (root.store) {
                            root.store.setCategory(catId);
                        }
                    }
                    onSwitchSourceRequested: (targetSource) => {
                        if (root.store) {
                            root.store.setSourceFilter(targetSource);
                        }
                    }
                }

                // Página 2: InstalledPage
                InstalledPage {
                    id: installedPage
                    theme: appTheme
                    storeBridge: root.store

                    onPackageSelected: (pkg, repo) => root.openDetail(pkg, repo)
                    onActionRequested: (action, pkg, repo) => root.executeAction(action, pkg, repo)
                    onExplicitFilterToggled: (explicitOnly) => {
                        if (root.store) {
                            root.store.refreshInstalled(explicitOnly);
                        }
                    }
                    onRefreshInstalledRequested: {
                        if (root.store) {
                            root.store.refreshInstalled(installedPage.explicitOnly);
                        }
                    }
                }

                // Página 3: UpdatesPage
                UpdatesPage {
                    id: updatesPage
                    theme: appTheme
                    storeBridge: root.store

                    onPackageSelected: (pkg, repo) => root.openDetail(pkg, repo)
                    onActionRequested: (action, pkg, repo) => root.executeAction(action, pkg, repo)
                    onCheckUpdatesRequested: {
                        if (root.store) {
                            root.store.checkUpdates();
                        }
                    }
                    onUpdateAllRequested: {
                        logDrawer.isOpen = true;
                        if (root.store) {
                            root.store.updateAll();
                        }
                    }
                }
            }

            // Drawer Deslizante de Operações e Logs em Tempo Real
            OperationsLogDrawer {
                id: logDrawer
                objectName: "logDrawer"
                Layout.fillWidth: true
                theme: appTheme
                isOpen: false
                operationState: root.store ? root.store.operationState : "idle"
                operationStatusText: root.store ? root.store.operationStatusText : ""
                operationProgress: root.store ? root.store.operationProgress : 0
                isBusy: root.store ? root.store.isBusy : false
                logText: root.store ? root.store.logText : ""
                canCancel: root.store ? root.store.canCancel : false
                transactionStage: root.store ? root.store.transactionStage : "idle"
                waitingForInput: root.store ? root.store.waitingForInput : false
                currentPromptText: root.store ? root.store.currentPromptText : ""

                onCancelRequested: {
                    if (root.store) {
                        root.store.cancelCurrentOperation();
                    }
                }
                onClearLogsRequested: {
                    if (root.store) {
                        root.store.clearLogs();
                    }
                }
                onCloseRequested: logDrawer.isOpen = false
                onPromptResponseRequested: (accepted) => {
                    if (root.store && root.store.respondToPrompt) {
                        root.store.respondToPrompt(accepted);
                    }
                }
                onCustomInputSubmitted: (text) => {
                    if (root.store) {
                        if (root.store.sendTransactionInput) {
                            root.store.sendTransactionInput(text);
                        } else if (root.store.sendInput) {
                            root.store.sendInput(text);
                        }
                    }
                }
            }
        }
    }

    // 3. Modal de Detalhes do Pacote (Overlay Dialog)
    PackageDetailDialog {
        id: detailDialog
        theme: appTheme
        isOpen: false
        pkgData: root.store ? root.store.selectedPackage : null
        pkgbuildText: root.store ? root.store.pkgbuildPreview : ""
        isBusy: root.store ? root.store.isBusy : false

        onClosed: detailDialog.isOpen = false
        onActionRequested: (action, pkg, repo) => root.executeAction(action, pkg, repo)
        onInspectPkgbuildRequested: (pkg) => {
            if (root.store) {
                root.store.fetchPkgbuildPreview(pkg);
            }
        }
    }

    // 4. Toast Notification Flutuante
    Rectangle {
        id: toastItem
        visible: false
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 20
        z: 200

        property string level: "info"
        property string message: ""

        implicitWidth: toastContent.implicitWidth + 24
        height: 40
        radius: appTheme.radiusFull

        color: {
            if (level === "success") return appTheme.successContainer;
            if (level === "error") return appTheme.errorContainer;
            if (level === "warning") return appTheme.warningContainer;
            return appTheme.surfaceContainerHighest;
        }

        border.width: 1
        border.color: {
            if (level === "success") return appTheme.success;
            if (level === "error") return appTheme.error;
            if (level === "warning") return appTheme.warning;
            return appTheme.outlineVariant;
        }

        RowLayout {
            id: toastContent
            anchors.centerIn: parent
            spacing: 8

            Text {
                text: {
                    if (toastItem.level === "success") return "check_circle";
                    if (toastItem.level === "error") return "error";
                    if (toastItem.level === "warning") return "warning";
                    return "info";
                }
                font.family: appTheme.iconFontFamily
                font.pixelSize: 18
                color: {
                    if (toastItem.level === "success") return appTheme.success;
                    if (toastItem.level === "error") return appTheme.error;
                    if (toastItem.level === "warning") return appTheme.warning;
                    return appTheme.primary;
                }
            }

            Text {
                text: toastItem.message
                font.family: appTheme.fontFamily
                font.pixelSize: 12
                font.weight: Font.Medium
                color: {
                    if (toastItem.level === "success") return (appTheme.colors && appTheme.colors.onSuccessContainer) ? appTheme.colors.onSuccessContainer : "#d1e9d6";
                    if (toastItem.level === "error") return (appTheme.colors && appTheme.colors.onErrorContainer) ? appTheme.colors.onErrorContainer : "#f9dedc";
                    if (toastItem.level === "warning") return (appTheme.colors && appTheme.colors.onWarningContainer) ? appTheme.colors.onWarningContainer : "#ffe082";
                    return (appTheme.colors && appTheme.colors.onSurface) ? appTheme.colors.onSurface : "#e6e1e1";
                }
            }
        }

        Timer {
            id: toastTimer
            interval: 3500
            repeat: false
            onTriggered: toastItem.visible = false
        }
    }
}
