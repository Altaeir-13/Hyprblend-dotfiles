import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    // --- Contratos de Propriedades e Sinais ---
    property var theme: null
    property string pkgName: ""
    property string displayName: ""
    property string summary: ""
    property string version: ""
    property string installedVersion: ""
    property string repository: "extra"
    property string source: "official" // "official" | "aur"
    property bool installed: false
    property bool updateAvailable: false
    property string category: "utilities"
    property string iconName: ""
    property int votes: 0
    property bool isBusy: false

    signal clicked()
    signal actionTriggered(string action, string pkgName, string repo)

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

    // Mapeamento de glifos Material Symbols por categoria
    function getCategoryGlyph(cat) {
        switch (cat) {
            case "development": return "code";
            case "games": return "sports_esports";
            case "multimedia": return "movie";
            case "internet": return "public";
            case "system": return "memory";
            case "office": return "description";
            case "featured": return "auto_awesome";
            default: return "inventory_2";
        }
    }

    readonly property bool isAur: root.source === "aur" || root.repository === "aur"
    readonly property bool isHovered: cardMouseArea.containsMouse

    implicitWidth: 320
    implicitHeight: 184
    radius: root.getToken("radiusNormal", 14)

    color: isHovered ?
        root.getToken("surfaceContainerHigh", "#2b2a2a") :
        root.getToken("surfaceContainer", "#201f20")

    border.width: isHovered ? 1.5 : 1
    border.color: isHovered ?
        (root.isAur ? root.getToken("tertiary", "#efb8c8") : root.getToken("primary", "#d0bcff")) :
        root.getToken("outlineVariant", "#49454f")

    Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutQuad } }
    Behavior on border.color { ColorAnimation { duration: 180; easing.type: Easing.OutQuad } }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // 1. Linha Superior: Avatar/Ícone + Nomes + Repositório
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Avatar / Emblema da Categoria ou Ícone XDG Real
            Rectangle {
                width: 48
                height: 48
                radius: root.getToken("radiusNormal", 14)
                color: root.isAur ?
                    root.getToken("tertiaryContainer", "#633b48") :
                    root.getToken("primaryContainer", "#4f378b")

                Image {
                    id: pkgIconImage
                    anchors.centerIn: parent
                    width: 30
                    height: 30
                    sourceSize: Qt.size(64, 64)
                    smooth: true
                    mipmap: true
                    visible: status === Image.Ready
                    source: (root.iconName && root.iconName.length > 0 && typeof StoreBridge !== "undefined" && StoreBridge && StoreBridge.hasDesktopIcon(root.iconName)) ? ("image://xdgicon/" + root.iconName) : ""
                }

                Text {
                    anchors.centerIn: parent
                    visible: pkgIconImage.status !== Image.Ready
                    text: root.getCategoryGlyph(root.category)
                    font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                    font.pixelSize: 26
                    color: root.isAur ?
                        root.getToken("onTertiaryContainer", "#ffd8e4") :
                        root.getToken("onPrimaryContainer", "#eaddff")
                }
            }

            // Título e Nome do Pacote
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: root.displayName && root.displayName.length > 0 ? root.displayName : root.pkgName
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        color: root.getToken("onSurface", "#e6e1e1")
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    // Badge de Repositório (core, extra, multilib, aur)
                    Rectangle {
                        implicitWidth: repoText.implicitWidth + 10
                        height: 18
                        radius: root.getToken("radiusSmall", 8)
                        color: root.isAur ?
                            root.getToken("tertiaryContainer", "#633b48") :
                            root.getToken("secondaryContainer", "#4a4458")

                        Text {
                            id: repoText
                            anchors.centerIn: parent
                            text: (root.repository || root.source).toUpperCase()
                            font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            color: root.isAur ?
                                root.getToken("onTertiaryContainer", "#ffd8e4") :
                                root.getToken("onSecondaryContainer", "#e8def8")
                        }
                    }
                }

                RowLayout {
                    spacing: 6

                    Text {
                        text: root.pkgName
                        font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                        font.pixelSize: 11
                        color: root.getToken("onSurfaceVariant", "#cbc5ca")
                        opacity: 0.8
                        elide: Text.ElideRight
                    }

                    Text {
                        text: "• " + root.version
                        font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                        font.pixelSize: 10
                        color: root.getToken("onSurfaceVariant", "#cbc5ca")
                        opacity: 0.65
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // 2. Resumo / Descrição (2 linhas com elide)
        Text {
            Layout.fillWidth: true
            Layout.fillHeight: true
            text: root.summary && root.summary.length > 0 ? root.summary : "Sem resumo disponível."
            font.family: root.getToken("fontFamily", "Google Sans Flex")
            font.pixelSize: 12
            color: root.getToken("onSurfaceVariant", "#cbc5ca")
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            lineHeight: 1.25
        }

        // 3. Rodapé do Card: Votos/Status + Botão de Ação Rápida
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            // Votos AUR se for do AUR
            RowLayout {
                visible: root.isAur
                spacing: 4

                Text {
                    text: "thumb_up"
                    font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                    font.pixelSize: 14
                    color: root.getToken("tertiary", "#efb8c8")
                }

                Text {
                    text: root.votes.toString()
                    font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                    font.pixelSize: 11
                    color: root.getToken("onSurfaceVariant", "#cbc5ca")
                }
            }

            // Badge de Estado: "Instalado" ou "Atualização"
            Rectangle {
                visible: root.installed
                implicitWidth: statusText.implicitWidth + 14
                height: 22
                radius: root.getToken("radiusFull", 9999)
                color: root.updateAvailable ?
                    root.getToken("warningContainer", "#594800") :
                    root.getToken("successContainer", "#374b3e")

                RowLayout {
                    id: statusText
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        text: root.updateAvailable ? "upgrade" : "check_circle"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 13
                        color: root.updateAvailable ?
                            root.getToken("warning", "#fbc02d") :
                            root.getToken("success", "#b5ccba")
                    }

                    Text {
                        text: root.updateAvailable ? "Atualização" : "Instalado"
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        color: root.updateAvailable ?
                            root.getToken("onWarningContainer", "#ffe082") :
                            root.getToken("onSuccessContainer", "#d1e9d6")
                    }
                }
            }

            Item {
                Layout.fillWidth: true
            }

            // Botão Rápido de Ação (Instalar / Atualizar / Remover)
            Rectangle {
                id: actionButton
                implicitWidth: actionRow.implicitWidth + 20
                height: 32
                radius: root.getToken("radiusFull", 9999)

                readonly property bool btnHovered: actionMouseArea.containsMouse
                readonly property string actionType: {
                    if (root.installed) {
                        if (root.updateAvailable) return "update";
                        return btnHovered ? "remove" : "installed";
                    }
                    return "install";
                }

                color: {
                    if (actionType === "update") {
                        return btnHovered ? root.getToken("primary", "#d0bcff") : root.getToken("primaryContainer", "#4f378b");
                    }
                    if (actionType === "remove") {
                        return root.getToken("errorContainer", "#8c1d18");
                    }
                    if (actionType === "installed") {
                        return root.getToken("surfaceContainerHighest", "#363435");
                    }
                    // "install"
                    return btnHovered ? root.getToken("primary", "#d0bcff") : root.getToken("primaryContainer", "#4f378b");
                }

                border.width: 1
                border.color: {
                    if (actionType === "remove") return root.getToken("error", "#f2b8b5");
                    if (actionType === "update") return root.getToken("primary", "#d0bcff");
                    return "transparent";
                }

                Behavior on color { ColorAnimation { duration: 150 } }

                RowLayout {
                    id: actionRow
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        text: {
                            if (actionButton.actionType === "update") return "upgrade";
                            if (actionButton.actionType === "remove") return "delete";
                            if (actionButton.actionType === "installed") return "check";
                            return "download";
                        }
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 15
                        color: {
                            if (actionButton.actionType === "remove") return root.getToken("error", "#f2b8b5");
                            if (actionButton.actionType === "update") return root.getToken("onPrimaryContainer", "#eaddff");
                            if (actionButton.actionType === "installed") return root.getToken("onSurfaceVariant", "#cbc5ca");
                            return root.getToken("onPrimaryContainer", "#eaddff");
                        }
                    }

                    Text {
                        text: {
                            if (actionButton.actionType === "update") return "Atualizar";
                            if (actionButton.actionType === "remove") return "Desinstalar";
                            if (actionButton.actionType === "installed") return "Instalado";
                            return "Instalar";
                        }
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: {
                            if (actionButton.actionType === "remove") return root.getToken("onErrorContainer", "#f9dedc");
                            if (actionButton.actionType === "update") return root.getToken("onPrimaryContainer", "#eaddff");
                            if (actionButton.actionType === "installed") return root.getToken("onSurface", "#e6e1e1");
                            return root.getToken("onPrimaryContainer", "#eaddff");
                        }
                    }
                }

                MouseArea {
                    id: actionMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: !root.isBusy
                    onClicked: {
                        if (actionButton.actionType === "update") {
                            root.actionTriggered("update", root.pkgName, root.repository);
                        } else if (actionButton.actionType === "remove") {
                            root.actionTriggered("remove", root.pkgName, root.repository);
                        } else if (actionButton.actionType === "install") {
                            root.actionTriggered("install", root.pkgName, root.repository);
                        }
                    }
                }
            }
        }
    }

    // Clique geral no card para abrir modal de detalhes
    MouseArea {
        id: cardMouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        z: -1
        onClicked: root.clicked()
    }
}
