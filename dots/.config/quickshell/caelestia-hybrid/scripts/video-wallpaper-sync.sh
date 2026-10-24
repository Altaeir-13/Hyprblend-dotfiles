#!/usr/bin/env bash

set -u

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

II_CONFIG="$XDG_CONFIG_HOME/illogical-impulse/config.json"
CAEL_CONFIG="$XDG_CONFIG_HOME/caelestia/shell.json"

BRIDGE="$XDG_CONFIG_HOME/quickshell/caelestia-hybrid/scripts/end4-theme-bridge.sh"

STATE_DIR="$XDG_STATE_HOME/quickshell/ui-switch"
PID_FILE="${VIDEO_PID_FILE:-$STATE_DIR/video-bridge.pid}"
LOG="${VIDEO_BRIDGE_LOG:-/tmp/caelestia-video-wallpaper.log}"

PARENT_PID="${VIDEO_BRIDGE_PARENT_PID:-$PPID}"

last_wall=""
mpv_pid=""


log() {
    printf '[%s] %s\n' \
        "$(date '+%H:%M:%S')" \
        "$*" \
        >> "$LOG"
}


get_wallpaper() {
    jq -r \
        '.background.wallpaperPath // empty' \
        "$II_CONFIG" \
        2>/dev/null \
        || true
}


normalise_path() {
    local path="$1"

    path="${path#file://}"

    printf '%s\n' "$path"
}


is_video() {
    local path="$1"

    case "${path,,}" in
        *.mp4|*.webm|*.mkv|*.mov|*.m4v|*.avi|*.gif)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}


set_caelestia_wallpaper_enabled() {
    local enabled="$1"

    python3 - "$enabled" <<'PY'
from pathlib import Path
import json
import os
import sys

enabled = sys.argv[1].lower() == "true"

config_home = Path(os.environ.get("XDG_CONFIG_HOME") or (Path.home() / ".config"))
p = config_home / "caelestia/shell.json"

if p.exists() and p.read_text().strip():
    try:
        data = json.loads(p.read_text())
    except Exception:
        data = {}
else:
    data = {}

background = data.setdefault("background", {})

if background.get("wallpaperEnabled") == enabled:
    raise SystemExit(0)

background["wallpaperEnabled"] = enabled

p.parent.mkdir(
    parents=True,
    exist_ok=True
)

p.write_text(
    json.dumps(
        data,
        indent=4,
        ensure_ascii=False
    ) + "\n"
)
PY
}


stop_our_mpvpaper() {
    if [[ -n "${mpv_pid:-}" ]]; then
        if kill -0 "$mpv_pid" 2>/dev/null; then
            kill "$mpv_pid" 2>/dev/null || true
            wait "$mpv_pid" 2>/dev/null || true
        fi

        mpv_pid=""
    fi
}


stop_wallpaper_players() {
    stop_our_mpvpaper

    # Durante o Caelestia nós assumimos controle do backend
    # mpvpaper. Isso remove uma instância deixada pelo end-4
    # para evitar dois vídeos tocando simultaneamente.
    pkill -x mpvpaper 2>/dev/null || true

    sleep 0.15
}


start_video() {
    local path="$1"

    stop_wallpaper_players

    log "Starting video: $path"

    mpvpaper \
        -p \
        -o "no-audio --loop-file=inf --panscan=1 --hwdec=auto-safe" \
        ALL \
        "$path" \
        >>"$LOG" 2>&1 &

    mpv_pid="$!"
}


sync_wallpaper() {
    local raw
    local wall

    raw="$(get_wallpaper)"
    wall="$(normalise_path "$raw")"

    if [[ -z "$wall" ]]; then
        return
    fi

    if [[ "$wall" == "$last_wall" ]]; then

        # Se deveria haver vídeo mas o processo morreu,
        # recupera automaticamente.
        if is_video "$wall"; then
            if [[ -z "${mpv_pid:-}" ]] \
                || ! kill -0 "$mpv_pid" 2>/dev/null
            then
                set_caelestia_wallpaper_enabled false
                start_video "$wall"
            fi
        fi

        return
    fi

    log "Wallpaper changed: $wall"

    # Mantém cores/tema do híbrido sincronizados com end-4.
    if [[ -x "$BRIDGE" ]]; then
        "$BRIDGE" >>"$LOG" 2>&1 || true
    fi


    if is_video "$wall"; then

        if [[ ! -f "$wall" ]]; then
            log "Video does not exist: $wall"
            return
        fi

        # O background estático do Caelestia fica transparente,
        # deixando o mpvpaper aparecer atrás do frame/blob.
        set_caelestia_wallpaper_enabled false

        start_video "$wall"

    else

        # Voltando para uma imagem comum.
        stop_wallpaper_players

        set_caelestia_wallpaper_enabled true

        log "Static wallpaper mode"
    fi

    last_wall="$wall"
}


cleanup() {
    log "Caelestia video bridge stopping"

    stop_our_mpvpaper

    if [[ -f "$PID_FILE" ]] && [[ "$(head -n 1 "$PID_FILE" 2>/dev/null || true)" == "$$" ]]; then
        rm -f "$PID_FILE"
    fi
}

trap cleanup EXIT INT TERM


case "${1:-watch}" in

    once)
        sync_wallpaper
        ;;

    watch)
        mkdir -p "$STATE_DIR"
        if [[ -f "$PID_FILE" ]]; then
            old_pid="$(head -n 1 "$PID_FILE" 2>/dev/null | tr -d '[:space:]' || true)"
            if [[ -n "$old_pid" && "$old_pid" != "$$" ]] && kill -0 "$old_pid" 2>/dev/null; then
                kill "$old_pid" 2>/dev/null || true
            fi
        fi
        printf '%s\n' "$$" > "$PID_FILE"

        : > "$LOG"

        log "Video wallpaper bridge started"

        sync_wallpaper

        while kill -0 "$PARENT_PID" 2>/dev/null; do
            sleep 1
            sync_wallpaper
        done
        ;;

    *)
        echo "Uso: $0 watch|once"
        exit 2
        ;;
esac
