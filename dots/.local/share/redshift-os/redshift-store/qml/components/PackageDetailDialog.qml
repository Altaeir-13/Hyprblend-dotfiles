import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Item {
    id: root

    // --- Contratos de Propriedades e Sinais ---
    property bool isOpen: false
    property var pkgData: null
    property var theme: null
    property string pkgbuildText: ""
    property bool isBusy: false

    signal closed()
    signal actionRequested(string action, string pkgName, string repository)
    signal inspectPkgbuildRequested(string pkgName)

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

    function getCategoryGlyph(cat) {
        switch (cat) {
            case "development": return "code";
            case "games": return "sports_esports";
            case "multimedia": return "movie";
            case "design": return "palette";
            case "internet": return "public";
            case "system": return "memory";
            case "office": return "edit_note";
            case "featured": return "auto_awesome";
            default: return "inventory_2";
        }
    }

    readonly property bool hasPkg: Boolean(root.pkgData && root.pkgData.name)
    readonly property bool isAur: Boolean(root.hasPkg && (root.pkgData.source === "aur" || root.pkgData.repository === "aur"))
    readonly property bool hasScreenshots: Boolean(root.hasPkg && root.pkgData.screenshots && root.pkgData.screenshots.length > 0)
    readonly property bool hasOptDepends: Boolean(root.hasPkg && root.pkgData.optdepends && root.pkgData.optdepends.length > 0)
    property bool pkgbuildExpanded: false

    anchors.fill: parent
    visible: root.isOpen && root.hasPkg
    z: 100

    // Fechar com Escape
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            root.closed();
            event.accepted = true;
        }
    }

    // Fundo Scrim Translúcido
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.65)

        MouseArea {
            anchors.fill: parent
            onClicked: root.closed()
        }
    }

    // Card Centralizado do Diálogo
    Rectangle {
        id: dialogCard
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 800)
        height: Math.min(parent.height - 48, 720)
        radius: root.getToken("radiusLarge", 20)
        color: root.getToken("surfaceContainer", "#201f20")
        border.width: 1
        border.color: root.getToken("outlineVariant", "#49454f")
        clip: true

        // Bloqueia clique para não fechar no corpo do modal
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            // =================================================================
            // 1. Cabeçalho do Modal: Avatar + Nomes + Versões + Botão Fechar
            // =================================================================
            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                // Avatar da Categoria ou Ícone XDG Real
                Rectangle {
                    width: 56
                    height: 56
                    radius: root.getToken("radiusNormal", 14)
                    color: root.isAur ?
                        root.getToken("tertiaryContainer", "#633b48") :
                        root.getToken("primaryContainer", "#4f378b")

                    Image {
                        id: detailIconImage
                        anchors.centerIn: parent
                        width: 36
                        height: 36
                        sourceSize: Qt.size(64, 64)
                        smooth: true
                        mipmap: true
                        visible: status === Image.Ready
                        source: (root.pkgData && root.pkgData.iconName && root.pkgData.iconName.length > 0 && typeof StoreBridge !== "undefined" && StoreBridge && StoreBridge.hasDesktopIcon && StoreBridge.hasDesktopIcon(root.pkgData.iconName)) ? ("image://xdgicon/" + root.pkgData.iconName) : ""
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: detailIconImage.status !== Image.Ready
                        text: root.pkgData ? root.getCategoryGlyph(root.pkgData.category) : "inventory_2"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 30
                        color: root.isAur ?
                            root.getToken("onTertiaryContainer", "#ffd8e4") :
                            root.getToken("onPrimaryContainer", "#eaddff")
                    }
                }

                // Títulos, Repositório e AppID
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: root.hasPkg ? (root.pkgData.displayName || root.pkgData.name || "") : ""
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 18
                            font.weight: Font.Bold
                            color: root.getToken("onSurface", "#e6e1e1")
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        // Badge de repositório
                        Rectangle {
                            implicitWidth: modalRepoText.implicitWidth + 12
                            height: 20
                            radius: root.getToken("radiusSmall", 8)
                            color: root.isAur ?
                                root.getToken("tertiaryContainer", "#633b48") :
                                root.getToken("secondaryContainer", "#4a4458")

                            Text {
                                id: modalRepoText
                                anchors.centerIn: parent
                                text: root.hasPkg ? String(root.pkgData.repository || root.pkgData.source || "").toUpperCase() : ""
                                font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                color: root.isAur ?
                                    root.getToken("onTertiaryContainer", "#ffd8e4") :
                                    root.getToken("onSecondaryContainer", "#e8def8")
                            }
                        }
                    }

                    RowLayout {
                        spacing: 8

                        Text {
                            text: root.hasPkg ? String(root.pkgData.name || "") : ""
                            font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                            font.pixelSize: 12
                            color: root.getToken("onSurfaceVariant", "#cbc5ca")
                        }

                        Text {
                            text: root.hasPkg && root.pkgData.version ? (root.pkgData.version === "available" ? "• disponível" : ("• " + root.pkgData.version)) : ""
                            font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                            font.pixelSize: 12
                            color: root.getToken("primary", "#d0bcff")
                            font.weight: Font.DemiBold
                        }

                        // AppID AppStream (se disponível)
                        Text {
                            visible: Boolean(root.hasPkg && root.pkgData.appId && root.pkgData.appId.length > 0)
                            text: "• " + (root.pkgData && root.pkgData.appId ? root.pkgData.appId : "")
                            font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                            font.pixelSize: 11
                            color: root.getToken("onSurfaceVariant", "#cbc5ca")
                            opacity: 0.75
                            elide: Text.ElideRight
                        }
                    }
                }

                // Botão Fechar Modal
                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    color: closeBtnMouse.containsMouse ?
                        root.getToken("surfaceContainerHighest", "#363435") : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "close"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 20
                        color: root.getToken("onSurfaceVariant", "#cbc5ca")
                    }

                    MouseArea {
                        id: closeBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closed()
                    }
                }
            }

            // =================================================================
            // 2. Barra de Proveniência & Popularidade Confiável
            // =================================================================
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: Boolean(root.hasPkg && ((root.pkgData.provenanceLabel && root.pkgData.provenanceLabel.length > 0) || (root.pkgData.popularityLabel && root.pkgData.popularityLabel.length > 0)))

                // Badge de Proveniência
                Rectangle {
                    visible: Boolean(root.hasPkg && root.pkgData.provenanceLabel && root.pkgData.provenanceLabel.length > 0)
                    implicitWidth: provRow.implicitWidth + 14
                    height: 24
                    radius: root.getToken("radiusFull", 9999)
                    color: root.getToken("surfaceContainerHighest", "#363435")
                    border.width: 1
                    border.color: root.getToken("outlineVariant", "#49454f")

                    RowLayout {
                        id: provRow
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            text: "recommend"
                            font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                            font.pixelSize: 13
                            color: root.getToken("primary", "#d0bcff")
                        }

                        Text {
                            text: root.hasPkg && root.pkgData.provenanceLabel ? root.pkgData.provenanceLabel : ""
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 11
                            color: root.getToken("onSurface", "#e6e1e1")
                        }
                    }
                }

                // Badge de Métrica de Popularidade com Explicação Transparente
                Rectangle {
                    visible: Boolean(root.hasPkg && root.pkgData.popularityLabel && root.pkgData.popularityLabel.length > 0)
                    implicitWidth: popRow.implicitWidth + 14
                    height: 24
                    radius: root.getToken("radiusFull", 9999)
                    color: root.isAur ? root.getToken("tertiaryContainer", "#633b48") : root.getToken("secondaryContainer", "#4a4458")

                    RowLayout {
                        id: popRow
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            text: root.isAur ? "thumb_up" : "analytics"
                            font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                            font.pixelSize: 13
                            color: root.isAur ? root.getToken("onTertiaryContainer", "#ffd8e4") : root.getToken("onSecondaryContainer", "#e8def8")
                        }

                        Text {
                            text: {
                                if (!root.hasPkg || !root.pkgData.popularityLabel) return "";
                                let sourceText = "";
                                if (root.pkgData.popularitySource === "pkgstats") {
                                    sourceText = " (Amostra voluntária Arch Linux pkgstats)";
                                } else if (root.pkgData.popularitySource === "aur_rpc") {
                                    sourceText = " (Votos e Popularidade no AUR RPC)";
                                }
                                return root.pkgData.popularityLabel + sourceText;
                            }
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 11
                            color: root.isAur ? root.getToken("onTertiaryContainer", "#ffd8e4") : root.getToken("onSecondaryContainer", "#e8def8")
                        }
                    }
                }

                Item { Layout.fillWidth: true }
            }

            // =================================================================
            // 3. Barra de Ações Primárias (Instalar, Atualizar Syu, Remover)
            // =================================================================
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                // Badge de Protegido
                Rectangle {
                    visible: Boolean(root.hasPkg && root.pkgData.isProtected === true)
                    implicitWidth: protectedRow.implicitWidth + 16
                    height: 36
                    radius: root.getToken("radiusFull", 9999)
                    color: root.getToken("secondaryContainer", "#4a4458")
                    border.width: 1
                    border.color: root.getToken("primary", "#d0bcff")

                    RowLayout {
                        id: protectedRow
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: "shield"
                            font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                            font.pixelSize: 16
                            color: root.getToken("primary", "#d0bcff")
                        }

                        Text {
                            text: "Componente Crítico Protegido"
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            color: root.getToken("onSecondaryContainer", "#e8def8")
                        }
                    }
                }

                // Botão Instalar Pacote
                Rectangle {
                    visible: Boolean(root.hasPkg && !root.pkgData.installed)
                    implicitWidth: installBtnRow.implicitWidth + 24
                    height: 36
                    radius: root.getToken("radiusFull", 9999)
                    color: instMouse.containsMouse ? root.getToken("primary", "#d0bcff") : root.getToken("primaryContainer", "#4f378b")

                    RowLayout {
                        id: installBtnRow
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: "download"
                            font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                            font.pixelSize: 16
                            color: root.getToken("onPrimaryContainer", "#eaddff")
                        }

                        Text {
                            text: "Instalar Pacote"
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: root.getToken("onPrimaryContainer", "#eaddff")
                        }
                    }

                    MouseArea {
                        id: instMouse
                        anchors.fill: parent
                        hoverEnabled: !root.isBusy
                        cursorShape: root.isBusy ? Qt.ForbiddenCursor : Qt.PointingHandCursor
                        enabled: !root.isBusy
                        onClicked: {
                            if (root.pkgData) {
                                root.actionRequested("install", root.pkgData.name, root.pkgData.repository);
                            }
                        }
                    }
                }

                // Botão Atualizar (Refletindo a política anti-partial upgrade do Arch Linux para oficiais)
                Rectangle {
                    visible: Boolean(root.hasPkg && root.pkgData.installed && root.pkgData.updateAvailable)
                    implicitWidth: updBtnRow.implicitWidth + 24
                    height: 36
                    radius: root.getToken("radiusFull", 9999)
                    color: updMouse.containsMouse ? root.getToken("warning", "#fbc02d") : root.getToken("warningContainer", "#594800")

                    RowLayout {
                        id: updBtnRow
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: "upgrade"
                            font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                            font.pixelSize: 16
                            color: root.getToken("onWarningContainer", "#ffe082")
                        }

                        Text {
                            text: !root.isAur ? "Atualizar Sistema (Syu)" : "Atualizar Pacote AUR"
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: root.getToken("onWarningContainer", "#ffe082")
                        }
                    }

                    MouseArea {
                        id: updMouse
                        anchors.fill: parent
                        hoverEnabled: !root.isBusy
                        cursorShape: root.isBusy ? Qt.ForbiddenCursor : Qt.PointingHandCursor
                        enabled: !root.isBusy
                        onClicked: {
                            if (root.pkgData) {
                                if (!root.isAur) {
                                    confirmUpgradeDialog.openDialog(root.pkgData.name, root.pkgData.repository);
                                } else {
                                    root.actionRequested("update", root.pkgData.name, root.pkgData.repository);
                                }
                            }
                        }
                    }
                }

                // Botão Desinstalar (se instalado e não protegido)
                Rectangle {
                    visible: Boolean(root.hasPkg && root.pkgData.installed && !root.pkgData.isProtected)
                    implicitWidth: rmBtnRow.implicitWidth + 24
                    height: 36
                    radius: root.getToken("radiusFull", 9999)
                    color: rmMouse.containsMouse ? root.getToken("error", "#f2b8b5") : root.getToken("errorContainer", "#8c1d18")

                    RowLayout {
                        id: rmBtnRow
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: "delete"
                            font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                            font.pixelSize: 16
                            color: root.getToken("onErrorContainer", "#f9dedc")
                        }

                        Text {
                            text: "Desinstalar"
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 12
                            font.weight: Font.Bold
                            color: root.getToken("onErrorContainer", "#f9dedc")
                        }
                    }

                    MouseArea {
                        id: rmMouse
                        anchors.fill: parent
                        hoverEnabled: !root.isBusy
                        cursorShape: root.isBusy ? Qt.ForbiddenCursor : Qt.PointingHandCursor
                        enabled: !root.isBusy
                        onClicked: {
                            if (root.pkgData) {
                                root.actionRequested("remove", root.pkgData.name, root.pkgData.repository);
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }
            }

            // Divisor
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: root.getToken("outlineVariant", "#49454f")
                opacity: 0.35
            }

            // =================================================================
            // 4. Conteúdo Rolável dos Detalhes (Screenshots, Sobre, Metadados, Deps)
            // =================================================================
            Flickable {
                id: detailsFlickable
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: detailsColumn.implicitHeight + 24
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    active: detailsFlickable.moving || detailsFlickable.flicking
                }

                ColumnLayout {
                    id: detailsColumn
                    width: detailsFlickable.width - 16
                    spacing: 16

                    // 4.1. Seção de Screenshots AppStream (se existirem URLs reais)
                    ColumnLayout {
                        visible: root.hasScreenshots
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: "Capturas de Tela (AppStream)"
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            color: root.getToken("onSurface", "#e6e1e1")
                        }

                        ListView {
                            id: screenshotList
                            Layout.fillWidth: true
                            implicitHeight: 200
                            orientation: ListView.Horizontal
                            spacing: 12
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            model: (root.pkgData && root.pkgData.screenshots) ? root.pkgData.screenshots : []

                            WheelHandler {
                                orientation: Qt.Horizontal
                                onWheel: (event) => {
                                    screenshotList.contentX = Math.max(0, Math.min(screenshotList.contentWidth - screenshotList.width, screenshotList.contentX - event.angleDelta.y));
                                }
                            }

                            delegate: Rectangle {
                                width: 320
                                height: 190
                                radius: root.getToken("radiusNormal", 14)
                                color: root.getToken("surfaceContainerLowest", "#0f0e0e")
                                border.width: 1
                                border.color: root.getToken("outlineVariant", "#49454f")
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    asynchronous: true
                                    fillMode: Image.PreserveAspectFit
                                    source: modelData
                                    smooth: true
                                }
                            }
                        }
                    }

                    // 4.2. Banner de Segurança do AUR
                    Rectangle {
                        visible: root.isAur
                        Layout.fillWidth: true
                        radius: root.getToken("radiusNormal", 14)
                        color: root.getToken("tertiaryContainer", "#633b48")
                        border.width: 1
                        border.color: root.getToken("tertiary", "#efb8c8")
                        implicitHeight: aurBannerCol.implicitHeight + 24

                        ColumnLayout {
                            id: aurBannerCol
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            RowLayout {
                                spacing: 8
                                Text {
                                    text: "warning"
                                    font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                                    font.pixelSize: 20
                                    color: root.getToken("tertiary", "#efb8c8")
                                }
                                Text {
                                    text: "Pacote do Arch User Repository (AUR)"
                                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                    color: root.getToken("onTertiaryContainer", "#ffd8e4")
                                }
                            }

                            Text {
                                text: "Pacotes do AUR contêm scripts PKGBUILD criados pela comunidade e serão compilados no seu sistema sem privilégios de root. Sempre revise o script antes de compilar."
                                font.family: root.getToken("fontFamily", "Google Sans Flex")
                                font.pixelSize: 11
                                color: root.getToken("onTertiaryContainer", "#ffd8e4")
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            RowLayout {
                                spacing: 14

                                Text {
                                    text: "Mantenedor: " + (root.pkgData && root.pkgData.maintainer ? root.pkgData.maintainer : "Não especificado")
                                    font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                                    font.pixelSize: 11
                                    color: root.getToken("onTertiaryContainer", "#ffd8e4")
                                }

                                Text {
                                    text: "• Votos: " + (root.pkgData && root.pkgData.votes !== undefined ? root.pkgData.votes : 0)
                                    font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                                    font.pixelSize: 11
                                    color: root.getToken("onTertiaryContainer", "#ffd8e4")
                                }

                                Text {
                                    text: "• Popularidade: " + (root.pkgData && root.pkgData.popularity !== undefined ? root.pkgData.popularity.toFixed(2) : "0.0")
                                    font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                                    font.pixelSize: 11
                                    color: root.getToken("onTertiaryContainer", "#ffd8e4")
                                }

                                Item { Layout.fillWidth: true }

                                Rectangle {
                                    implicitWidth: inspectBtnRow.implicitWidth + 16
                                    height: 28
                                    radius: root.getToken("radiusFull", 9999)
                                    color: inspectMouse.containsMouse ?
                                        root.getToken("tertiary", "#efb8c8") :
                                        root.getToken("surfaceContainerHighest", "#363435")

                                    RowLayout {
                                        id: inspectBtnRow
                                        anchors.centerIn: parent
                                        spacing: 4

                                        Text {
                                            text: root.pkgbuildExpanded ? "expand_less" : "code"
                                            font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                                            font.pixelSize: 14
                                            color: inspectMouse.containsMouse ?
                                                root.getToken("onTertiary", "#492532") :
                                                root.getToken("onSurface", "#e6e1e1")
                                        }

                                        Text {
                                            text: root.pkgbuildExpanded ? "Ocultar PKGBUILD" : "Inspecionar PKGBUILD"
                                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                                            font.pixelSize: 11
                                            font.weight: Font.DemiBold
                                            color: inspectMouse.containsMouse ?
                                                root.getToken("onTertiary", "#492532") :
                                                root.getToken("onSurface", "#e6e1e1")
                                        }
                                    }

                                    MouseArea {
                                        id: inspectMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.pkgbuildExpanded = !root.pkgbuildExpanded;
                                            if (root.pkgbuildExpanded && root.pkgData) {
                                                root.inspectPkgbuildRequested(root.pkgData.name);
                                            }
                                        }
                                    }
                                }
                            }

                            // Visualizador Expansível do PKGBUILD
                            Rectangle {
                                visible: root.pkgbuildExpanded
                                Layout.fillWidth: true
                                height: 160
                                radius: root.getToken("radiusSmall", 8)
                                color: root.getToken("surfaceContainerLowest", "#0f0e0e")
                                border.width: 1
                                border.color: root.getToken("outlineVariant", "#49454f")

                                Flickable {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    contentWidth: Math.max(width, pkgbuildTextItem.implicitWidth)
                                    contentHeight: Math.max(height, pkgbuildTextItem.implicitHeight)
                                    clip: true

                                    Text {
                                        id: pkgbuildTextItem
                                        text: root.pkgbuildText.length > 0 ? root.pkgbuildText : "# Carregando PKGBUILD de forma somente-leitura..."
                                        font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                                        font.pixelSize: 11
                                        color: root.getToken("onSurface", "#e6e1e1")
                                    }
                                }
                            }
                        }
                    }

                    // 4.3. Descrição Completa
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "Sobre o Aplicativo"
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                            color: root.getToken("onSurface", "#e6e1e1")
                        }

                        Text {
                            text: root.pkgData ?
                                (root.pkgData.description || root.pkgData.summary || "Nenhuma descrição fornecida.") : ""
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 13
                            color: root.getToken("onSurfaceVariant", "#cbc5ca")
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            lineHeight: 1.3
                        }
                    }

                    // 4.4. Grade de Metadados
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 3
                        columnSpacing: 14
                        rowSpacing: 10

                        // Licença
                        ColumnLayout {
                            spacing: 2
                            Text { text: "Licença"; font.family: root.getToken("fontFamily", "Google Sans Flex"); font.pixelSize: 11; color: root.getToken("onSurfaceVariant", "#cbc5ca") }
                            Text { text: root.pkgData && root.pkgData.license ? root.pkgData.license : "—"; font.family: root.getToken("monoFontFamily", "JetBrains Mono NF"); font.pixelSize: 12; color: root.getToken("onSurface", "#e6e1e1") }
                        }

                        // Tamanho Instalado
                        ColumnLayout {
                            spacing: 2
                            Text { text: "Tamanho Instalado"; font.family: root.getToken("fontFamily", "Google Sans Flex"); font.pixelSize: 11; color: root.getToken("onSurfaceVariant", "#cbc5ca") }
                            Text { text: root.pkgData && root.pkgData.installedSize ? root.pkgData.installedSize : "—"; font.family: root.getToken("monoFontFamily", "JetBrains Mono NF"); font.pixelSize: 12; color: root.getToken("onSurface", "#e6e1e1") }
                        }

                        // Tamanho de Download
                        ColumnLayout {
                            spacing: 2
                            Text { text: "Tamanho de Download"; font.family: root.getToken("fontFamily", "Google Sans Flex"); font.pixelSize: 11; color: root.getToken("onSurfaceVariant", "#cbc5ca") }
                            Text { text: root.pkgData && root.pkgData.downloadSize ? root.pkgData.downloadSize : "—"; font.family: root.getToken("monoFontFamily", "JetBrains Mono NF"); font.pixelSize: 12; color: root.getToken("onSurface", "#e6e1e1") }
                        }

                        // Categoria
                        ColumnLayout {
                            spacing: 2
                            Text { text: "Categoria"; font.family: root.getToken("fontFamily", "Google Sans Flex"); font.pixelSize: 11; color: root.getToken("onSurfaceVariant", "#cbc5ca") }
                            Text { text: root.pkgData && root.pkgData.category ? root.pkgData.category.toUpperCase() : "—"; font.family: root.getToken("monoFontFamily", "JetBrains Mono NF"); font.pixelSize: 12; color: root.getToken("onSurface", "#e6e1e1") }
                        }

                        // URL Upstream
                        ColumnLayout {
                            Layout.columnSpan: 2
                            spacing: 2
                            Text { text: "Página Oficial do Projeto"; font.family: root.getToken("fontFamily", "Google Sans Flex"); font.pixelSize: 11; color: root.getToken("onSurfaceVariant", "#cbc5ca") }
                            Text {
                                text: root.pkgData && root.pkgData.url ? root.pkgData.url : "—"
                                font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                                font.pixelSize: 12
                                color: root.getToken("primary", "#d0bcff")
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }
                    }

                    // 4.5. Seção de Dependências Diretas
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: Boolean(root.hasPkg && root.pkgData.depends && root.pkgData.depends.length > 0)

                        Text {
                            text: "Dependências Diretas"
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: root.getToken("onSurface", "#e6e1e1")
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: root.pkgData && root.pkgData.depends ? root.pkgData.depends : []
                                delegate: Rectangle {
                                    implicitWidth: depLabel.implicitWidth + 12
                                    height: 22
                                    radius: root.getToken("radiusSmall", 8)
                                    color: root.getToken("surfaceContainerHigh", "#2b2a2a")
                                    border.width: 1
                                    border.color: root.getToken("outlineVariant", "#49454f")

                                    Text {
                                        id: depLabel
                                        anchors.centerIn: parent
                                        text: modelData
                                        font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                                        font.pixelSize: 10
                                        color: root.getToken("onSurfaceVariant", "#cbc5ca")
                                    }
                                }
                            }
                        }
                    }

                    // 4.6. Seção de Dependências Opcionais
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: root.hasOptDepends

                        Text {
                            text: "Dependências Opcionais"
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            color: root.getToken("onSurface", "#e6e1e1")
                        }

                        Flow {
                            Layout.fillWidth: true
                            spacing: 6

                            Repeater {
                                model: (root.pkgData && root.pkgData.optdepends) ? root.pkgData.optdepends : []
                                delegate: Rectangle {
                                    implicitWidth: optDepLabel.implicitWidth + 12
                                    height: 22
                                    radius: root.getToken("radiusSmall", 8)
                                    color: root.getToken("surfaceContainer", "#201f20")
                                    border.width: 1
                                    border.color: root.getToken("outlineVariant", "#49454f")

                                    Text {
                                        id: optDepLabel
                                        anchors.centerIn: parent
                                        text: modelData
                                        font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                                        font.pixelSize: 10
                                        color: root.getToken("onSurfaceVariant", "#cbc5ca")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Diálogo Explicativo de Confirmação de Atualização Completa do Sistema
    ConfirmSystemUpgradeDialog {
        id: confirmUpgradeDialog
        theme: root.theme
        onConfirmed: (pkgName, repo) => {
            root.actionRequested("update", pkgName, repo);
        }
    }
}
