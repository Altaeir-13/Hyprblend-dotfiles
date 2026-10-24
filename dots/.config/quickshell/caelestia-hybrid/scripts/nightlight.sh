#!/usr/bin/env bash
set -euo pipefail

get_temp() {
    hyprctl hyprsunset temperature 2>/dev/null \
        | grep -oE '[0-9]+' \
        | head -n1 || true
}

get_status() {
    local t
    t="$(get_temp)"
    if [[ -n "${t:-}" ]] && [[ "$t" -lt 6000 ]]; then
        echo on
    else
        echo off
    fi
}

case "${1:-status}" in
    status)
        get_status
        ;;
    toggle)
        if [[ "$(get_status)" == "on" ]]; then
            hyprctl hyprsunset temperature 6500 >/dev/null 2>&1 \
                || hyprctl hyprsunset identity >/dev/null 2>&1 \
                || true
        else
            hyprctl hyprsunset temperature 4500 >/dev/null 2>&1 || true
        fi

        sleep 0.15
        get_status
        ;;
    on)
        hyprctl hyprsunset temperature 4500 >/dev/null 2>&1 || true
        ;;
    off)
        hyprctl hyprsunset temperature 6500 >/dev/null 2>&1 \
            || hyprctl hyprsunset identity >/dev/null 2>&1 \
            || true
        ;;
esac
