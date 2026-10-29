#!/usr/bin/env bash
# =============================================================================
# Redshift Store — Launcher Script
# =============================================================================
# Dispatches execution to the Redshift Store application (main.py).
# Supports source resolution across user directory (~/.local/share),
# system installation (/usr/share) and repository clone.
# Supports REDSHIFT_STORE_SOURCE ('user', 'system', 'repo') override.
# When multiple copies exist, selects based on structural integrity
# and semantic/ALPM version (VERSION in main.py) without depending on mtime.
# Logs the chosen main.py path and version deterministically.
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
LOCAL_MAIN="${SCRIPT_DIR}/main.py"
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

MAIN_PY=""

case "${REDSHIFT_STORE_SOURCE:-}" in
    user)
        if _is_valid_store_dir "$INSTALLED_MAIN"; then
            MAIN_PY="$INSTALLED_MAIN"
        else
            printf "Error: REDSHIFT_STORE_SOURCE=user requested, but %s is invalid or not found.\n" "$INSTALLED_MAIN" >&2
            exit 1
        fi
        ;;
    system)
        if _is_valid_store_dir "$SYSTEM_MAIN"; then
            MAIN_PY="$SYSTEM_MAIN"
        else
            printf "Error: REDSHIFT_STORE_SOURCE=system requested, but %s is invalid or not found.\n" "$SYSTEM_MAIN" >&2
            exit 1
        fi
        ;;
    repo)
        if _is_valid_store_dir "$LOCAL_MAIN"; then
            MAIN_PY="$LOCAL_MAIN"
        elif _is_valid_store_dir "$RELATIVE_MAIN"; then
            MAIN_PY="$RELATIVE_MAIN"
        else
            printf "Error: REDSHIFT_STORE_SOURCE=repo requested, but neither %s nor %s is valid.\n" "$LOCAL_MAIN" "$RELATIVE_MAIN" >&2
            exit 1
        fi
        ;;
    "")
        # Deterministic coexistence resolution across all discovered candidates
        candidates=()
        [[ -f "$INSTALLED_MAIN" ]] && candidates+=("$INSTALLED_MAIN")
        [[ -f "$LOCAL_MAIN" && "$LOCAL_MAIN" != "$INSTALLED_MAIN" ]] && candidates+=("$LOCAL_MAIN")
        [[ -f "$RELATIVE_MAIN" && "$RELATIVE_MAIN" != "$INSTALLED_MAIN" && "$RELATIVE_MAIN" != "$LOCAL_MAIN" ]] && candidates+=("$RELATIVE_MAIN")
        [[ -f "$SYSTEM_MAIN" ]] && candidates+=("$SYSTEM_MAIN")

        best_cand=""
        best_ver="0.0.0"

        for cand in "${candidates[@]}"; do
            if _is_valid_store_dir "$cand"; then
                cand_ver="$(_extract_version "$cand")"
                if [[ -z "$best_cand" ]]; then
                    best_cand="$cand"
                    best_ver="$cand_ver"
                else
                    cmp_res="$(_compare_versions "$cand_ver" "$best_ver")"
                    if (( cmp_res > 0 )); then
                        best_cand="$cand"
                        best_ver="$cand_ver"
                    fi
                fi
            fi
        done

        if [[ -n "$best_cand" ]]; then
            MAIN_PY="$best_cand"
        else
            printf "Error: Redshift Store main.py not found at any known location:\n  - %s\n  - %s\n  - %s\n  - %s\n" \
                "$INSTALLED_MAIN" "$LOCAL_MAIN" "$RELATIVE_MAIN" "$SYSTEM_MAIN" >&2
            exit 1
        fi
        ;;
    *)
        printf "Error: Invalid REDSHIFT_STORE_SOURCE='%s' (valid values: user, system, repo).\n" "$REDSHIFT_STORE_SOURCE" >&2
        exit 1
        ;;
esac

CHOSEN_VER="$(_extract_version "$MAIN_PY")"
echo "[redshift-store launcher] Resolved main.py: ${MAIN_PY} (version: ${CHOSEN_VER})" >&2
if command -v logger >/dev/null 2>&1; then
    logger -t redshift-store-launcher "Resolved main.py: ${MAIN_PY} (version: ${CHOSEN_VER})" || true
fi

exec python3 "$MAIN_PY" "$@"
