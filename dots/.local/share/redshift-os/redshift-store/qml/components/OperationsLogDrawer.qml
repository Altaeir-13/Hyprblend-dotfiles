import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Rectangle {
    id: root

    // --- Contratos de Propriedades e Sinais ---
    property bool isOpen: false
    property var theme: null
    property string operationState: "idle"
    property string operationStatusText: ""
    property int operationProgress: 0
    property bool isBusy: false
    property string logText: ""
    property bool canCancel: false
    property string transactionStage: "idle"
    property bool waitingForInput: false
    property string currentPromptText: ""
    readonly property bool isAurMenuPrompt: {
        const t = (root.currentPromptText || "").toLowerCase();
        return t.indexOf("cleanbuild") !== -1 ||
               t.indexOf("diffs to show") !== -1 ||
               t.indexOf("diffs para mostrar") !== -1 ||
               t.indexOf("pkgbuilds to edit") !== -1 ||
               t.indexOf("[n]one") !== -1;
    }

    signal cancelRequested()
    signal clearLogsRequested()
    signal closeRequested()
    signal promptResponseRequested(bool accepted)
    signal customInputSubmitted(string text)

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

    implicitHeight: root.isOpen ? 260 : 0
    height: implicitHeight
    color: root.getToken("surfaceContainer", "#201f20")
    clip: true

    Behavior on height {
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    // Borda Superior
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: root.getToken("outlineVariant", "#49454f")
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        // 1. Barra de Status da Operação
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // Badge do Estado
            Rectangle {
                implicitWidth: stateBadgeRow.implicitWidth + 14
                height: 26
                radius: root.getToken("radiusFull", 9999)

                color: {
                    if (root.operationState === "success") return root.getToken("successContainer", "#374b3e");
                    if (root.operationState === "error") return root.getToken("errorContainer", "#8c1d18");
                    if (root.operationState === "cancelled") return root.getToken("warningContainer", "#594800");
                    if (root.isBusy) return root.getToken("primaryContainer", "#4f378b");
                    return root.getToken("surfaceContainerHigh", "#2b2a2a");
                }

                RowLayout {
                    id: stateBadgeRow
                    anchors.centerIn: parent
                    spacing: 5

                    Text {
                        text: {
                            if (root.operationState === "success") return "check_circle";
                            if (root.operationState === "error") return "error";
                            if (root.operationState === "cancelled") return "cancel";
                            if (root.isBusy) return "sync";
                            return "terminal";
                        }
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 15
                        color: {
                            if (root.operationState === "success") return root.getToken("success", "#b5ccba");
                            if (root.operationState === "error") return root.getToken("error", "#f2b8b5");
                            if (root.operationState === "cancelled") return root.getToken("warning", "#fbc02d");
                            if (root.isBusy) return root.getToken("primary", "#d0bcff");
                            return root.getToken("onSurfaceVariant", "#cbc5ca");
                        }

                        RotationAnimation on rotation {
                            running: root.isBusy
                            loops: Animation.Infinite
                            from: 0
                            to: 360
                            duration: 1000
                        }
                    }

                    Text {
                        text: {
                            switch (root.operationState) {
                                case "installing": return "Instalando";
                                case "removing": return "Removendo";
                                case "updating": return "Atualizando";
                                case "checking_updates": return "Verificando";
                                case "authenticating": return "Autenticação Polkit";
                                case "success": return "Sucesso";
                                case "error": return "Falha";
                                case "cancelled": return "Cancelado";
                                default: return "Console de Logs";
                            }
                        }
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        color: {
                            if (root.operationState === "success") return root.getToken("onSuccessContainer", "#d1e9d6");
                            if (root.operationState === "error") return root.getToken("onErrorContainer", "#f9dedc");
                            if (root.operationState === "cancelled") return root.getToken("onWarningContainer", "#ffe082");
                            if (root.isBusy) return root.getToken("onPrimaryContainer", "#eaddff");
                            return root.getToken("onSurface", "#e6e1e1");
                        }
                    }
                }
            }

            // Mensagem de Status da Operação
            Text {
                text: root.operationStatusText && root.operationStatusText.length > 0 ?
                    root.operationStatusText : "Aguardando próxima instrução do usuário..."
                font.family: root.getToken("fontFamily", "Google Sans Flex")
                font.pixelSize: 12
                color: root.getToken("onSurface", "#e6e1e1")
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            // Botão Cancelar Operação (visível durante processamento)
            Rectangle {
                visible: root.isBusy
                implicitWidth: cancelRow.implicitWidth + 14
                height: 26
                radius: root.getToken("radiusFull", 9999)
                color: {
                    if (!root.canCancel) return root.getToken("surfaceContainerHighest", "#363435");
                    return cancelMouse.containsMouse ? root.getToken("error", "#f2b8b5") : root.getToken("errorContainer", "#8c1d18");
                }
                border.width: 1
                border.color: root.canCancel ? root.getToken("error", "#f2b8b5") : root.getToken("outlineVariant", "#49454f")

                RowLayout {
                    id: cancelRow
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        text: root.canCancel ? "stop" : "lock"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 14
                        color: root.canCancel ? root.getToken("onErrorContainer", "#f9dedc") : root.getToken("onSurfaceVariant", "#cbc5ca")
                    }

                    Text {
                        text: root.canCancel ? "Cancelar Operação" : "Commit Crítico (Protegido)"
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: root.canCancel ? root.getToken("onErrorContainer", "#f9dedc") : root.getToken("onSurfaceVariant", "#cbc5ca")
                    }
                }

                MouseArea {
                    id: cancelMouse
                    anchors.fill: parent
                    hoverEnabled: root.canCancel
                    enabled: root.canCancel
                    cursorShape: root.canCancel ? Qt.PointingHandCursor : Qt.ForbiddenCursor
                    onClicked: root.cancelRequested()
                }
            }

            // Botão Limpar Logs
            Rectangle {
                implicitWidth: clearLogsRow.implicitWidth + 12
                height: 26
                radius: root.getToken("radiusSmall", 8)
                color: clearLogsMouse.containsMouse ? root.getToken("surfaceContainerHighest", "#363435") : "transparent"

                RowLayout {
                    id: clearLogsRow
                    anchors.centerIn: parent
                    spacing: 4

                    Text {
                        text: "delete_sweep"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 15
                        color: root.getToken("onSurfaceVariant", "#cbc5ca")
                    }

                    Text {
                        text: "Limpar"
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 11
                        color: root.getToken("onSurfaceVariant", "#cbc5ca")
                    }
                }

                MouseArea {
                    id: clearLogsMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.clearLogsRequested()
                }
            }

            // Botão Fechar/Recolher Drawer
            Rectangle {
                width: 26
                height: 26
                radius: 13
                color: closeDrawerMouse.containsMouse ? root.getToken("surfaceContainerHighest", "#363435") : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "expand_more"
                    font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                    font.pixelSize: 18
                    color: root.getToken("onSurfaceVariant", "#cbc5ca")
                }

                MouseArea {
                    id: closeDrawerMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.closeRequested()
                }
            }
        }

        // Barra de Confirmação Interativa (visível quando waitingForInput for true)
        Rectangle {
            id: promptBar
            visible: root.waitingForInput
            Layout.fillWidth: true
            height: 40
            radius: root.getToken("radiusNormal", 14)
            color: root.getToken("primaryContainer", "#4f378b")
            border.width: 1
            border.color: root.getToken("primary", "#d0bcff")

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 10
                spacing: 8

                Text {
                    text: root.isAurMenuPrompt ? "rate_review" : "help"
                    font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                    font.pixelSize: 18
                    color: root.getToken("primary", "#d0bcff")
                }

                Text {
                    text: root.currentPromptText && root.currentPromptText.length > 0 ?
                        root.currentPromptText : "Confirmação necessária para continuar a operação:"
                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    color: root.getToken("onPrimaryContainer", "#eaddff")
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                // Opções para Menus de Revisão do AUR (cleanBuild, Diffs, PKGBUILDs)
                RowLayout {
                    visible: root.isAurMenuPrompt
                    spacing: 6

                    // Botão Nenhum (N)
                    Rectangle {
                        implicitWidth: aurNoneRow.implicitWidth + 14
                        height: 28
                        radius: root.getToken("radiusFull", 9999)
                        color: aurNoneMouse.containsMouse ? root.getToken("primary", "#d0bcff") : root.getToken("secondaryContainer", "#4a4458")

                        RowLayout {
                            id: aurNoneRow
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                text: "close"
                                font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                                font.pixelSize: 13
                                color: aurNoneMouse.containsMouse ? root.getToken("onPrimary", "#381e72") : root.getToken("onSecondaryContainer", "#e8def8")
                            }

                            Text {
                                text: "Nenhum (N)"
                                font.family: root.getToken("fontFamily", "Google Sans Flex")
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: aurNoneMouse.containsMouse ? root.getToken("onPrimary", "#381e72") : root.getToken("onSecondaryContainer", "#e8def8")
                            }
                        }

                        MouseArea {
                            id: aurNoneMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.customInputSubmitted("N")
                        }
                    }

                    // Botão Mostrar Todos / Diff (A)
                    Rectangle {
                        implicitWidth: aurAllRow.implicitWidth + 14
                        height: 28
                        radius: root.getToken("radiusFull", 9999)
                        color: aurAllMouse.containsMouse ? root.getToken("tertiary", "#efb8c8") : root.getToken("surfaceContainerHighest", "#363435")

                        RowLayout {
                            id: aurAllRow
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                text: "visibility"
                                font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                                font.pixelSize: 13
                                color: aurAllMouse.containsMouse ? root.getToken("onTertiary", "#492532") : root.getToken("onSurface", "#e6e1e1")
                            }

                            Text {
                                text: "Mostrar Todos / Diff (A)"
                                font.family: root.getToken("fontFamily", "Google Sans Flex")
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                color: aurAllMouse.containsMouse ? root.getToken("onTertiary", "#492532") : root.getToken("onSurface", "#e6e1e1")
                            }
                        }

                        MouseArea {
                            id: aurAllMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.customInputSubmitted("A")
                        }
                    }

                    // Botão Abortar (Ab)
                    Rectangle {
                        implicitWidth: aurAbortRow.implicitWidth + 14
                        height: 28
                        radius: root.getToken("radiusFull", 9999)
                        color: aurAbortMouse.containsMouse ? root.getToken("error", "#f2b8b5") : root.getToken("errorContainer", "#8c1d18")

                        RowLayout {
                            id: aurAbortRow
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                text: "block"
                                font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                                font.pixelSize: 13
                                color: root.getToken("onErrorContainer", "#f9dedc")
                            }

                            Text {
                                text: "Abortar (Ab)"
                                font.family: root.getToken("fontFamily", "Google Sans Flex")
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: root.getToken("onErrorContainer", "#f9dedc")
                            }
                        }

                        MouseArea {
                            id: aurAbortMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.customInputSubmitted("Ab")
                        }
                    }
                }

                // Opções para Prompts Padrão de Confirmação (S/N)
                RowLayout {
                    visible: !root.isAurMenuPrompt
                    spacing: 6

                    // Botão Confirmar (S/Y)
                    Rectangle {
                        implicitWidth: confirmBtnRow.implicitWidth + 16
                        height: 28
                        radius: root.getToken("radiusFull", 9999)
                        color: confirmMouse.containsMouse ? root.getToken("primary", "#d0bcff") : root.getToken("secondaryContainer", "#4a4458")

                        RowLayout {
                            id: confirmBtnRow
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                text: "check"
                                font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                                font.pixelSize: 14
                                color: confirmMouse.containsMouse ? root.getToken("onPrimary", "#381e72") : root.getToken("onSecondaryContainer", "#e8def8")
                            }

                            Text {
                                text: "Confirmar (S/Y)"
                                font.family: root.getToken("fontFamily", "Google Sans Flex")
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: confirmMouse.containsMouse ? root.getToken("onPrimary", "#381e72") : root.getToken("onSecondaryContainer", "#e8def8")
                            }
                        }

                        MouseArea {
                            id: confirmMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.promptResponseRequested(true)
                        }
                    }

                    // Botão Recusar (N)
                    Rectangle {
                        implicitWidth: declineBtnRow.implicitWidth + 16
                        height: 28
                        radius: root.getToken("radiusFull", 9999)
                        color: declineMouse.containsMouse ? root.getToken("error", "#f2b8b5") : root.getToken("errorContainer", "#8c1d18")

                        RowLayout {
                            id: declineBtnRow
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                text: "close"
                                font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                                font.pixelSize: 14
                                color: root.getToken("onErrorContainer", "#f9dedc")
                            }

                            Text {
                                text: "Recusar (N)"
                                font.family: root.getToken("fontFamily", "Google Sans Flex")
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: root.getToken("onErrorContainer", "#f9dedc")
                            }
                        }

                        MouseArea {
                            id: declineMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.promptResponseRequested(false)
                        }
                    }
                }

                // Campo Compacto de Resposta Manual (para ambos os modos: permite digitar números, ranges, etc.)
                Rectangle {
                    id: customInputBox
                    implicitWidth: 125
                    height: 28
                    radius: root.getToken("radiusFull", 9999)
                    color: root.getToken("surfaceContainerLowest", "#0f0e0e")
                    border.width: customPromptInput.activeFocus ? 1.5 : 1
                    border.color: customPromptInput.activeFocus ?
                        root.getToken("primary", "#d0bcff") : root.getToken("outlineVariant", "#49454f")

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 3
                        spacing: 4

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            Text {
                                anchors.fill: parent
                                verticalAlignment: Text.AlignVCenter
                                text: "Digitar..."
                                font.family: root.getToken("fontFamily", "Google Sans Flex")
                                font.pixelSize: 11
                                color: root.getToken("onSurfaceVariant", "#cbc5ca")
                                opacity: 0.6
                                visible: customPromptInput.text.length === 0
                            }

                            TextInput {
                                id: customPromptInput
                                anchors.fill: parent
                                verticalAlignment: TextInput.AlignVCenter
                                font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                                font.pixelSize: 11
                                color: root.getToken("onSurface", "#e6e1e1")
                                selectByMouse: true
                                clip: true

                                onAccepted: {
                                    if (text.trim().length > 0) {
                                        root.customInputSubmitted(text.trim());
                                        text = "";
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: 22
                            height: 22
                            radius: 11
                            color: sendBtnMouse.containsMouse ?
                                root.getToken("primary", "#d0bcff") : root.getToken("surfaceContainerHighest", "#363435")

                            Text {
                                anchors.centerIn: parent
                                text: "send"
                                font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                                font.pixelSize: 12
                                color: sendBtnMouse.containsMouse ?
                                    root.getToken("onPrimary", "#381e72") : root.getToken("onSurface", "#e6e1e1")
                            }

                            MouseArea {
                                id: sendBtnMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (customPromptInput.text.trim().length > 0) {
                                        root.customInputSubmitted(customPromptInput.text.trim());
                                        customPromptInput.text = "";
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // 2. Barra de Progresso
        Rectangle {
            id: progressBarTrack
            Layout.fillWidth: true
            height: 4
            radius: 2
            color: root.getToken("surfaceContainerHighest", "#363435")
            clip: true
            visible: root.isBusy

            // Progresso determinado ou indeterminado
            Rectangle {
                id: progressBarThumb
                height: parent.height
                radius: 2
                color: root.getToken("primary", "#d0bcff")

                width: {
                    if (root.operationProgress >= 0) {
                        return Math.max(0, Math.min(progressBarTrack.width, progressBarTrack.width * (root.operationProgress / 100.0)));
                    }
                    return progressBarTrack.width * 0.35;
                }

                x: {
                    if (root.operationProgress >= 0) return 0;
                    return indeterminateAnimItem.currentX;
                }
            }

            Item {
                id: indeterminateAnimItem
                property real currentX: 0
                NumberAnimation on currentX {
                    running: root.isBusy && root.operationProgress < 0
                    loops: Animation.Infinite
                    from: -progressBarTrack.width * 0.35
                    to: progressBarTrack.width
                    duration: 1400
                }
            }
        }

        // 3. Área de Console de Logs em Tempo Real
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: root.getToken("radiusSmall", 8)
            color: root.getToken("surfaceContainerLowest", "#0f0e0e")
            border.width: 1
            border.color: Qt.alpha(root.getToken("outlineVariant", "#49454f"), 0.5)

            Flickable {
                id: logFlickable
                anchors.fill: parent
                anchors.margins: 8
                contentWidth: Math.max(width, logTextItem.implicitWidth)
                contentHeight: Math.max(height, logTextItem.implicitHeight)
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    active: logFlickable.moving || logFlickable.flicking
                }

                ScrollBar.horizontal: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    active: logFlickable.moving || logFlickable.flicking
                }

                TextEdit {
                    id: logTextItem
                    text: root.logText && root.logText.length > 0 ?
                        root.logText : "# Pronto. Nenhuma transação executada até o momento.\n# As saídas do pacman, yay e checagens de lock serão exibidas aqui em tempo real."
                    font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                    font.pixelSize: 11
                    color: root.getToken("onSurface", "#e6e1e1")
                    readOnly: true
                    selectByMouse: true
                    selectionColor: root.getToken("primaryContainer", "#4f378b")
                    selectedTextColor: root.getToken("onPrimaryContainer", "#eaddff")

                    // Auto scroll para o final quando novos logs chegam
                    onTextChanged: {
                        Qt.callLater(() => {
                            logFlickable.contentY = Math.max(0, logFlickable.contentHeight - logFlickable.height);
                        });
                    }
                }
            }
        }
    }
}
