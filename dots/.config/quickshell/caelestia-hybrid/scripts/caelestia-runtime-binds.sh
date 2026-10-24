#!/usr/bin/env bash
set -euo pipefail

XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
STATE="$XDG_STATE_HOME/quickshell/ui-switch/current"

mkdir -p "$(dirname "$STATE")"

case "${1:-}" in
    enable)
        printf '%s\n' caelestia > "$STATE"
        hyprctl reload
        ;;
    disable)
        printf '%s\n' end4 > "$STATE"
        hyprctl reload
        ;;
    *)
        exit 2
        ;;
esac
