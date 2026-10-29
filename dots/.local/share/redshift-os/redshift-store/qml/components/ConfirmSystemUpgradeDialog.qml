import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: root

    property var theme: null
    property string packageName: ""
    property string targetRepository: ""

    signal confirmed(string pkgName, string repository)
    signal cancelled()

    // Helpers de Tema e Fallbacks M3 Expressive
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

    function openDialog(pkgName, repository) {
        root.packageName = pkgName || "";
        root.targetRepository = repository || "";
        root.open();
    }

    modal: true
    dim: true
    parent: Overlay.overlay
    anchors.centerIn: Overlay.overlay

    width: Math.min(Overlay.overlay ? Overlay.overlay.width - 48 : 520, 520)
    padding: 20
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    background: Rectangle {
        radius: root.getToken("radiusLarge", 20)
        color: root.getToken("surfaceContainer", "#201f20")
        border.width: 1
        border.color: root.getToken("outlineVariant", "#49454f")
    }

    Overlay.modal: Rectangle {
        color: Qt.rgba(0, 0, 0, 0.65)
    }

    contentItem: ColumnLayout {
        spacing: 16

        // Cabeçalho do Diálogo
        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            Rectangle {
                width: 44
                height: 44
                radius: root.getToken("radiusNormal", 14)
                color: root.getToken("warningContainer", "#594800")

                Text {
                    anchors.centerIn: parent
                    text: "warning"
                    font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                    font.pixelSize: 24
                    color: root.getToken("warning", "#fbc02d")
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: "Atualização Completa do Sistema"
                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                    font.pixelSize: 16
                    font.weight: Font.Bold
                    color: root.getToken("onSurface", "#e6e1e1")
                }

                Text {
                    text: "Política do Arch Linux contra Partial Upgrades"
                    font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                    font.pixelSize: 11
                    color: root.getToken("onSurfaceVariant", "#cbc5ca")
                }
            }

            Rectangle {
                width: 28
                height: 28
                radius: 14
                color: closeMouse.containsMouse ? root.getToken("surfaceContainerHighest", "#363435") : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "close"
                    font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                    font.pixelSize: 18
                    color: root.getToken("onSurfaceVariant", "#cbc5ca")
                }

                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.cancelled();
                        root.close();
                    }
                }
            }
        }

        // Divisor
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: root.getToken("outlineVariant", "#49454f")
            opacity: 0.35
        }

        // Corpo Informativo
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 10

            Text {
                text: "O Arch Linux não suporta atualizações parciais (partial upgrades)."
                font.family: root.getToken("fontFamily", "Google Sans Flex")
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: root.getToken("warning", "#fbc02d")
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Text {
                text: "No Arch Linux e sistemas compatíveis, atualizar apenas o pacote <b>" + (root.packageName ? root.packageName : "selecionado") + "</b> isoladamente pode quebrar dependências de sistema e compatibilidade binária (ABI).<br><br>Para assegurar a estabilidade do sistema, o Redshift OS executará uma transação sincronizada de atualização completa (<b>yay -Syu</b> / <b>pacman -Syu</b>)."
                font.family: root.getToken("fontFamily", "Google Sans Flex")
                font.pixelSize: 12
                color: root.getToken("onSurfaceVariant", "#cbc5ca")
                textFormat: Text.RichText
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
                lineHeight: 1.3
            }

            // Box indicativa do comando
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: cmdRow.implicitHeight + 14
                radius: root.getToken("radiusSmall", 8)
                color: root.getToken("surfaceContainerLowest", "#0f0e0e")
                border.width: 1
                border.color: root.getToken("outlineVariant", "#49454f")

                RowLayout {
                    id: cmdRow
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    Text {
                        text: "terminal"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 16
                        color: root.getToken("primary", "#d0bcff")
                    }

                    Text {
                        text: "Transação Sincronizada: yay -Syu / pacman -Syu"
                        font.family: root.getToken("monoFontFamily", "JetBrains Mono NF")
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        color: root.getToken("onSurface", "#e6e1e1")
                        Layout.fillWidth: true
                    }
                }
            }
        }

        // Rodapé de Ações
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 6
            spacing: 10

            Item { Layout.fillWidth: true }

            Rectangle {
                implicitWidth: cancelText.implicitWidth + 24
                height: 36
                radius: root.getToken("radiusFull", 9999)
                color: cancelMouse.containsMouse ? root.getToken("surfaceContainerHigh", "#2b2a2a") : "transparent"
                border.width: 1
                border.color: root.getToken("outlineVariant", "#49454f")

                Text {
                    id: cancelText
                    anchors.centerIn: parent
                    text: "Cancelar"
                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    color: root.getToken("onSurface", "#e6e1e1")
                }

                MouseArea {
                    id: cancelMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.cancelled();
                        root.close();
                    }
                }
            }

            Rectangle {
                implicitWidth: confirmBtnRow.implicitWidth + 24
                height: 36
                radius: root.getToken("radiusFull", 9999)
                color: confirmMouse.containsMouse ? root.getToken("primary", "#d0bcff") : root.getToken("primaryContainer", "#4f378b")

                RowLayout {
                    id: confirmBtnRow
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        text: "system_update_alt"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 16
                        color: confirmMouse.containsMouse ? root.getToken("onPrimary", "#381e72") : root.getToken("onPrimaryContainer", "#eaddff")
                    }

                    Text {
                        text: "Atualizar Sistema (Syu)"
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        color: confirmMouse.containsMouse ? root.getToken("onPrimary", "#381e72") : root.getToken("onPrimaryContainer", "#eaddff")
                    }
                }

                MouseArea {
                    id: confirmMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        let pkg = root.packageName;
                        let repo = root.targetRepository;
                        root.close();
                        root.confirmed(pkg, repo);
                    }
                }
            }
        }
    }
}
