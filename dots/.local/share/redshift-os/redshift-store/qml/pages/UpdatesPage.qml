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
    signal checkUpdatesRequested()
    signal updateAllRequested()

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
    readonly property int updatesCount: (root.storeBridge && root.storeBridge.updatesCount !== undefined) ?
                                        root.storeBridge.updatesCount : 0
    readonly property int modelCount: (root.storeBridge && root.storeBridge.updatesModel && root.storeBridge.updatesModel.count !== undefined) ?
                                      root.storeBridge.updatesModel.count : 0
    readonly property int effectiveCount: root.updatesCount > 0 ? root.updatesCount : root.modelCount

    readonly property string lastOutcome: (root.storeBridge && root.storeBridge.lastUpdateOutcome) ?
                                          root.storeBridge.lastUpdateOutcome : ""
    readonly property string lastSummary: (root.storeBridge && root.storeBridge.lastUpdateSummary) ?
                                          root.storeBridge.lastUpdateSummary : ""

    property bool bannerDismissed: false
    onLastOutcomeChanged: bannerDismissed = false

    color: getToken("surface", "#141313")

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 14

        // =====================================================================
        // 1. Cabeçalho da Central de Atualizações (Microsoft Store Style)
        // =====================================================================
        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                RowLayout {
                    spacing: 8

                    Text {
                        text: "Central de Atualizações"
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 22
                        font.weight: Font.Bold
                        color: root.getToken("onSurface", "#e6e1e1")
                    }

                    // Badge de contagem de atualizações
                    Rectangle {
                        visible: root.effectiveCount > 0
                        implicitWidth: updatesBadgeText.implicitWidth + 12
                        height: 22
                        radius: root.getToken("radiusFull", 9999)
                        color: root.getToken("warningContainer", "#594800")
                        border.width: 1
                        border.color: root.getToken("warning", "#fbc02d")

                        Text {
                            id: updatesBadgeText
                            anchors.centerIn: parent
                            text: root.effectiveCount.toString()
                            font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                            font.pixelSize: 11
                            font.weight: Font.Bold
                            color: root.getToken("onWarningContainer", "#ffe082")
                        }
                    }
                }

                // Subtítulo explicitando a política anti-partial upgrade do Arch Linux
                Text {
                    text: root.effectiveCount > 0 ?
                        ("Atualizar Tudo executa yay -Syu (sincronizando pacotes oficiais e comunitários AUR simultaneamente). Para evitar inconsistências no Arch Linux, pacotes oficiais são atualizados de forma sincronizada com os espelhos.") :
                        "Todos os pacotes estão sincronizados com os espelhos oficiais do Arch Linux e AUR."
                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                    font.pixelSize: 12
                    color: root.getToken("onSurfaceVariant", "#cbc5ca")
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                    lineHeight: 1.25
                }
            }

            // Botão "Verificar Atualizações"
            Rectangle {
                implicitWidth: checkRow.implicitWidth + 24
                height: 38
                radius: root.getToken("radiusFull", 9999)
                color: checkMouse.containsMouse ?
                    root.getToken("surfaceContainerHigh", "#2b2a2a") :
                    root.getToken("surfaceContainer", "#201f20")
                border.width: 1
                border.color: root.getToken("outlineVariant", "#49454f")

                RowLayout {
                    id: checkRow
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        text: "refresh"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 18
                        color: root.getToken("onSurface", "#e6e1e1")

                        RotationAnimation on rotation {
                            running: root.isBusy
                            loops: Animation.Infinite
                            from: 0
                            to: 360
                            duration: 1000
                        }
                    }

                    Text {
                        text: "Verificar"
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 12
                        font.weight: Font.Medium
                        color: root.getToken("onSurface", "#e6e1e1")
                    }
                }

                MouseArea {
                    id: checkMouse
                    anchors.fill: parent
                    hoverEnabled: !root.isBusy
                    cursorShape: root.isBusy ? Qt.ForbiddenCursor : Qt.PointingHandCursor
                    enabled: !root.isBusy
                    onClicked: root.checkUpdatesRequested()
                }
            }

            // Botão Principal "Atualizar Tudo (yay -Syu)"
            Rectangle {
                visible: root.effectiveCount > 0
                implicitWidth: updateAllRow.implicitWidth + 24
                height: 38
                radius: root.getToken("radiusFull", 9999)
                color: updateAllMouse.containsMouse ?
                    root.getToken("primary", "#d0bcff") :
                    root.getToken("primaryContainer", "#4f378b")
                opacity: root.isBusy ? 0.6 : 1.0

                Behavior on color { ColorAnimation { duration: 150 } }

                RowLayout {
                    id: updateAllRow
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        text: "system_update_alt"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 18
                        color: updateAllMouse.containsMouse ?
                            root.getToken("onPrimary", "#381e72") :
                            root.getToken("onPrimaryContainer", "#eaddff")
                    }

                    Text {
                        text: "Atualizar Tudo (yay -Syu)"
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        color: updateAllMouse.containsMouse ?
                            root.getToken("onPrimary", "#381e72") :
                            root.getToken("onPrimaryContainer", "#eaddff")
                    }
                }

                MouseArea {
                    id: updateAllMouse
                    anchors.fill: parent
                    hoverEnabled: !root.isBusy
                    cursorShape: root.isBusy ? Qt.ForbiddenCursor : Qt.PointingHandCursor
                    enabled: !root.isBusy && root.effectiveCount > 0
                    onClicked: root.updateAllRequested()
                }
            }
        }

        // =====================================================================
        // 2. Banner de Resultado da Última Transação (Pós-verificação)
        // =====================================================================
        Rectangle {
            id: outcomeBanner
            objectName: "outcomeBanner"
            readonly property bool isUnchanged: root.lastOutcome === "unchanged" || root.lastOutcome === "divergent_db"
            readonly property bool isComplete: root.lastOutcome === "complete"
            readonly property bool isPartial: root.lastOutcome === "partial"
            readonly property bool isFailed: root.lastOutcome === "failed"
            readonly property bool isCancelled: root.lastOutcome === "cancelled"

            visible: root.lastOutcome.length > 0 && !root.bannerDismissed
            Layout.fillWidth: true
            implicitHeight: outcomeRow.implicitHeight + 20
            radius: root.getToken("radiusNormal", 14)
            color: {
                if (isComplete) return root.getToken("successContainer", "#374b3e");
                if (isUnchanged) return root.getToken("secondaryContainer", "#4a4458");
                if (isPartial) return root.getToken("warningContainer", "#594800");
                if (isFailed) return root.getToken("errorContainer", "#8c1d18");
                return root.getToken("surfaceContainerHighest", "#363435");
            }
            border.width: 1
            border.color: {
                if (isComplete) return root.getToken("success", "#b5ccba");
                if (isUnchanged) return root.getToken("secondary", "#ccc2dc");
                if (isPartial) return root.getToken("warning", "#fbc02d");
                if (isFailed) return root.getToken("error", "#f2b8b5");
                return root.getToken("outlineVariant", "#49454f");
            }

            RowLayout {
                id: outcomeRow
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                Text {
                    text: {
                        if (outcomeBanner.isComplete) return "verified";
                        if (outcomeBanner.isUnchanged) return "info";
                        if (outcomeBanner.isPartial) return "warning";
                        if (outcomeBanner.isFailed) return "error";
                        return "cancel";
                    }
                    font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                    font.pixelSize: 22
                    color: {
                        if (outcomeBanner.isComplete) return root.getToken("success", "#b5ccba");
                        if (outcomeBanner.isUnchanged) return root.getToken("secondary", "#ccc2dc");
                        if (outcomeBanner.isPartial) return root.getToken("warning", "#fbc02d");
                        if (outcomeBanner.isFailed) return root.getToken("error", "#f2b8b5");
                        return root.getToken("onSurfaceVariant", "#cbc5ca");
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: {
                            if (outcomeBanner.isComplete) return "Atualização do sistema concluída com êxito.";
                            if (outcomeBanner.isUnchanged) return "Nenhuma alteração realizada no pacote";
                            if (outcomeBanner.isPartial) return "Atualização parcial realizada.";
                            if (outcomeBanner.isFailed) return "Falha na atualização.";
                            return "Operação cancelada pelo usuário.";
                        }
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 13
                        font.weight: Font.Bold
                        color: {
                            if (outcomeBanner.isComplete) return root.getToken("onSuccessContainer", "#d1e9d6");
                            if (outcomeBanner.isUnchanged) return root.getToken("onSecondaryContainer", "#e8def8");
                            if (outcomeBanner.isPartial) return root.getToken("onWarningContainer", "#ffe082");
                            if (outcomeBanner.isFailed) return root.getToken("onErrorContainer", "#f9dedc");
                            return root.getToken("onSurface", "#e6e1e1");
                        }
                    }

                    Text {
                        text: {
                            if (root.lastSummary.length > 0) return root.lastSummary;
                            if (outcomeBanner.isComplete) return "Todas as atualizações do sistema foram aplicadas com sucesso e os pacotes estão sincronizados.";
                            if (outcomeBanner.isUnchanged) return "Nenhuma alteração foi realizada no pacote e ele continua na versão anterior devido a sincronização pendente do banco local.";
                            if (outcomeBanner.isPartial) return "Atualização parcial realizada. Alguns pacotes ainda requerem atenção.";
                            if (outcomeBanner.isFailed) return "Falha no processo de atualização. Verifique o console de logs.";
                            return "A operação foi interrompida pelo usuário antes da conclusão.";
                        }
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 11
                        color: {
                            if (outcomeBanner.isComplete) return root.getToken("onSuccessContainer", "#d1e9d6");
                            if (outcomeBanner.isUnchanged) return root.getToken("onSecondaryContainer", "#e8def8");
                            if (outcomeBanner.isPartial) return root.getToken("onWarningContainer", "#ffe082");
                            if (outcomeBanner.isFailed) return root.getToken("onErrorContainer", "#f9dedc");
                            return root.getToken("onSurfaceVariant", "#cbc5ca");
                        }
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }
                }

                Rectangle {
                    width: 26
                    height: 26
                    radius: 13
                    color: closeBannerMouse.containsMouse ? root.getToken("surfaceContainerHighest", "#363435") : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "close"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 16
                        color: root.getToken("onSurfaceVariant", "#cbc5ca")
                    }

                    MouseArea {
                        id: closeBannerMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.bannerDismissed = true
                    }
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

        // =====================================================================
        // 3. Área Central: Lista de Atualizações ou Estado 100% Atualizado
        // =====================================================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Lista Detalhada de Pacotes com Atualização
            ListView {
                id: updatesListView
                anchors.fill: parent
                clip: true
                spacing: 10
                boundsBehavior: Flickable.StopAtBounds
                visible: root.effectiveCount > 0

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    active: updatesListView.moving || updatesListView.flicking
                }

                model: root.storeBridge ? root.storeBridge.updatesModel : null

                delegate: Rectangle {
                    id: updateItemCard
                    width: updatesListView.width
                    height: 74
                    radius: root.getToken("radiusNormal", 14)
                    color: itemMouse.containsMouse ?
                        root.getToken("surfaceContainerHigh", "#2b2a2a") :
                        root.getToken("surfaceContainer", "#201f20")
                    border.width: 1
                    border.color: itemMouse.containsMouse ?
                        root.getToken("primary", "#d0bcff") :
                        root.getToken("outlineVariant", "#49454f")

                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    readonly property string pName: (model && model.name !== undefined) ? model.name : ""
                    readonly property string dName: (model && model.displayName !== undefined) ? model.displayName : ""
                    readonly property string curVer: (model && model.installedVersion !== undefined) ? model.installedVersion : ""
                    readonly property string newVer: (model && model.version !== undefined) ? model.version : ""
                    readonly property string repo: (model && model.repository !== undefined) ? model.repository : "extra"
                    readonly property string src: (model && model.source !== undefined) ? model.source : "official"
                    readonly property bool isAur: src === "aur" || repo === "aur"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 14

                        // Ícone do Pacote
                        Rectangle {
                            width: 44
                            height: 44
                            radius: root.getToken("radiusNormal", 14)
                            color: updateItemCard.isAur ?
                                root.getToken("tertiaryContainer", "#633b48") :
                                root.getToken("primaryContainer", "#4f378b")

                            Text {
                                anchors.centerIn: parent
                                text: updateItemCard.isAur ? "cloud_download" : "upgrade"
                                font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                                font.pixelSize: 22
                                color: updateItemCard.isAur ?
                                    root.getToken("onTertiaryContainer", "#ffd8e4") :
                                    root.getToken("onPrimaryContainer", "#eaddff")
                            }
                        }

                        // Informações do Pacote
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            RowLayout {
                                spacing: 8

                                Text {
                                    text: updateItemCard.dName && updateItemCard.dName.length > 0 ?
                                          updateItemCard.dName : updateItemCard.pName
                                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                    color: root.getToken("onSurface", "#e6e1e1")
                                }

                                Text {
                                    text: "(" + updateItemCard.pName + ")"
                                    font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                                    font.pixelSize: 11
                                    color: root.getToken("onSurfaceVariant", "#cbc5ca")
                                    opacity: 0.75
                                }

                                // Badge de repositório
                                Rectangle {
                                    implicitWidth: repoLabel.implicitWidth + 8
                                    height: 18
                                    radius: root.getToken("radiusSmall", 8)
                                    color: updateItemCard.isAur ?
                                        root.getToken("tertiaryContainer", "#633b48") :
                                        root.getToken("secondaryContainer", "#4a4458")

                                    Text {
                                        id: repoLabel
                                        anchors.centerIn: parent
                                        text: updateItemCard.repo.toUpperCase()
                                        font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                        color: updateItemCard.isAur ?
                                            root.getToken("onTertiaryContainer", "#ffd8e4") :
                                            root.getToken("onSecondaryContainer", "#e8def8")
                                    }
                                }
                            }

                            // Transição de Versão: curVer -> newVer
                            RowLayout {
                                spacing: 6

                                Text {
                                    text: updateItemCard.curVer.length > 0 ? updateItemCard.curVer : "instalado"
                                    font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                                    font.pixelSize: 11
                                    color: root.getToken("onSurfaceVariant", "#cbc5ca")
                                }

                                Text {
                                    text: "arrow_forward"
                                    font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                                    font.pixelSize: 13
                                    color: root.getToken("primary", "#d0bcff")
                                }

                                Text {
                                    text: updateItemCard.newVer
                                    font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                                    font.pixelSize: 11
                                    font.weight: Font.Bold
                                    color: root.getToken("primary", "#d0bcff")
                                }
                            }
                        }

                        // Botão Individual de Atualização
                        Rectangle {
                            implicitWidth: singleUpdateRow.implicitWidth + 20
                            height: 32
                            radius: root.getToken("radiusFull", 9999)
                            color: singleUpdateMouse.containsMouse ?
                                root.getToken("primary", "#d0bcff") :
                                root.getToken("primaryContainer", "#4f378b")

                            Behavior on color { ColorAnimation { duration: 150 } }

                            RowLayout {
                                id: singleUpdateRow
                                anchors.centerIn: parent
                                spacing: 4

                                Text {
                                    text: "upgrade"
                                    font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                                    font.pixelSize: 15
                                    color: singleUpdateMouse.containsMouse ?
                                        root.getToken("onPrimary", "#381e72") :
                                        root.getToken("onPrimaryContainer", "#eaddff")
                                }

                                Text {
                                    text: !updateItemCard.isAur ? "Atualizar Sistema (Syu)" : "Atualizar Pacote AUR"
                                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                                    font.pixelSize: 11
                                    font.weight: Font.DemiBold
                                    color: singleUpdateMouse.containsMouse ?
                                        root.getToken("onPrimary", "#381e72") :
                                        root.getToken("onPrimaryContainer", "#eaddff")
                                }
                            }

                            MouseArea {
                                id: singleUpdateMouse
                                anchors.fill: parent
                                hoverEnabled: !root.isBusy
                                cursorShape: root.isBusy ? Qt.ForbiddenCursor : Qt.PointingHandCursor
                                enabled: !root.isBusy
                                onClicked: {
                                    if (!updateItemCard.isAur) {
                                        confirmUpgradeDialog.openDialog(updateItemCard.pName, updateItemCard.repo);
                                    } else {
                                        root.actionRequested("update", updateItemCard.pName, updateItemCard.repo);
                                    }
                                }
                            }
                        }
                    }

                    MouseArea {
                        id: itemMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        z: -1
                        onClicked: root.packageSelected(updateItemCard.pName, updateItemCard.repo)
                    }
                }
            }

            // Estado "Sistema 100% Atualizado" (Empty State de Sucesso)
            Rectangle {
                visible: root.effectiveCount === 0 && !root.isBusy
                anchors.centerIn: parent
                width: 480
                height: 240
                radius: root.getToken("radiusLarge", 20)
                color: root.getToken("surfaceContainer", "#201f20")
                border.width: 1
                border.color: root.getToken("outlineVariant", "#49454f")

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 12
                    width: parent.width - 48

                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        width: 64
                        height: 64
                        radius: 32
                        color: root.getToken("successContainer", "#374b3e")

                        Text {
                            anchors.centerIn: parent
                            text: "verified"
                            font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                            font.pixelSize: 36
                            color: root.getToken("success", "#b5ccba")
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Seu sistema está atualizado!"
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 18
                        font.weight: Font.Bold
                        color: root.getToken("onSurface", "#e6e1e1")
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Todos os pacotes oficiais Arch Linux e comunitários AUR estão na versão mais recente disponível."
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 12
                        color: root.getToken("onSurfaceVariant", "#cbc5ca")
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
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
