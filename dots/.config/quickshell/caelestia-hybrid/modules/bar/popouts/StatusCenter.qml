pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import Quickshell
import Quickshell.Io

import Caelestia
import Caelestia.Config

import qs.components
import qs.services
import qs.modules.nexus
import qs.modules.utilities.cards as UtilityCards

Item {
    id: root

    required property var popouts

    // Recebido do Panels.qml somente no popout real da barra.
    property var screenState: null

    property string page: "home"

    property bool nightLightEnabled: false
    property bool keepAwakeEnabled: false

    readonly property PersistentProperties recorderProps:
        PersistentProperties {
            property bool recordingListExpanded: false
            property string recordingConfirmDelete
            property string recordingMode

            reloadableId: "quickControlsRecorder"
        }

    implicitWidth:
        page === "recorder"
            ? Tokens.sizes.utilities.width
            : 330

    implicitHeight:
        pageLoader.item?.implicitHeight ?? 0


    // ========================================================
    // NIGHT LIGHT
    // ========================================================

    function refreshNightLight(): void {
        if (!nightQuery.running)
            nightQuery.running = true;
    }

    function toggleNightLight(): void {
        root.nightLightEnabled =
            !root.nightLightEnabled;

        if (!nightToggle.running)
            nightToggle.running = true;

        nightRefresh.restart();
    }

    Process {
        id: nightQuery

        command: [
            "bash",
            "-lc",
            "\"${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/caelestia-hybrid/scripts/nightlight.sh\" status"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                const value =
                    text.trim().toLowerCase();

                root.nightLightEnabled =
                    value === "on"
                    || value === "true"
                    || value === "1";
            }
        }
    }

    Process {
        id: nightToggle

        command: [
            "bash",
            "-lc",
            "\"${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/caelestia-hybrid/scripts/nightlight.sh\" toggle"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                const value =
                    text.trim().toLowerCase();

                root.nightLightEnabled =
                    value === "on"
                    || value === "true"
                    || value === "1";
            }
        }
    }

    Timer {
        id: nightRefresh

        interval: 260

        onTriggered:
            root.refreshNightLight()
    }


    // ========================================================
    // KEEP AWAKE
    // ========================================================

    function refreshAwake(): void {
        if (!awakeQuery.running)
            awakeQuery.running = true;
    }

    function toggleAwake(): void {
        Quickshell.execDetached([
            "qs",
            "-c",
            "caelestia-hybrid",
            "ipc",
            "call",
            "idleInhibitor",
            "toggle"
        ]);

        awakeRefresh.restart();
    }

    Process {
        id: awakeQuery

        command: [
            "qs",
            "-c",
            "caelestia-hybrid",
            "ipc",
            "call",
            "idleInhibitor",
            "isEnabled"
        ]

        stdout: StdioCollector {
            onStreamFinished: {
                const value =
                    text.trim().toLowerCase();

                root.keepAwakeEnabled =
                    value === "true"
                    || value === "1";
            }
        }
    }

    Timer {
        id: awakeRefresh

        interval: 220

        onTriggered:
            root.refreshAwake()
    }


    Component.onCompleted: {
        refreshNightLight();
        refreshAwake();
    }


    Connections {
        target: root.popouts

        function onHasCurrentChanged(): void {
            if (!root.popouts.hasCurrent)
                root.page = "home";
        }
    }


    Loader {
        id: pageLoader

        width: root.implicitWidth

        sourceComponent:
            root.page === "recorder"
                ? recorderPage
                : homePage
    }


    // ========================================================
    // HOME
    // ========================================================

    Component {
        id: homePage

        ColumnLayout {
            width: root.implicitWidth

            spacing:
                Tokens.spacing.medium


            // ------------------------------------------------
            // APENAS O TÍTULO.
            // Subtítulo removido conforme solicitado.
            // ------------------------------------------------

            StyledText {
                text:
                    qsTr("Quick controls")

                font:
                    Tokens.font.title.medium
            }


            // ------------------------------------------------
            // KEYBOARD
            // ------------------------------------------------

            StyledRect {
                id: keyboardRow

                Layout.fillWidth: true

                implicitHeight: 44

                radius:
                    Tokens.rounding.full

                color:
                    keyboardMouse.containsMouse
                        ? Colours.palette.m3surfaceContainerHighest
                        : Colours.tPalette.m3surfaceContainer

                Behavior on color {
                    CAnim {}
                }


                RowLayout {
                    anchors.fill: parent

                    anchors.leftMargin:
                        Tokens.padding.medium

                    anchors.rightMargin:
                        Tokens.padding.medium

                    spacing:
                        Tokens.spacing.small


                    MaterialIcon {
                        text: "keyboard"

                        color:
                            Colours.palette.m3onSurfaceVariant
                    }


                    StyledText {
                        text:
                            qsTr("Keyboard")

                        font:
                            Tokens.font.label.medium
                    }


                    Item {
                        Layout.fillWidth: true
                    }


                    StyledText {
                        text:
                            qsTr("Super + Space")

                        color:
                            Colours.palette.m3onSurfaceVariant

                        font:
                            Tokens.font.body.small
                    }


                    StyledRect {
                        implicitWidth: 42
                        implicitHeight: 26

                        radius:
                            Tokens.rounding.full

                        color:
                            Colours.palette.m3secondaryContainer


                        StyledText {
                            anchors.centerIn: parent

                            text:
                                Hypr.kbLayout.toUpperCase()

                            color:
                                Colours.palette.m3onSecondaryContainer

                            font:
                                Tokens.font.mono.medium
                        }
                    }
                }


                SequentialAnimation {
                    id: keyboardPulse

                    NumberAnimation {
                        target: keyboardRow
                        property: "scale"

                        from: 1
                        to: 0.97

                        duration: 65
                    }

                    NumberAnimation {
                        target: keyboardRow
                        property: "scale"

                        from: 0.97
                        to: 1

                        duration: 110

                        easing.type:
                            Easing.OutBack
                    }
                }


                MouseArea {
                    id: keyboardMouse

                    anchors.fill: parent

                    hoverEnabled: true

                    cursorShape:
                        Qt.PointingHandCursor

                    onClicked: {
                        keyboardPulse.restart();

                        Quickshell.execDetached([
                            "hyprctl",
                            "switchxkblayout",
                            "all",
                            "next"
                        ]);
                    }
                }
            }


            // ------------------------------------------------
            // SYSTEM
            // ------------------------------------------------

            StyledText {
                text:
                    qsTr("System")

                color:
                    Colours.palette.m3onSurfaceVariant

                font:
                    Tokens.font.label.medium
            }


            GridLayout {
                Layout.fillWidth: true

                columns: 3

                columnSpacing:
                    Tokens.spacing.small

                rowSpacing:
                    Tokens.spacing.small


                QuickControl {
                    Layout.fillWidth: true

                    icon:
                        Audio.sourceMuted
                            ? "mic_off"
                            : "mic"

                    label:
                        qsTr("Mic")

                    active:
                        !Audio.sourceMuted

                    onActivated: {
                        const audio =
                            Audio.source?.audio;

                        if (audio)
                            audio.muted =
                                !audio.muted;
                    }
                }


                QuickControl {
                    Layout.fillWidth: true

                    icon:
                        root.nightLightEnabled
                            ? "nightlight"
                            : "light_mode"

                    label:
                        qsTr("Night")

                    active:
                        root.nightLightEnabled

                    onActivated:
                        root.toggleNightLight()
                }


                QuickControl {
                    Layout.fillWidth: true

                    icon:
                        "sports_esports"

                    label:
                        qsTr("Game")

                    active:
                        GameMode.enabled

                    showIndicator:
                        GameMode.enabled

                    onActivated:
                        GameMode.enabled =
                            !GameMode.enabled
                }


                QuickControl {
                    Layout.fillWidth: true

                    icon:
                        Notifs.dnd
                            ? "notifications_off"
                            : "notifications"

                    label:
                        qsTr("DND")

                    active:
                        Notifs.dnd

                    onActivated:
                        Notifs.dnd =
                            !Notifs.dnd
                }


                QuickControl {
                    Layout.fillWidth: true

                    icon:
                        root.keepAwakeEnabled
                            ? "coffee"
                            : "bedtime"

                    label:
                        qsTr("Awake")

                    active:
                        root.keepAwakeEnabled

                    onActivated:
                        root.toggleAwake()
                }


                QuickControl {
                    Layout.fillWidth: true

                    icon:
                        "settings"

                    label:
                        qsTr("Settings")

                    onActivated: {
                        root.popouts.hasCurrent = false;
                        WindowFactory.create();
                    }
                }
            }


            // ------------------------------------------------
            // SCREEN RECORDING
            //
            // Entrada maior porque leva para uma interface
            // completa, não é somente um toggle.
            // ------------------------------------------------

            StyledRect {
                id: recorderRow

                Layout.fillWidth: true
                Layout.bottomMargin: Tokens.spacing.small

                implicitHeight: 58

                
                clip: true
radius:
                    Tokens.rounding.large

                color:
                    recorderMouse.containsMouse
                        ? Colours.palette.m3surfaceContainerHighest
                        : Colours.tPalette.m3surfaceContainer

                Behavior on color {
                    CAnim {}
                }


                RowLayout {
                    anchors.fill: parent

                    anchors.leftMargin:
                        Tokens.padding.medium

                    anchors.rightMargin:
                        Tokens.padding.medium

                    spacing:
                        Tokens.spacing.small


                    StyledRect {
                        implicitWidth: 36
                        implicitHeight: 36

                        radius:
                            Tokens.rounding.full

                        color:
                            Colours.palette.m3secondaryContainer


                        MaterialIcon {
                            anchors.centerIn: parent

                            text:
                                "screen_record"

                            color:
                                Colours.palette.m3onSecondaryContainer
                        }
                    }


                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0

                        spacing: 0


                        StyledText {
                            text:
                                qsTr("Screen recording")

                            font:
                                Tokens.font.label.medium

                        elide: Text.ElideRight
                        maximumLineCount: 1
                        }


                        StyledText {
                            text:
                                qsTr("Fullscreen, region & audio")

                            color:
                                Colours.palette.m3onSurfaceVariant

                            font:
                                Tokens.font.body.small

                        elide: Text.ElideRight
                        maximumLineCount: 1
                        }
                    }


                    MaterialIcon {
                        text:
                            "chevron_right"

                        color:
                            Colours.palette.m3onSurfaceVariant
                    }
                }


                MouseArea {
                    id: recorderMouse

                    anchors.fill: parent

                    hoverEnabled: true

                    cursorShape:
                        Qt.PointingHandCursor

                    onClicked: {
                        if (root.screenState === null) {
                            console.warn(
                                "[QuickControls] screenState unavailable"
                            );
                            return;
                        }

                        root.page = "recorder";
                    }
                }
            }
        }
    }


    // ========================================================
    // RECORDER PAGE
    //
    // Usa o componente ORIGINAL do Caelestia.
    // ========================================================

    Component {
        id: recorderPage

        ColumnLayout {
            width: root.implicitWidth

            spacing:
                Tokens.spacing.medium


            RowLayout {
                Layout.fillWidth: true

                spacing:
                    Tokens.spacing.small


                StyledRect {
                    id: recorderBack

                    implicitWidth: 38
                    implicitHeight: 38

                    radius:
                        Tokens.rounding.full

                    color:
                        recorderBackMouse.containsMouse
                            ? Colours.palette.m3surfaceContainerHighest
                            : Colours.tPalette.m3surfaceContainer


                    MaterialIcon {
                        anchors.centerIn: parent

                        text:
                            "arrow_back"

                        color:
                            Colours.palette.m3onSurface
                    }


                    MouseArea {
                        id: recorderBackMouse

                        anchors.fill: parent

                        hoverEnabled: true

                        cursorShape:
                            Qt.PointingHandCursor

                        onClicked:
                            root.page = "home"
                    }
                }


                StyledText {
                    Layout.fillWidth: true

                    text:
                        qsTr("Screen recording")

                    font:
                        Tokens.font.title.medium
                }
            }


            // =================================================
            // O CARD NATIVO.
            //
            // Fullscreen / região / áudio / recordings list
            // continuam pertencendo ao upstream.
            // =================================================

            UtilityCards.Record {
                Layout.fillWidth: true

                props:
                    root.recorderProps

                screenState:
                    root.screenState
            }

            // HYBRID_RECORDER_DROPDOWN_RESERVE
            //
            // O seletor nativo de modo do recorder abre para baixo.
            // Reservamos espaço dentro do MESMO popout para que:
            //
            // - Record fullscreen
            // - Record region
            // - Record fullscreen with sound
            // - Record region with sound
            //
            // apareçam integralmente.
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 96
            }

        }
    }


    // ========================================================
    // QUICK CONTROL
    // ========================================================

    component QuickControl: StyledRect {
        id: control

        required property string icon
        required property string label

        property bool active: false
        property bool showIndicator: false

        signal activated()

        implicitHeight: 62

        radius:
            Tokens.rounding.large

        transformOrigin:
            Item.Center

        color: {
            if (controlMouse.containsMouse)
                return Colours.palette.m3surfaceContainerHighest;

            if (control.active)
                return Colours.palette.m3secondaryContainer;

            return Colours.tPalette.m3surfaceContainer;
        }


        Behavior on color {
            ColorAnimation {
                duration: 160
            }
        }


        ColumnLayout {
            anchors.centerIn: parent

            spacing: 2


            MaterialIcon {
                Layout.alignment:
                    Qt.AlignHCenter

                animate: true

                text:
                    control.icon

                fill:
                    control.active
                        ? 1
                        : 0

                color:
                    control.active
                        ? Colours.palette.m3onSecondaryContainer
                        : Colours.palette.m3onSurfaceVariant
            }


            StyledText {
                Layout.alignment:
                    Qt.AlignHCenter

                text:
                    control.label

                color:
                    control.active
                        ? Colours.palette.m3onSecondaryContainer
                        : Colours.palette.m3onSurfaceVariant

                font:
                    Tokens.font.label.small
            }
        }


        StyledRect {
            visible:
                control.showIndicator

            anchors.right:
                parent.right

            anchors.top:
                parent.top

            anchors.rightMargin: 8
            anchors.topMargin: 8

            implicitWidth: 6
            implicitHeight: 6

            radius: 3

            color:
                Colours.palette.m3primary
        }


        SequentialAnimation {
            id: pulse

            NumberAnimation {
                target: control
                property: "scale"

                from: 1
                to: 0.86

                duration: 65
            }

            NumberAnimation {
                target: control
                property: "scale"

                from: 0.86
                to: 1

                duration: 115

                easing.type:
                    Easing.OutBack
            }
        }


        MouseArea {
            id: controlMouse

            anchors.fill: parent

            hoverEnabled: true

            cursorShape:
                Qt.PointingHandCursor

            onClicked: {
                pulse.restart();
                control.activated();
            }
        }
    }
}
