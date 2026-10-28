pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import qs.services

Singleton {
    id: root

    property bool enabled: false
    property bool busy: false
    property bool _syncing: false

    readonly property string scriptPath: {
        const configHome = Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config");
        return configHome + "/quickshell/caelestia-hybrid/scripts/gamemode.sh";
    }

    function toggle() {
        root.enabled = !root.enabled;
    }

    function enable() {
        root.enabled = true;
    }

    function disable() {
        root.enabled = false;
    }

    function refresh() {
        if (!busy && !statusProc.running)
            statusProc.running = true;
    }

    onEnabledChanged: {
        if (_syncing)
            return;

        if (busy) {
            _syncing = true;
            enabled = !enabled;
            _syncing = false;
            return;
        }

        busy = true;
        const target = enabled;
        actionProc.requestedAction = target ? "enable" : "disable";
        actionProc.command = [root.scriptPath, target ? "enable" : "disable"];
        actionProc.running = true;
    }

    Process {
        id: statusProc

        command: [root.scriptPath, "status"]

        stdout: StdioCollector {
            onStreamFinished: {
                const s = text.trim();
                root._syncing = true;
                root.enabled = (s === "on");
                root._syncing = false;
            }
        }
    }

    Process {
        id: actionProc

        property string requestedAction: ""

        stdout: StdioCollector {
            onStreamFinished: {
                const s = text.trim();
                const isNowOn = (s === "on");
                root._syncing = true;
                root.enabled = isNowOn;
                root._syncing = false;

                if (actionProc.requestedAction === "enable" && isNowOn) {
                    if (GlobalConfig.utilities.toasts.gameModeChanged)
                        Toaster.toast(Tr.tr("Game mode enabled"), Tr.tr("Disabled Hyprland animations, blur, gaps and shadows"), "gamepad");
                } else if (actionProc.requestedAction === "disable" && !isNowOn) {
                    if (GlobalConfig.utilities.toasts.gameModeChanged)
                        Toaster.toast(Tr.tr("Game mode disabled"), Tr.tr("Hyprland settings restored"), "gamepad");
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            root.busy = false;
            if (exitCode !== 0) {
                statusProc.running = true;
            }
        }
    }

    Process {
        id: reapplyProc

        command: [root.scriptPath, "reapply"]
    }

    Connections {
        target: Hypr

        function onConfigReloaded() {
            if (root.enabled) {
                reapplyProc.running = true;
            } else {
                root.refresh();
            }
        }
    }

    Component.onCompleted: {
        root.refresh();
    }

    IpcHandler {
        function isEnabled(): bool {
            return root.enabled;
        }

        function toggle() {
            root.toggle();
        }

        function enable() {
            root.enable();
        }

        function disable() {
            root.disable();
        }

        target: "gameMode"
    }
}
