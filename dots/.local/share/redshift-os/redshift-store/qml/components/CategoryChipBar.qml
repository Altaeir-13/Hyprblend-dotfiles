import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root

    // --- Contratos de Propriedades e Sinais ---
    property var theme: null
    property string selectedCategory: "all"

    signal categorySelected(string categoryId)

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

    implicitWidth: 840
    implicitHeight: 48
    color: "transparent"

    Flickable {
        id: flickable
        anchors.fill: parent
        contentWidth: chipsRow.implicitWidth + 8
        contentHeight: parent.height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        // Suporte para rolagem horizontal com scroll do mouse
        WheelHandler {
            orientation: Qt.Horizontal
            onWheel: (event) => {
                flickable.contentX = Math.max(0, Math.min(flickable.contentWidth - flickable.width, flickable.contentX - event.angleDelta.y));
            }
        }

        RowLayout {
            id: chipsRow
            height: parent.height
            spacing: 8

            Repeater {
                model: [
                    { id: "all", label: "Todas", icon: "apps" },
                    { id: "featured", label: "Destaques", icon: "auto_awesome" },
                    { id: "internet", label: "Internet", icon: "public" },
                    { id: "development", label: "Desenvolvimento", icon: "code" },
                    { id: "games", label: "Jogos", icon: "sports_esports" },
                    { id: "multimedia", label: "Multimídia", icon: "movie" },
                    { id: "utilities", label: "Utilitários", icon: "construction" },
                    { id: "system", label: "Sistema", icon: "memory" },
                    { id: "office", label: "Escritório", icon: "edit_note" }
                ]

                delegate: Rectangle {
                    id: chipItem
                    required property var modelData
                    readonly property bool isSelected: root.selectedCategory === modelData.id
                    readonly property bool isHovered: chipMouse.containsMouse

                    implicitWidth: chipContent.implicitWidth + 24
                    height: 36
                    Layout.alignment: Qt.AlignVCenter
                    radius: root.getToken("radiusFull", 9999)

                    color: {
                        if (isSelected) return root.getToken("primary", "#d0bcff");
                        if (isHovered) return root.getToken("surfaceContainerHigh", "#2b2a2a");
                        return root.getToken("surfaceContainer", "#201f20");
                    }

                    border.width: 1
                    border.color: isSelected ?
                        root.getToken("primary", "#d0bcff") :
                        root.getToken("outlineVariant", "#49454f")

                    scale: isHovered && !isSelected ? 1.02 : 1.0

                    Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutQuad } }
                    Behavior on border.color { ColorAnimation { duration: 160; easing.type: Easing.OutQuad } }
                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                    RowLayout {
                        id: chipContent
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            text: chipItem.modelData.icon
                            font.family: root.getToken("iconFontFamily", "Material Symbols Rounded")
                            font.pixelSize: 17
                            color: chipItem.isSelected ?
                                root.getToken("onPrimary", "#381e72") :
                                (chipItem.isHovered ? root.getToken("onSurface", "#e6e1e1") : root.getToken("onSurfaceVariant", "#cbc5ca"))
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        Text {
                            text: chipItem.modelData.label
                            font.family: root.getToken("fontFamily", "Google Sans Flex")
                            font.pixelSize: 12
                            font.weight: chipItem.isSelected ? Font.DemiBold : Font.Normal
                            color: chipItem.isSelected ?
                                root.getToken("onPrimary", "#381e72") :
                                (chipItem.isHovered ? root.getToken("onSurface", "#e6e1e1") : root.getToken("onSurfaceVariant", "#cbc5ca"))
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }

                    MouseArea {
                        id: chipMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.selectedCategory = chipItem.modelData.id;
                            root.categorySelected(chipItem.modelData.id);
                        }
                    }
                }
            }
        }
    }
}
