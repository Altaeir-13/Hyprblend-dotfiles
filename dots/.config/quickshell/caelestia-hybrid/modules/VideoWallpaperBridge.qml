import QtQuick
import Quickshell.Io

Item {
    id: root

    visible: false
    width: 0
    height: 0

    Process {
        id: videoWallpaperBridge

        running: true

        command: [
            "bash",
            "-lc",
            "exec \"${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/caelestia-hybrid/scripts/video-wallpaper-sync.sh\" watch"
        ]
    }
}
