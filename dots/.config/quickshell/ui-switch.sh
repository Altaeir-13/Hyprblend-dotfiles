#!/usr/bin/env bash

set -euo pipefail

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"

CAEL_CONFIG="$XDG_CONFIG_HOME/quickshell/caelestia-hybrid"
BRIDGE="$CAEL_CONFIG/scripts/end4-theme-bridge.sh"

STATE_DIR="$XDG_STATE_HOME/quickshell/ui-switch"
STATE_FILE="$STATE_DIR/current"
LOCK_FILE="$STATE_DIR/switch.lock"
VIDEO_PID_FILE="$STATE_DIR/video-bridge.pid"

END4_LOG="${END4_LOG:-/tmp/quickshell-ii.log}"
CAEL_LOG="${CAEL_LOG:-/tmp/caelestia-hybrid.log}"
HYPR_LOG="${HYPR_LOG:-/tmp/hypr-ui-switch-reload.log}"

UI_SWITCH_WAIT_ITERS="${UI_SWITCH_WAIT_ITERS:-80}"
UI_SWITCH_WAIT_SLEEP="${UI_SWITCH_WAIT_SLEEP:-0.1}"
UI_SWITCH_STABILITY_SLEEP="${UI_SWITCH_STABILITY_SLEEP:-1}"

# Ensure HYPRLAND_INSTANCE_SIGNATURE is set if Hyprland is active
if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    _rt="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    if [[ -d "$_rt/hypr" ]]; then
        _sig="$(ls -t "$_rt/hypr" 2>/dev/null | head -n 1 || true)"
        if [[ -n "$_sig" ]]; then
            export HYPRLAND_INSTANCE_SIGNATURE="$_sig"
        fi
    fi
    unset _rt _sig
fi

mkdir -p "$STATE_DIR"


notify_user() {
    local urgency="${1:-normal}"
    local title="$2"
    local body="$3"

    if command -v notify-send >/dev/null 2>&1; then
        notify-send -u "$urgency" -a "Hybrid Rice" "$title" "$body" >/dev/null 2>&1 || true
    fi
}


release_switch_lock() {
    if command -v flock >/dev/null 2>&1; then
        flock -u 9 2>/dev/null || true
        exec 9>&-
    fi
}


acquire_switch_lock() {
    if command -v flock >/dev/null 2>&1; then
        exec 9>"$LOCK_FILE"
        if ! flock -n 9; then
            echo "Transição de interface já está em andamento."
            exit 0
        fi
        trap release_switch_lock EXIT INT TERM
    fi
}


stop_video_bridge() {
    if [[ -f "$VIDEO_PID_FILE" ]]; then
        local vpid
        vpid="$(head -n 1 "$VIDEO_PID_FILE" 2>/dev/null | tr -d '[:space:]' || true)"
        if [[ -n "$vpid" ]] && kill -0 "$vpid" 2>/dev/null; then
            kill "$vpid" 2>/dev/null || true
        fi
        rm -f "$VIDEO_PID_FILE"
    fi
}


# -----------------------------------------------------------------------------
# Verificações de Três Níveis para Caelestia
# -----------------------------------------------------------------------------

# Nível 1 — Instalação:
# Confirma se o módulo QML existe e possui qmldir e biblioteca .so presentes e legíveis.
resolve_caelestia_plugin_dir() {
    local candidate
    local -a candidates=()

    if [[ -n "${CAELESTIA_QML_PATH:-}" ]]; then
        candidates+=("$CAELESTIA_QML_PATH")
    fi

    if [[ "${CAELESTIA_QML_ONLY:-false}" != "true" ]]; then
        candidates+=(
            "/usr/lib/qt6/qml"
            "/usr/local/lib/qt6/qml"
            "$XDG_DATA_HOME/quickshell/qml"
            "$HOME/.local/lib/qt6/qml"
        )
    fi

    for candidate in "${candidates[@]}"; do
        if [[ -n "$candidate" && -d "$candidate/Caelestia" ]]; then
            # Confirmar se Caelestia/qmldir existe e é legível
            if [[ -f "$candidate/Caelestia/qmldir" && -r "$candidate/Caelestia/qmldir" ]]; then
                # Confirmar se a biblioteca nativa .so está presente e legível
                if find_caelestia_plugin_so "$candidate" >/dev/null; then
                    printf '%s\n' "$candidate"
                    return 0
                fi
            fi
        fi
    done

    return 1
}

find_caelestia_plugin_so() {
    local base_dir="$1"
    if [[ -f "$base_dir/Caelestia/libcaelestia-coreplugin.so" && -r "$base_dir/Caelestia/libcaelestia-coreplugin.so" ]]; then
        printf '%s\n' "$base_dir/Caelestia/libcaelestia-coreplugin.so"
        return 0
    elif [[ -f "$base_dir/Caelestia/lib/libcaelestia-core.so" && -r "$base_dir/Caelestia/lib/libcaelestia-core.so" ]]; then
        printf '%s\n' "$base_dir/Caelestia/lib/libcaelestia-core.so"
        return 0
    fi

    local any_so
    any_so="$(find "$base_dir/Caelestia" -maxdepth 2 -type f -name "*.so*" 2>/dev/null | head -n 1 || true)"
    if [[ -n "$any_so" && -r "$any_so" ]]; then
        printf '%s\n' "$any_so"
        return 0
    fi
    return 1
}

# Nível 1: Validação com feedback formal
check_caelestia_installation() {
    local plugin_dir
    if ! plugin_dir="$(resolve_caelestia_plugin_dir)"; then
        local msg="Instalação incompleta ou ausente: plugin nativo Caelestia não encontrado. Execute 'redshift-doctor --check caelestia'."
        echo "ERRO: $msg" >&2
        notify_user "critical" "Instalação Caelestia Incompleta" "$msg"
        return 1
    fi
    printf '%s\n' "$plugin_dir"
    return 0
}

# Nível 2 — Compatibilidade:
# Confirma se a biblioteca nativa .so não possui símbolos não-resolvidos nem incompatibilidade de linker com o Qt6 instalado
check_caelestia_compatibility() {
    local plugin_dir="$1"
    local so_file
    if ! so_file="$(find_caelestia_plugin_so "$plugin_dir")"; then
        local msg="Instalação incompleta ou ausente: plugin nativo Caelestia não encontrado. Execute 'redshift-doctor --check caelestia'."
        echo "ERRO: $msg" >&2
        notify_user "critical" "Instalação Caelestia Incompleta" "$msg"
        return 1
    fi

    if command -v ldd >/dev/null 2>&1; then
        local ldd_out
        ldd_out="$(ldd -r "$so_file" 2>&1 || true)"
        if echo "$ldd_out" | grep -iE "undefined symbol|not found" >/dev/null; then
            local msg="Incompatibilidade detectada entre Caelestia e Qt6/Quickshell. Execute 'redshift-doctor --repair caelestia'."
            echo "ERRO: $msg" >&2
            echo "Detalhes do linker (ldd -r):" >&2
            echo "$ldd_out" | grep -iE "undefined symbol|not found" | head -n 20 >&2
            notify_user "critical" "Incompatibilidade Caelestia / Qt6" "$msg"
            return 2
        fi
    fi

    return 0
}


running_end4() {
    qs list --all 2>/dev/null \
        | grep -Fq "/quickshell/ii/shell.qml"
}


running_caelestia() {
    qs list --all 2>/dev/null \
        | grep -Fq "/quickshell/caelestia-hybrid/shell.qml"
}


wait_end4() {
    for _ in $(seq 1 "$UI_SWITCH_WAIT_ITERS"); do
        running_end4 && return 0
        sleep "$UI_SWITCH_WAIT_SLEEP"
    done

    return 1
}


wait_caelestia() {
    for _ in $(seq 1 "$UI_SWITCH_WAIT_ITERS"); do
        running_caelestia && return 0
        sleep "$UI_SWITCH_WAIT_SLEEP"
    done

    return 1
}


set_frontend_state() {
    local frontend="$1"

    printf '%s\n' "$frontend" > "$STATE_FILE"

    if ! hyprctl reload >"$HYPR_LOG" 2>&1; then
        echo
        echo "ERRO: Hyprland recusou o reload para '$frontend':"
        cat "$HYPR_LOG"
        return 1
    fi
}


start_end4_process() {
    if running_end4; then
        return 0
    fi

    setsid -f \
        qs -c ii 9>&- \
        >"$END4_LOG" 2>&1

    if ! wait_end4; then
        echo "ERRO: end-4 não iniciou."
        tail -n 80 "$END4_LOG" 2>/dev/null || true
        return 1
    fi
}


start_caelestia_process() {
    if running_caelestia; then
        return 0
    fi

    local plugin_dir
    if ! plugin_dir="$(resolve_caelestia_plugin_dir)"; then
        local msg="Instalação incompleta ou ausente: plugin nativo Caelestia não encontrado. Execute 'redshift-doctor --check caelestia'."
        echo "ERRO: $msg" >&2
        notify_user "critical" "Instalação Caelestia Incompleta" "$msg"
        return 1
    fi

    # Nível 3 — Operacionalidade: Inicialização e validação de estabilidade pós-lançamento
    setsid -f env \
        QML_IMPORT_PATH="$plugin_dir${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
        QML2_IMPORT_PATH="$plugin_dir${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
        qs -c caelestia-hybrid 9>&- \
        >"$CAEL_LOG" 2>&1

    if ! wait_caelestia; then
        echo "ERRO: Caelestia não iniciou no tempo limite." >&2
        tail -n 100 "$CAEL_LOG" 2>/dev/null || true
        return 1
    fi

    # Detectar crash logo após Configuration Loaded (estabilidade pós-startup).
    sleep "$UI_SWITCH_STABILITY_SLEEP"

    if ! running_caelestia; then
        echo "ERRO: Caelestia encerrou logo após iniciar." >&2
        tail -n 100 "$CAEL_LOG" 2>/dev/null || true
        return 1
    fi
}


restore_end4() {
    qs kill -c caelestia-hybrid >/dev/null 2>&1 || true
    stop_video_bridge

    set_frontend_state end4 || true

    start_end4_process || true
}


to_caelestia() {
    echo "end-4 -> Caelestia"

    if [[ ! -f "$CAEL_CONFIG/shell.qml" ]]; then
        echo "ERRO: caelestia-hybrid não está instalado em:"
        echo "$CAEL_CONFIG"
        notify_user "normal" "Caelestia indisponível" "O perfil atual não inclui caelestia-hybrid. Mantendo end-4 ativo."
        return 1
    fi

    if [[ ! -x "$BRIDGE" ]]; then
        echo "ERRO: bridge não encontrado:"
        echo "$BRIDGE"
        notify_user "critical" "Erro na transição Caelestia" "Script end4-theme-bridge.sh não encontrado."
        return 1
    fi

    # Nível 1 — Instalação: Validar disponibilidade dos arquivos antes de parar o frontend atual.
    local plugin_dir
    if ! plugin_dir="$(check_caelestia_installation)"; then
        echo "ERRO: Abortando transição para Caelestia devido à falha de instalação (Nível 1). Mantendo end-4 ativo." >&2
        return 1
    fi

    # Nível 2 — Compatibilidade: Validar linker e símbolos Qt6 antes de parar o frontend atual.
    if ! check_caelestia_compatibility "$plugin_dir"; then
        echo "ERRO: Abortando transição para Caelestia devido à falha de compatibilidade (Nível 2). Mantendo end-4 ativo." >&2
        return 1
    fi

    # Sincronizar tema antes de matar o frontend atual.
    "$BRIDGE"

    # Limpar eventuais overrides de Game Mode do end-4 para não interferir no Caelestia
    local end4_cfg="$XDG_CONFIG_HOME/quickshell/ii/scripts/hyprland/hyprconfigurator.py"
    local shell_overrides="$XDG_CONFIG_HOME/hypr/hyprland/shellOverrides/main.lua"
    if [[ -f "$end4_cfg" ]] && [[ -f "$shell_overrides" ]]; then
        python3 "$end4_cfg" --file "$shell_overrides" \
            --reset animations:enabled \
            --reset decoration:shadow:enabled \
            --reset decoration:blur:enabled \
            --reset general:gaps_in \
            --reset general:gaps_out \
            --reset general:border_size \
            --reset decoration:rounding \
            --reset general:allow_tearing >/dev/null 2>&1 || true
    fi

    qs kill -c ii >/dev/null 2>&1 || true
    sleep "$UI_SWITCH_WAIT_SLEEP"

    # Nível 3 — Operacionalidade: Primeiro sobe o shell, porque os novos binds chamam IPC dele.
    if ! start_caelestia_process; then
        echo "ERRO: Falha operacional no Caelestia (Nível 3). Executando rollback seguro para end-4..." >&2
        notify_user "critical" "Falha ao iniciar Caelestia" "O frontend Caelestia falhou na inicialização ou encerrou inesperadamente. Rollback automático seguro executado para end-4."
        restore_end4
        return 1
    fi

    # Agora ativa os binds específicos do Caelestia.
    if ! set_frontend_state caelestia; then
        echo "Rollback para end-4..." >&2
        notify_user "critical" "Falha no reload do Hyprland" "Executando rollback automático seguro para end-4."
        restore_end4
        return 1
    fi

    echo "Caelestia ativo."
}


to_end4() {
    echo "Caelestia -> end-4"

    # Desativar Game Mode do Caelestia se ativo para não deixar gaps zerados no compositor
    if [[ -x "$CAEL_CONFIG/scripts/gamemode.sh" ]]; then
        "$CAEL_CONFIG/scripts/gamemode.sh" off >/dev/null 2>&1 || true
    fi

    qs kill -c caelestia-hybrid >/dev/null 2>&1 || true
    stop_video_bridge
    sleep "$UI_SWITCH_WAIT_SLEEP"

    if ! set_frontend_state end4; then
        echo "ERRO ao restaurar binds do end-4."
        return 1
    fi

    if ! start_end4_process; then
        echo "ERRO ao iniciar end-4."
        return 1
    fi

    echo "end-4 ativo."
}


status() {
    local e=0
    local c=0

    running_end4 && e=1
    running_caelestia && c=1

    if (( e == 1 && c == 0 )); then
        echo "end4"
    elif (( e == 0 && c == 1 )); then
        echo "caelestia"
    elif (( e == 1 && c == 1 )); then
        echo "CONFLITO"
        return 2
    else
        echo "nenhum"
        return 3
    fi
}


case "${1:-toggle}" in

    toggle)
        acquire_switch_lock
        if running_caelestia; then
            to_end4
        else
            to_caelestia
        fi
        ;;

    caelestia|cael)
        acquire_switch_lock
        if running_caelestia && ! running_end4; then
            # Mesmo se já estiver rodando, garantir estado/binds.
            set_frontend_state caelestia
            echo "Caelestia já está ativo."
        else
            qs kill -c caelestia-hybrid >/dev/null 2>&1 || true
            to_caelestia
        fi
        ;;

    end4|ii)
        acquire_switch_lock
        if running_end4 && ! running_caelestia; then
            stop_video_bridge
            set_frontend_state end4
            echo "end-4 já está ativo."
        else
            to_end4
        fi
        ;;

    status)
        status
        ;;

    *)
        echo "Uso: $0 toggle|caelestia|end4|status"
        exit 2
        ;;
esac
