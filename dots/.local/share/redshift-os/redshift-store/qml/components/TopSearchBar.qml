import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    // --- Contratos de Propriedades e Sinais ---
    property var theme: null
    property string searchText: ""
    property string sourceFilter: "all" // "all" | "official" | "aur"
    property bool isDbLocked: false
    property bool isBusy: false

    signal searchTriggered(string query, string sourceFilter)
    signal sourceFilterSelected(string sourceFilter)
    signal refreshRequested()

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

    implicitWidth: 800
    implicitHeight: 56
    color: "transparent"

    // Timer de Debounce (300ms)
    Timer {
        id: debounceTimer
        interval: 300
        repeat: false
        onTriggered: {
            root.searchTriggered(root.searchText, root.sourceFilter)
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 12

        // 1. Caixa de Entrada da Pesquisa (Search Box)
        Rectangle {
            id: searchBox
            Layout.fillWidth: true
            Layout.maximumWidth: 520
            Layout.preferredWidth: 380
            Layout.preferredHeight: 44
            radius: root.getToken("radiusFull", 9999)
            color: searchBoxMouseArea.containsMouse || searchInput.activeFocus ?
                root.getToken("surfaceContainerHighest", "#363435") :
                root.getToken("surfaceContainerHigh", "#2b2a2a")
            border.width: searchInput.activeFocus ? 2 : 1
            border.color: searchInput.activeFocus ?
                root.getToken("primary", "#d0bcff") :
                root.getToken("outlineVariant", "#49454f")

            Behavior on color { ColorAnimation { duration: 150 } }
            Behavior on border.color { ColorAnimation { duration: 150 } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 12
                spacing: 10

                Text {
                    text: "search"
                    font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                    font.pixelSize: 20
                    color: searchInput.activeFocus ?
                        root.getToken("primary", "#d0bcff") :
                        root.getToken("onSurfaceVariant", "#cbc5ca")
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // Placeholder
                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        text: "Pesquisar pacotes oficiais e AUR..."
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 13
                        color: root.getToken("onSurfaceVariant", "#cbc5ca")
                        opacity: 0.65
                        visible: searchInput.text.length === 0
                    }

                    TextInput {
                        id: searchInput
                        anchors.fill: parent
                        verticalAlignment: TextInput.AlignVCenter
                        text: root.searchText
                        font.family: root.getToken("fontFamily", "Google Sans Flex")
                        font.pixelSize: 13
                        color: root.getToken("onSurface", "#e6e1e1")
                        selectByMouse: true
                        selectionColor: root.getToken("primaryContainer", "#4f378b")
                        selectedTextColor: root.getToken("onPrimaryContainer", "#eaddff")

                        onTextChanged: {
                            if (root.searchText !== text) {
                                root.searchText = text;
                                debounceTimer.restart();
                            }
                        }

                        onAccepted: {
                            debounceTimer.stop();
                            root.searchTriggered(root.searchText, root.sourceFilter);
                        }
                    }
                }

                // Botão de Limpar Busca
                Rectangle {
                    visible: searchInput.text.length > 0
                    width: 24
                    height: 24
                    radius: 12
                    color: clearMouseArea.containsMouse ?
                        root.getToken("surfaceContainer", "#201f20") : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "close"
                        font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                        font.pixelSize: 16
                        color: root.getToken("onSurfaceVariant", "#cbc5ca")
                    }

                    MouseArea {
                        id: clearMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            searchInput.text = "";
                            root.searchText = "";
                            debounceTimer.stop();
                            root.searchTriggered("", root.sourceFilter);
                        }
                    }
                }
            }

            MouseArea {
                id: searchBoxMouseArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.NoButton
            }
        }

        // 2. Chips de Filtro Rápido de Origem (Todos / Oficial / AUR)
        RowLayout {
            spacing: 6

            Repeater {
                model: [
                    { id: "all", label: "Todos", icon: "apps" },
                    { id: "official", label: "Oficial Pacman", icon: "verified" },
                    { id: "aur", label: "AUR", icon: "cloud_download" }
                ]

                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    readonly property bool isSelected: root.sourceFilter === modelData.id
                    readonly property bool isHovered: chipMouseArea.containsMouse

                    implicitWidth: chipRow.implicitWidth + 24
                    implicitHeight: 36
                    radius: root.getToken("radiusFull", 9999)

                    color: {
                        if (isSelected) {
                            return modelData.id === "aur" ?
                                root.getToken("tertiaryContainer", "#633b48") :
                                root.getToken("secondaryContainer", "#4a4458");
                        }
                        return isHovered ?
                            root.getToken("surfaceContainerHigh", "#2b2a2a") :
                            root.getToken("surfaceContainer", "#201f20");
                    }

                    border.width: 1
                    border.color: isSelected ?
                        (modelData.id === "aur" ? root.getToken("tertiary", "#efb8c8") : root.getToken("primary", "#d0bcff")) :
                        root.getToken("outlineVariant", "#49454f")

                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: chip.modelData.icon
                            font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                            font.pixelSize: 16
                            color: chip.isSelected ?
                                (chip.modelData.id === "aur" ? root.getToken("tertiary", "#efb8c8") : root.getToken("primary", "#d0bcff")) :
                                root.getToken("onSurfaceVariant", "#cbc5ca")
                        }

                        Text {
                            text: chip.modelData.label
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 12
                            font.weight: chip.isSelected ? Font.Medium : Font.Normal
                            color: chip.isSelected ?
                                root.getToken("onSurface", "#e6e1e1") :
                                root.getToken("onSurfaceVariant", "#cbc5ca")
                        }
                    }

                    MouseArea {
                        id: chipMouseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.sourceFilter = chip.modelData.id;
                            root.sourceFilterSelected(chip.modelData.id);
                            debounceTimer.stop();
                            root.searchTriggered(root.searchText, chip.modelData.id);
                        }
                    }
                }
            }
        }

        // Espaço elástico
        Item {
            Layout.fillWidth: true
        }

        // 3. Badge de Aviso de Banco de Dados Bloqueado (db.lck)
        Rectangle {
            visible: root.isDbLocked
            implicitWidth: lockRow.implicitWidth + 20
            implicitHeight: 36
            radius: root.getToken("radiusFull", 9999)
            color: root.getToken("errorContainer", "#8c1d18")
            border.width: 1
            border.color: root.getToken("error", "#f2b8b5")

            RowLayout {
                id: lockRow
                anchors.centerIn: parent
                spacing: 6

                Text {
                    text: "lock"
                    font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                    font.pixelSize: 16
                    color: root.getToken("error", "#f2b8b5")
                }

                Text {
                    text: "db.lck ativo"
                    font.family: root.getToken("fontFamily", "Google Sans Flex")
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: root.getToken("onErrorContainer", "#f9dedc")
                }
            }
        }

        // 4. Botão de Atualizar Catálogo
        Rectangle {
            id: refreshBtn
            width: 40
            height: 40
            radius: root.getToken("radiusNormal", 14)
            color: refreshMouseArea.containsMouse ?
                root.getToken("surfaceContainerHigh", "#2b2a2a") :
                root.getToken("surfaceContainer", "#201f20")
            border.width: 1
            border.color: root.getToken("outlineVariant", "#49454f")
            opacity: root.isBusy ? 0.6 : 1.0

            Behavior on color { ColorAnimation { duration: 150 } }

            Text {
                id: refreshIcon
                anchors.centerIn: parent
                text: "refresh"
                font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                font.pixelSize: 20
                color: refreshMouseArea.containsMouse ?
                    root.getToken("primary", "#d0bcff") :
                    root.getToken("onSurfaceVariant", "#cbc5ca")

                RotationAnimation on rotation {
                    running: root.isBusy
                    loops: Animation.Infinite
                    from: 0
                    to: 360
                    duration: 1000
                }
            }

            MouseArea {
                id: refreshMouseArea
                anchors.fill: parent
                hoverEnabled: !root.isBusy
                cursorShape: root.isBusy ? Qt.ForbiddenCursor : Qt.PointingHandCursor
                enabled: !root.isBusy
                onClicked: root.refreshRequested()
            }
        }
    }
}
