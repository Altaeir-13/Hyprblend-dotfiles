#!/usr/bin/env bash
# =============================================================================
# Redshift Store — Launcher Script
# =============================================================================
# Dispatches execution to the Redshift Store application (main.py).
# Supports source resolution across user directory (~/.local/share),
# system installation (/usr/share) and repository clone.
# Supports REDSHIFT_STORE_SOURCE ('user', 'system', 'repo') override.
# When both user and system copies exist, selects based on structural integrity
# and ALPM/semantic version (VERSION in main.py) without depending on mtime.
# =============================================================================

set -euo pipefail

export XDG_BIN_HOME="${XDG_BIN_HOME:-$HOME/.local/bin}"
case ":${PATH:-}:" in
    *":${XDG_BIN_HOME}:"*) ;;
    *) export PATH="${XDG_BIN_HOME}:${PATH:-/usr/local/sbin:/usr/local/bin:/usr/bin}" ;;
esac

XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
INSTALLED_MAIN="${XDG_DATA_HOME}/redshift-os/redshift-store/main.py"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELATIVE_MAIN="$(cd "${SCRIPT_DIR}/../share/redshift-os/redshift-store" 2>/dev/null && pwd || true)/main.py"
SYSTEM_MAIN="${REDSHIFT_STORE_SYSTEM_MAIN:-/usr/share/redshift-os/redshift-store/main.py}"

_is_valid_store_dir() {
    local main_py="$1"
    [[ -n "$main_py" && -f "$main_py" ]] || return 1
    local dir
    dir="$(dirname "$main_py")"
    [[ -f "$dir/backend/__init__.py" && -f "$dir/qml/Main.qml" ]]
}

_extract_version() {
    local main_py="$1"
    local ver="0.0.0"
    if [[ -f "$main_py" ]]; then
        local parsed
        parsed="$(sed -nE 's/^[[:space:]]*VERSION[[:space:]]*=[[:space:]]*["'"'"']([^"'"'"']+)["'"'"'].*$/\1/p' "$main_py" | head -n 1)"
        if [[ -n "$parsed" ]]; then
            ver="$parsed"
        fi
    fi
    printf "%s\n" "$ver"
}

_compare_versions() {
    local v1="$1"
    local v2="$2"
    if command -v vercmp >/dev/null 2>&1; then
        vercmp "$v1" "$v2"
        return 0
    fi
    if [[ "$v1" == "$v2" ]]; then
        echo "0"
        return 0
    fi
    local ep1=0 ep2=0 r1="$v1" r2="$v2"
    if [[ "$v1" == *:* ]]; then
        ep1="${v1%%:*}"
        r1="${v1#*:}"
    fi
    if [[ "$v2" == *:* ]]; then
        ep2="${v2%%:*}"
        r2="${v2#*:}"
    fi
    if (( ep1 < ep2 )); then
        echo "-1"
        return 0
    elif (( ep1 > ep2 )); then
        echo "1"
        return 0
    fi
    local lowest
    lowest="$(printf "%s\n%s\n" "$r1" "$r2" | sort -V | head -n 1)"
    if [[ "$lowest" == "$r1" && "$lowest" != "$r2" ]]; then
        echo "-1"
    elif [[ "$lowest" == "$r2" && "$lowest" != "$r1" ]]; then
        echo "1"
    else
        echo "0"
    fi
}

_resolve_coexistence() {
    local usr_valid=0 sys_valid=0
    if _is_valid_store_dir "$INSTALLED_MAIN"; then usr_valid=1; fi
    if _is_valid_store_dir "$SYSTEM_MAIN"; then sys_valid=1; fi

    if (( usr_valid && !sys_valid )); then
        MAIN_PY="$INSTALLED_MAIN"
    elif (( !usr_valid && sys_valid )); then
        MAIN_PY="$SYSTEM_MAIN"
    elif (( usr_valid && sys_valid )); then
        local sys_ver usr_ver cmp_res
        sys_ver="$(_extract_version "$SYSTEM_MAIN")"
        usr_ver="$(_extract_version "$INSTALLED_MAIN")"
        cmp_res="$(_compare_versions "$sys_ver" "$usr_ver")"
        if (( cmp_res > 0 )); then
            MAIN_PY="$SYSTEM_MAIN"
        else
            MAIN_PY="$INSTALLED_MAIN"
        fi
    else
        MAIN_PY=""
    fi
}

MAIN_PY=""

case "${REDSHIFT_STORE_SOURCE:-}" in
    user)
        if [[ -f "$INSTALLED_MAIN" ]]; then
            MAIN_PY="$INSTALLED_MAIN"
        else
            printf "Error: REDSHIFT_STORE_SOURCE=user requested, but %s not found.\n" "$INSTALLED_MAIN" >&2
            exit 1
        fi
        ;;
    system)
        if [[ -f "$SYSTEM_MAIN" ]]; then
            MAIN_PY="$SYSTEM_MAIN"
        else
            printf "Error: REDSHIFT_STORE_SOURCE=system requested, but %s not found.\n" "$SYSTEM_MAIN" >&2
            exit 1
        fi
        ;;
    repo)
        if [[ -f "$RELATIVE_MAIN" ]]; then
            MAIN_PY="$RELATIVE_MAIN"
        else
            printf "Error: REDSHIFT_STORE_SOURCE=repo requested, but %s not found.\n" "$RELATIVE_MAIN" >&2
            exit 1
        fi
        ;;
    "")
        # Automatic coexistence resolution between user and system installations
        if [[ -f "$INSTALLED_MAIN" && -f "$SYSTEM_MAIN" ]]; then
            _resolve_coexistence
        elif [[ -f "$INSTALLED_MAIN" ]]; then
            MAIN_PY="$INSTALLED_MAIN"
        elif [[ -f "$SYSTEM_MAIN" ]]; then
            MAIN_PY="$SYSTEM_MAIN"
        elif [[ -f "$RELATIVE_MAIN" ]]; then
            MAIN_PY="$RELATIVE_MAIN"
        fi

        if [[ -z "$MAIN_PY" ]]; then
            printf "Error: Redshift Store main.py not found at:\n  - %s\n  - %s\n  - %s\n" "$INSTALLED_MAIN" "$RELATIVE_MAIN" "$SYSTEM_MAIN" >&2
            exit 1
        fi
        ;;
    *)
        printf "Error: Invalid REDSHIFT_STORE_SOURCE='%s' (valid values: user, system, repo).\n" "$REDSHIFT_STORE_SOURCE" >&2
        exit 1
        ;;
esac

CHOSEN_VER="$(_extract_version "$MAIN_PY")"
if [[ "${REDSHIFT_STORE_DEBUG:-0}" == "1" ]]; then
    echo "[redshift-store launcher] Resolved main.py: ${MAIN_PY} (version: ${CHOSEN_VER})" >&2
fi
if command -v logger >/dev/null 2>&1; then
    logger -t redshift-store-launcher "Resolved main.py: ${MAIN_PY} (version: ${CHOSEN_VER})" 2>/dev/null || true
fi

exec python3 "$MAIN_PY" "$@"
