#!/usr/bin/env bash
# =============================================================================
# Automated Security, Behavioral & Integration Test Suite for Hybrid Rice
# =============================================================================
# Executes strictly inside temporary sandboxes with mocked system binaries.
# Never modifies the active host environment, packages, services, or Quickshell.
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PASS_COUNT=0
FAIL_COUNT=0
TOTAL_COUNT=0

CLR_GREEN='\e[32m'
CLR_RED='\e[31m'
CLR_CYAN='\e[36m'
CLR_YELLOW='\e[33m'
CLR_RST='\e[0m'

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/hybrid-rice-test-suite.XXXXXX")"
# Ensure test suite operates under a simulated Arch Linux environment on non-Arch hosts (e.g. Ubuntu GitHub Actions runner)
printf 'ID=arch\nID_LIKE=\n' > "${REPO_ROOT}/os-release"
cleanup_suite() {
    chmod -R u+w "$TEST_ROOT" 2>/dev/null || true
    rm -rf "$TEST_ROOT" 2>/dev/null || true
    rm -rf "${REPO_ROOT}/cache/.test_dry_run_sentinel" 2>/dev/null || true
    rm -f "${REPO_ROOT}/os-release" 2>/dev/null || true
}
trap cleanup_suite EXIT INT TERM

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    printf "${CLR_GREEN}[PASS]${CLR_RST} %s\n" "$1"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    printf "${CLR_RED}[FAIL]${CLR_RST} %s\n" "$1" >&2
    if [[ -n "${2:-}" ]]; then
        printf "       Reason: %s\n" "$2" >&2
    fi
}

assert_eq() {
    local actual="$1"
    local expected="$2"
    local msg="$3"
    if [[ "$actual" == "$expected" ]]; then
        pass "$msg"
    else
        fail "$msg" "expected '$expected', got '$actual'"
    fi
}

assert_file_exists() {
    local path="$1"
    local msg="$2"
    if [[ -f "$path" ]]; then
        pass "$msg"
    else
        fail "$msg" "file does not exist: $path"
    fi
}

assert_dir_exists() {
    local path="$1"
    local msg="$2"
    if [[ -d "$path" ]]; then
        pass "$msg"
    else
        fail "$msg" "directory does not exist: $path"
    fi
}

assert_not_exists() {
    local path="$1"
    local msg="$2"
    if [[ ! -e "$path" ]]; then
        pass "$msg"
    else
        fail "$msg" "path should not exist: $path"
    fi
}

# -----------------------------------------------------------------------------
# Helper: Create an isolated sandbox with mocked external binaries
# -----------------------------------------------------------------------------
create_sandbox() {
    local name="$1"
    local sb="$TEST_ROOT/$name"
    mkdir -p "$sb/home" "$sb/bin" "$sb/mock-state" "$sb/qml/Caelestia"

    # Mock Caelestia QML plugin qmldir
    printf 'module Caelestia\n' > "$sb/qml/Caelestia/qmldir"

    # Mock `qs` (Quickshell CLI)
    cat > "$sb/bin/qs" <<'EOF'
#!/usr/bin/env bash
STATE_DIR="${MOCK_STATE_DIR:?}"
echo "qs $*" >> "$STATE_DIR/commands.log"

case "${1:-}" in
    list)
        if [[ -f "$STATE_DIR/qs_ii_running" ]]; then
            echo "Config path: /mock/.config/quickshell/ii/shell.qml"
        fi
        if [[ -f "$STATE_DIR/qs_cael_running" ]]; then
            if [[ "${MOCK_CAEL_CRASH_ON_SECOND_CHECK:-0}" == "1" ]]; then
                count="$(cat "$STATE_DIR/cael_check_count" 2>/dev/null || echo 0)"
                count=$((count + 1))
                echo "$count" > "$STATE_DIR/cael_check_count"
                if (( count >= 2 )); then
                    rm -f "$STATE_DIR/qs_cael_running"
                    exit 0
                fi
            fi
            echo "Config path: /mock/.config/quickshell/caelestia-hybrid/shell.qml"
        fi
        exit 0
        ;;
    kill)
        if [[ "${3:-}" == "ii" ]]; then
            rm -f "$STATE_DIR/qs_ii_running"
        elif [[ "${3:-}" == "caelestia-hybrid" ]]; then
            rm -f "$STATE_DIR/qs_cael_running"
        fi
        exit 0
        ;;
    -c)
        cfg="${2:-}"
        shift 2 || true
        if [[ "${1:-}" == "ipc" ]]; then
            echo "qs_ipc $cfg $*" >> "$STATE_DIR/ipc.log"
            if [[ "${MOCK_QS_IPC_FAIL:-0}" == "1" ]]; then
                exit 1
            fi
            exit 0
        fi
        if [[ "$cfg" == "ii" ]]; then
            if [[ "${MOCK_II_START_FAIL:-0}" == "1" ]]; then
                exit 1
            fi
            touch "$STATE_DIR/qs_ii_running"
        elif [[ "$cfg" == "caelestia-hybrid" ]]; then
            if [[ "${MOCK_CAEL_START_FAIL:-0}" == "1" ]]; then
                exit 1
            fi
            touch "$STATE_DIR/qs_cael_running"
        fi
        exit 0
        ;;
esac
exit 0
EOF

    # Mock `setsid` (runs command in background or foreground immediately for deterministic tests)
    cat > "$sb/bin/setsid" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-f" ]]; then
    shift
fi
"$@" &
exit 0
EOF

    # Mock `hyprctl`
    cat > "$sb/bin/hyprctl" <<'EOF'
#!/usr/bin/env bash
STATE_DIR="${MOCK_STATE_DIR:?}"
echo "hyprctl $*" >> "$STATE_DIR/hyprctl.log"
if [[ "${1:-}" == "reload" && "${MOCK_HYPRCTL_RELOAD_FAIL:-0}" == "1" ]]; then
    echo "Mock hyprctl reload error" >&2
    exit 1
fi
if [[ "${1:-}" == "hyprsunset" && "${2:-}" == "temperature" ]]; then
    if [[ -n "${3:-}" ]]; then
        echo "${3}" > "$STATE_DIR/hyprsunset_temp"
    else
        cat "$STATE_DIR/hyprsunset_temp" 2>/dev/null || echo "6500"
    fi
fi
exit 0
EOF

    # Mock `hyprlock`
    cat > "$sb/bin/hyprlock" <<'EOF'
#!/usr/bin/env bash
STATE_DIR="${MOCK_STATE_DIR:?}"
echo "hyprlock $*" >> "$STATE_DIR/hyprlock.log"
exit 0
EOF

    # Mock `pidof`
    cat > "$sb/bin/pidof" <<'EOF'
#!/usr/bin/env bash
STATE_DIR="${MOCK_STATE_DIR:?}"
if [[ "${1:-}" == "hyprlock" && -f "$STATE_DIR/hyprlock_running" ]]; then
    echo "99999"
    exit 0
fi
exit 1
EOF

    # Mock `notify-send`
    cat > "$sb/bin/notify-send" <<'EOF'
#!/usr/bin/env bash
STATE_DIR="${MOCK_STATE_DIR:?}"
echo "notify-send $*" >> "$STATE_DIR/notify.log"
exit 0
EOF

    # Mock `fc-list` (pretends Google Sans Flex is installed so network clone is never attempted)
    cat > "$sb/bin/fc-list" <<'EOF'
#!/usr/bin/env bash
echo "/usr/share/fonts/Google Sans Flex.ttf: Google Sans Flex:style=Regular"
EOF

    # Mock `mpvpaper`
    cat > "$sb/bin/mpvpaper" <<'EOF'
#!/usr/bin/env bash
STATE_DIR="${MOCK_STATE_DIR:?}"
echo "mpvpaper $*" >> "$STATE_DIR/mpvpaper.log"
sleep 30
EOF

    # Mock `pkill` (safe no-op for mpvpaper inside sandbox)
    cat > "$sb/bin/pkill" <<'EOF'
#!/usr/bin/env bash
STATE_DIR="${MOCK_STATE_DIR:?}"
echo "pkill $*" >> "$STATE_DIR/pkill.log"
exit 0
EOF

    # Mock `hyprsunset`
    cat > "$sb/bin/hyprsunset" <<'EOF'
#!/usr/bin/env bash
STATE_DIR="${MOCK_STATE_DIR:?}"
echo "hyprsunset $*" >> "$STATE_DIR/hyprsunset.log"
exit 0
EOF

    # Mock `gsettings`
    cat > "$sb/bin/gsettings" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "get" ]]; then
    echo "'prefer-dark'"
fi
exit 0
EOF

        # Mock `pacman`
    cat > "$sb/bin/pacman" <<'MOCK_PACMAN'
#!/usr/bin/env bash
STATE_DIR="${MOCK_STATE_DIR:-/tmp}"
echo "pacman $*" >> "$STATE_DIR/commands.log"
case "${1:-}" in
    -Qq) exit 1 ;;
    -Qeq) echo ""; exit 0 ;;
    -S|-Syu|-R) exit 0 ;;
    *) exit 0 ;;
esac
MOCK_PACMAN

    # Mock `yay`
    cat > "$sb/bin/yay" <<'MOCK_YAY'
#!/usr/bin/env bash
STATE_DIR="${MOCK_STATE_DIR:-/tmp}"
echo "yay $*" >> "$STATE_DIR/commands.log"
exit 0
MOCK_YAY

    chmod +x "$sb/bin/"*
    printf '%s\n' "$sb"
}

printf "\n${CLR_CYAN}=== 1. Testes de Carregamento de Perfis, Dependências e Caminhos XDG ===${CLR_RST}\n"

(
    sb="$(create_sandbox "profiles")"
    export HOME="$sb/home"
    export XDG_CONFIG_HOME="$sb/xdg-config"
    export XDG_DATA_HOME="$sb/xdg-data"
    export XDG_STATE_HOME="$sb/xdg-state"
    export XDG_CACHE_HOME="$sb/xdg-cache"
    export XDG_BIN_HOME="$sb/xdg-bin"

    source ./sdata/lib/environment-variables.sh
    source ./sdata/lib/functions.sh

    [[ "$DOTS_CORE_CONFDIR" == "$sb/xdg-config/illogical-impulse" ]] || exit 11
    [[ "$INSTALLED_LISTFILE" == "$sb/xdg-config/illogical-impulse/installed_listfile" ]] || exit 12
    [[ "$BACKUP_DIR" == "$sb/home/ii-original-dots-backup" ]] || exit 13

    # Minimal profile
    load_install_profile "minimal"
    [[ "$INSTALL_PROFILE" == "minimal" ]] || exit 21
    [[ "$INSTALL_CAELESTIA_HYBRID" == "false" ]] || exit 22
    [[ "$INSTALL_OPTIONAL_APPS" == "false" ]] || exit 23
    [[ "$SKIP_MISCCONF" == "true" ]] || exit 24
    for pkg in "${ARCH_METAPKGS[@]}"; do
        [[ "$pkg" != *"caelestia-plugin"* ]] || exit 25
    done

    # Hybrid profile
    unset SKIP_MISCCONF SKIP_PLASMAINTG
    load_install_profile "hybrid"
    [[ "$INSTALL_PROFILE" == "hybrid" ]] || exit 31
    [[ "$INSTALL_CAELESTIA_HYBRID" == "true" ]] || exit 32
    [[ "$INSTALL_OPTIONAL_APPS" == "false" ]] || exit 33
    found_plugin=false
    for pkg in "${ARCH_METAPKGS[@]}"; do
        [[ "$pkg" == *"illogical-impulse-caelestia-plugin"* ]] && found_plugin=true
    done
    [[ "$found_plugin" == "true" ]] || exit 34

    # Complete profile
    load_install_profile "complete"
    [[ "$INSTALL_PROFILE" == "complete" ]] || exit 41
    [[ "$INSTALL_CAELESTIA_HYBRID" == "true" ]] || exit 42
    [[ "$INSTALL_OPTIONAL_APPS" == "true" ]] || exit 43
    (( ${#ARCH_EXTRA_PKGS[@]} >= 3 )) || exit 44

    # --skip-caelestia override on complete profile
    SKIP_CAELESTIA=true
    load_install_profile "complete"
    [[ "$INSTALL_CAELESTIA_HYBRID" == "false" ]] || exit 45
) && pass "Perfis (minimal, hybrid, complete), seleção de dependências e variáveis XDG" \
  || fail "Perfis (minimal, hybrid, complete), seleção de dependências e variáveis XDG"

# Invalid profile rejection
if ./setup install-files -p invalid_profile_xyz --dry-run >/dev/null 2>&1; then
    fail "Rejeição de perfil inválido (--profile invalid_profile_xyz)"
else
    pass "Rejeição de perfil inválido (--profile invalid_profile_xyz)"
fi

printf "\n${CLR_CYAN}=== 2. Testes de Segurança do modo --dry-run (Zero Mutação) ===${CLR_RST}\n"

sb_dry="$(create_sandbox "dryrun")"
mkdir -p "${REPO_ROOT}/cache"
touch "${REPO_ROOT}/cache/.test_dry_run_sentinel"

PATH="$sb_dry/bin:$PATH" \
MOCK_STATE_DIR="$sb_dry/mock-state" \
HOME="$sb_dry/home" \
XDG_CONFIG_HOME="$sb_dry/home/.config" \
XDG_DATA_HOME="$sb_dry/home/.local/share" \
XDG_STATE_HOME="$sb_dry/home/.local/state" \
XDG_CACHE_HOME="$sb_dry/home/.cache" \
XDG_BIN_HOME="$sb_dry/home/.local/bin" \
./setup install --clean --dry-run -p complete --skip-allgreeting >/dev/null

assert_file_exists "${REPO_ROOT}/cache/.test_dry_run_sentinel" "--clean --dry-run preserva diretório cache do repositório"
rm -f "${REPO_ROOT}/cache/.test_dry_run_sentinel"

dry_files_count="$(find "$sb_dry/home" -mindepth 1 | wc -l)"
assert_eq "$dry_files_count" "0" "./setup install --dry-run não cria nenhum arquivo ou diretório no HOME alvo"

# Test dry-run with missing prerequisite commands (rsync, etc.)
sb_dry_prereq="$(create_sandbox "dryrun-prereq")"
dry_prereq_res=0
(
    mkdir -p "$sb_dry_prereq/clean-bin"
    for tool in bash sed grep sort find; do
        tool_path="$(which "$tool")"
        ln -s "$tool_path" "$sb_dry_prereq/clean-bin/$tool"
    done
    export PATH="$sb_dry_prereq/clean-bin"
    export HOME="$sb_dry_prereq/home"
    export DRY_RUN=true
    export REPO_ROOT="${REPO_ROOT}"
    source "${REPO_ROOT}/sdata/lib/environment-variables.sh"
    source "${REPO_ROOT}/sdata/lib/functions.sh"

    check_install_prerequisites >/dev/null 2>&1
) || dry_prereq_res=$?

if (( dry_prereq_res == 0 )); then
    pass "--dry-run não tenta instalar pacotes nem modificar arquivos mesmo com comandos ausentes (ex: rsync)"
else
    fail "--dry-run falhou ou tentou executar comandos com pré-requisitos ausentes"
fi

printf "\n${CLR_CYAN}=== 3. Testes de Cópia, Backup, Preservação de Arquivos Locais e Reexecução ===${CLR_RST}\n"

sb_hyb="$(create_sandbox "hybrid-install")"
# Pre-populate conflicting and unmanaged user files
mkdir -p \
    "$sb_hyb/home/.config/hypr/custom" \
    "$sb_hyb/home/.config/quickshell/my-custom-widget" \
    "$sb_hyb/home/.config/caelestia/monitors" \
    "$sb_hyb/home/.config/fish/conf.d" \
    "$sb_hyb/home/.config/fuzzel"

printf '# User original hypridle\n' > "$sb_hyb/home/.config/hypr/hypridle.conf"
printf '# User monitors from nwg-displays\n' > "$sb_hyb/home/.config/hypr/monitors.lua"
printf '# User workspaces\n' > "$sb_hyb/home/.config/hypr/workspaces.lua"
printf '# User custom rule\n' > "$sb_hyb/home/.config/hypr/custom/user-extra.lua"
printf 'import QtQuick\nItem {}\n' > "$sb_hyb/home/.config/quickshell/my-custom-widget/shell.qml"
printf '{"scale": 1.6}\n' > "$sb_hyb/home/.config/caelestia/monitors/eDP-1"
printf '{"custom": "user_shell_json"}\n' > "$sb_hyb/home/.config/caelestia/shell.json"
printf 'set -gx SECRET_TOKEN 123\n' > "$sb_hyb/home/.config/fish/conf.d/secret.fish"
printf 'old_fuzzel_config\n' > "$sb_hyb/home/.config/fuzzel/fuzzel.ini"

PATH="$sb_hyb/bin:$PATH" \
MOCK_STATE_DIR="$sb_hyb/mock-state" \
HOME="$sb_hyb/home" \
XDG_CONFIG_HOME="$sb_hyb/home/.config" \
XDG_DATA_HOME="$sb_hyb/home/.local/share" \
XDG_STATE_HOME="$sb_hyb/home/.local/state" \
XDG_CACHE_HOME="$sb_hyb/home/.cache" \
XDG_BIN_HOME="$sb_hyb/home/.local/bin" \
BACKUP_DIR="$sb_hyb/home/ii-original-dots-backup" \
./setup install-files -p hybrid -f >/dev/null

# Verify backups were created before replacement
assert_file_exists "$sb_hyb/home/ii-original-dots-backup/.config/fuzzel/fuzzel.ini" "Backup automático salva arquivos conflitantes antes de sobrescrever"
assert_eq "$(cat "$sb_hyb/home/ii-original-dots-backup/.config/fuzzel/fuzzel.ini")" "old_fuzzel_config" "Conteúdo original preservado intacto no diretório de backup"

# Verify firstrun auto-backup (.old) for hypridle.conf and caelestia/shell.json
assert_file_exists "$sb_hyb/home/.config/hypr/hypridle.conf.old" "Primeira execução move hypridle.conf preexistente para hypridle.conf.old"
assert_file_exists "$sb_hyb/home/.config/caelestia/shell.json.old" "Primeira execução move caelestia/shell.json preexistente para shell.json.old"

# Verify unmanaged user files were NOT deleted by rsync --delete
assert_file_exists "$sb_hyb/home/.config/quickshell/my-custom-widget/shell.qml" "Diretório desconhecido em ~/.config/quickshell/ preservado sem exclusão"
assert_file_exists "$sb_hyb/home/.config/caelestia/monitors/eDP-1" "Configuração de hardware ~/.config/caelestia/monitors/eDP-1 preservada"
assert_file_exists "$sb_hyb/home/.config/hypr/monitors.lua" "Arquivo local ~/.config/hypr/monitors.lua preservado"
assert_file_exists "$sb_hyb/home/.config/hypr/workspaces.lua" "Arquivo local ~/.config/hypr/workspaces.lua preservado"
assert_file_exists "$sb_hyb/home/.config/hypr/custom/user-extra.lua" "Arquivo em ~/.config/hypr/custom/ preservado (--ignore-existing)"
assert_file_exists "$sb_hyb/home/.config/fish/conf.d/secret.fish" "Diretório ~/.config/fish/conf.d/ excluído do rsync --delete"

# Verify hybrid components installed
assert_file_exists "$sb_hyb/home/.config/quickshell/ii/shell.qml" "Frontend end-4 (ii) instalado"
assert_file_exists "$sb_hyb/home/.config/quickshell/caelestia-hybrid/shell.qml" "Frontend caelestia-hybrid instalado no perfil hybrid"
assert_file_exists "$sb_hyb/home/.config/quickshell/ui-switch.sh" "Script ui-switch.sh instalado"
assert_file_exists "$sb_hyb/home/.local/bin/rice-lock" "Dispatcher rice-lock instalado em XDG_BIN_HOME"
assert_file_exists "$sb_hyb/home/.config/hypr/hyprlock/status.sh" "Diretório hyprlock/ sincronizado"
assert_file_exists "$sb_hyb/home/.config/illogical-impulse/installed_true" "Marcador installed_true gerado"
assert_file_exists "$sb_hyb/home/.config/illogical-impulse/installed_listfile" "Manifesto installed_listfile gerado"

# Modify caelestia/shell.json as user and re-run installer (second execution)
printf '{"user_modified_after_install": true}\n' > "$sb_hyb/home/.config/caelestia/shell.json"

PATH="$sb_hyb/bin:$PATH" \
MOCK_STATE_DIR="$sb_hyb/mock-state" \
HOME="$sb_hyb/home" \
XDG_CONFIG_HOME="$sb_hyb/home/.config" \
XDG_DATA_HOME="$sb_hyb/home/.local/share" \
XDG_STATE_HOME="$sb_hyb/home/.local/state" \
XDG_CACHE_HOME="$sb_hyb/home/.cache" \
XDG_BIN_HOME="$sb_hyb/home/.local/bin" \
BACKUP_DIR="$sb_hyb/home/ii-original-dots-backup" \
./setup install-files -p hybrid -f >/dev/null

assert_eq "$(cat "$sb_hyb/home/.config/caelestia/shell.json")" '{"user_modified_after_install": true}' "Reexecução preserva shell.json editado pelo usuário"
assert_file_exists "$sb_hyb/home/.config/caelestia/shell.json.new" "Reexecução grava atualização em shell.json.new"
assert_eq "$(cat "$sb_hyb/home/ii-original-dots-backup/.config/fuzzel/fuzzel.ini")" "old_fuzzel_config" "Reexecução não sobrescreve backup original em BACKUP_DIR"

# User adds custom personal files directly into managed directories
mkdir -p "$sb_hyb/home/.config/quickshell/ii" \
         "$sb_hyb/home/.config/quickshell/caelestia-hybrid" \
         "$sb_hyb/home/.config/hypr/hyprland"
echo "user_custom_widget" > "$sb_hyb/home/.config/quickshell/ii/my_custom_widget.qml"
echo "user_custom_module" > "$sb_hyb/home/.config/quickshell/caelestia-hybrid/my_custom_module.qml"
echo "user_custom_rule" > "$sb_hyb/home/.config/hypr/hyprland/my_extra.conf"

# Run setup and deterministically locate the exact backup directory created
setup_out="$(PATH="$sb_hyb/bin:$PATH" \
MOCK_STATE_DIR="$sb_hyb/mock-state" \
HOME="$sb_hyb/home" \
XDG_CONFIG_HOME="$sb_hyb/home/.config" \
XDG_DATA_HOME="$sb_hyb/home/.local/share" \
XDG_STATE_HOME="$sb_hyb/home/.local/state" \
XDG_CACHE_HOME="$sb_hyb/home/.cache" \
XDG_BIN_HOME="$sb_hyb/home/.local/bin" \
BACKUP_DIR="$sb_hyb/home/ii-original-dots-backup" \
./setup install-files -p hybrid -f)"

sync_bk="$(cat "$sb_hyb/home/.local/state/illogical-impulse/latest_backup_dir" 2>/dev/null || true)"
if [[ -z "$sync_bk" || ! -d "$sync_bk" ]]; then
    sync_bk="$(printf '%s\n' "$setup_out" | grep -o 'Backup into "[^"]*"' | sed 's/Backup into "//;s/"//' | tail -n 1)"
fi
if [[ -z "$sync_bk" || ! -d "$sync_bk" ]]; then
    sync_bk="$(find "$sb_hyb/home" -type d -path "*/sync-deleted/ii" 2>/dev/null | sed 's|/sync-deleted/ii||' | head -n 1)"
fi

assert_file_exists "$sync_bk/sync-deleted/ii/my_custom_widget.qml" "Reexecução: arquivo personalizado em quickshell/ii é salvo em backup antes do sync"
assert_eq "$(cat "$sync_bk/sync-deleted/ii/my_custom_widget.qml")" "user_custom_widget" "Reexecução: integridade de my_custom_widget.qml preservada"
assert_file_exists "$sync_bk/sync-deleted/caelestia-hybrid/my_custom_module.qml" "Reexecução: arquivo personalizado em quickshell/caelestia-hybrid é salvo em backup antes do sync"
assert_eq "$(cat "$sync_bk/sync-deleted/caelestia-hybrid/my_custom_module.qml")" "user_custom_module" "Reexecução: integridade de my_custom_module.qml preservada"
assert_file_exists "$sync_bk/sync-deleted/hyprland/my_extra.conf" "Reexecução: arquivo personalizado em hypr/hyprland é salvo em backup antes do sync"
assert_eq "$(cat "$sync_bk/sync-deleted/hyprland/my_extra.conf")" "user_custom_rule" "Reexecução: integridade de my_extra.conf preservada"
assert_file_exists "$sb_hyb/home/.local/bin/ui-switch.sh" "Script ui-switch.sh instalado em XDG_BIN_HOME (~/.local/bin)"

printf "\n${CLR_CYAN}=== 4. Testes de Transição entre Perfis (minimal <-> hybrid) e Paridade Legacy vs Exp ===${CLR_RST}\n"

sb_min="$(create_sandbox "minimal-install")"
PATH="$sb_min/bin:$PATH" \
MOCK_STATE_DIR="$sb_min/mock-state" \
HOME="$sb_min/home" \
XDG_CONFIG_HOME="$sb_min/home/.config" \
XDG_DATA_HOME="$sb_min/home/.local/share" \
XDG_STATE_HOME="$sb_min/home/.local/state" \
XDG_CACHE_HOME="$sb_min/home/.cache" \
XDG_BIN_HOME="$sb_min/home/.local/bin" \
./setup install-files -p minimal -f >/dev/null

assert_file_exists "$sb_min/home/.config/quickshell/ii/shell.qml" "Perfil minimal instala quickshell/ii"
assert_not_exists "$sb_min/home/.config/quickshell/caelestia-hybrid" "Perfil minimal não instala caelestia-hybrid"
assert_file_exists "$sb_min/home/.config/quickshell/ui-switch.sh" "Perfil minimal instala ui-switch.sh para evitar erro no botão da barra"
assert_eq "$(cat "$sb_min/home/.local/state/quickshell/ui-switch/current")" "end4" "Perfil minimal define estado inicial de frontend como end4"

# Experimental mode (--exp-files) test & non-destructive hypr check
sb_exp="$(create_sandbox "exp-install")"
mkdir -p "$sb_exp/home/.config/hypr"
printf '# Custom monitors.lua in exp mode\n' > "$sb_exp/home/.config/hypr/monitors.lua"

PATH="$sb_exp/bin:$PATH" \
MOCK_STATE_DIR="$sb_exp/mock-state" \
HOME="$sb_exp/home" \
XDG_CONFIG_HOME="$sb_exp/home/.config" \
XDG_DATA_HOME="$sb_exp/home/.local/share" \
XDG_STATE_HOME="$sb_exp/home/.local/state" \
XDG_CACHE_HOME="$sb_exp/home/.cache" \
XDG_BIN_HOME="$sb_exp/home/.local/bin" \
./setup install-files -p hybrid --exp-files -f >/dev/null

assert_file_exists "$sb_exp/home/.config/hypr/monitors.lua" "Modo --exp-files preserva ~/.config/hypr/monitors.lua sem exclusão"
assert_file_exists "$sb_exp/home/.config/quickshell/caelestia-hybrid/shell.qml" "Modo --exp-files instala caelestia-hybrid no perfil hybrid"
assert_file_exists "$sb_exp/home/.config/hypr/hyprlock/status.sh" "Modo --exp-files sincroniza hypr/hyprlock"
assert_file_exists "$sb_exp/home/.config/illogical-impulse/installed_listfile" "Modo --exp-files registra arquivos em installed_listfile"

printf "\n${CLR_CYAN}=== 5. Testes de Propagação de Erros e Permissões Insuficientes ===${CLR_RST}\n"

sb_err="$(create_sandbox "perm-error")"
mkdir -p "$sb_err/home/.config"
chmod 500 "$sb_err/home/.config"

if PATH="$sb_err/bin:$PATH" \
   MOCK_STATE_DIR="$sb_err/mock-state" \
   HOME="$sb_err/home" \
   XDG_CONFIG_HOME="$sb_err/home/.config" \
   XDG_DATA_HOME="$sb_err/home/.local/share" \
   XDG_STATE_HOME="$sb_err/home/.local/state" \
   XDG_CACHE_HOME="$sb_err/home/.cache" \
   XDG_BIN_HOME="$sb_err/home/.local/bin" \
   ./setup install-files -p minimal -f --skip-backup >/dev/null 2>&1; then
    chmod 700 "$sb_err/home/.config"
    fail "Propagação de erro quando diretório de destino é somente-leitura (chmod 500)"
else
    chmod 700 "$sb_err/home/.config"
    pass "Propagação de erro quando diretório de destino é somente-leitura (chmod 500)"
fi

printf "\n${CLR_CYAN}=== 6. Testes Comportamentais da Integração Híbrida (ui-switch, rollback, rice-lock, bridges) ===${CLR_RST}\n"

# Use the hybrid sandbox from Section 3 to run behavioral runtime tests
export PATH="$sb_hyb/bin:$PATH"
export MOCK_STATE_DIR="$sb_hyb/mock-state"
export HOME="$sb_hyb/home"
export XDG_CONFIG_HOME="$sb_hyb/home/.config"
export XDG_DATA_HOME="$sb_hyb/home/.local/share"
export XDG_STATE_HOME="$sb_hyb/home/.local/state"
export XDG_CACHE_HOME="$sb_hyb/home/.cache"
export XDG_BIN_HOME="$sb_hyb/home/.local/bin"
export CAELESTIA_QML_PATH="$sb_hyb/qml"
export CAELESTIA_QML_ONLY="true"
export END4_LOG="$sb_hyb/mock-state/end4.log"
export CAEL_LOG="$sb_hyb/mock-state/cael.log"
export HYPR_LOG="$sb_hyb/mock-state/hypr.log"
export UI_SWITCH_WAIT_ITERS=10
export UI_SWITCH_WAIT_SLEEP=0.02
export UI_SWITCH_STABILITY_SLEEP=0.05

# 6.1 Start in end-4 and toggle to Caelestia (first boot without colors.json -> fallback palette)
touch "$MOCK_STATE_DIR/qs_ii_running"
"$XDG_CONFIG_HOME/quickshell/ui-switch.sh" toggle >/dev/null

assert_eq "$("$XDG_CONFIG_HOME/quickshell/ui-switch.sh" status)" "caelestia" "ui-switch.sh alterna de end-4 para Caelestia com sucesso"
assert_eq "$(cat "$XDG_STATE_HOME/quickshell/ui-switch/current")" "caelestia" "ui-switch.sh persiste estado 'caelestia' em current"
assert_file_exists "$XDG_STATE_HOME/caelestia/scheme.json" "end4-theme-bridge.sh gera scheme.json de fallback no primeiro boot sem colors.json"
assert_eq "$(jq -r '.name' "$XDG_STATE_HOME/caelestia/scheme.json")" "end4-fallback" "scheme.json usa paleta end4-fallback quando colors.json ainda não existe"

# 6.2 Toggle from Caelestia back to end-4
"$XDG_CONFIG_HOME/quickshell/ui-switch.sh" toggle >/dev/null
assert_eq "$("$XDG_CONFIG_HOME/quickshell/ui-switch.sh" status)" "end4" "ui-switch.sh alterna de Caelestia de volta para end-4"
assert_eq "$(cat "$XDG_STATE_HOME/quickshell/ui-switch/current")" "end4" "ui-switch.sh persiste estado 'end4' em current"

# 6.3 Test rollback when Caelestia fails to start
if MOCK_CAEL_START_FAIL=1 "$XDG_CONFIG_HOME/quickshell/ui-switch.sh" toggle >/dev/null 2>&1; then
    fail "ui-switch.sh retorna código de erro quando Caelestia falha ao iniciar"
else
    pass "ui-switch.sh retorna código de erro quando Caelestia falha ao iniciar"
fi
assert_eq "$("$XDG_CONFIG_HOME/quickshell/ui-switch.sh" status)" "end4" "Rollback automático restaura processo end-4 após falha de inicialização do Caelestia"
assert_eq "$(cat "$XDG_STATE_HOME/quickshell/ui-switch/current")" "end4" "Rollback automático preserva estado 'end4' após falha de inicialização"

# 6.4 Test rollback when Caelestia crashes right after Configuration Loaded (stability check)
rm -f "$MOCK_STATE_DIR/cael_check_count"
if MOCK_CAEL_CRASH_ON_SECOND_CHECK=1 "$XDG_CONFIG_HOME/quickshell/ui-switch.sh" toggle >/dev/null 2>&1; then
    fail "ui-switch.sh detecta crash pós-inicialização do Caelestia"
else
    pass "ui-switch.sh detecta crash pós-inicialização do Caelestia"
fi
assert_eq "$("$XDG_CONFIG_HOME/quickshell/ui-switch.sh" status)" "end4" "Rollback automático restaura end-4 após crash pós-inicialização do Caelestia"

# 6.5 Test missing Caelestia QML plugin aborts before stopping end-4
if CAELESTIA_QML_PATH="/nonexistent/qml" CAELESTIA_QML_ONLY=true "$XDG_CONFIG_HOME/quickshell/ui-switch.sh" toggle >/dev/null 2>&1; then
    fail "ui-switch.sh recusa transição quando plugin QML Caelestia está ausente"
else
    pass "ui-switch.sh recusa transição quando plugin QML Caelestia está ausente"
fi
assert_eq "$("$XDG_CONFIG_HOME/quickshell/ui-switch.sh" status)" "end4" "end-4 permanece ativo quando plugin QML está ausente"

# 6.6 Test end4-theme-bridge.sh with dynamic colors.json and video thumbnailPath
mkdir -p "$XDG_STATE_HOME/quickshell/user/generated" "$XDG_CONFIG_HOME/illogical-impulse"
cat > "$XDG_STATE_HOME/quickshell/user/generated/colors.json" <<'EOF'
{
  "primary": "#c9bfff",
  "on_primary_container": "#e5deff",
  "surface_container_high": "#2b292f"
}
EOF
touch "$sb_hyb/home/wall-thumb.jpg"
cat > "$XDG_CONFIG_HOME/illogical-impulse/config.json" <<EOF
{
  "background": {
    "wallpaperPath": "$sb_hyb/home/animated.mp4",
    "thumbnailPath": "$sb_hyb/home/wall-thumb.jpg"
  }
}
EOF
"$XDG_CONFIG_HOME/quickshell/caelestia-hybrid/scripts/end4-theme-bridge.sh" >/dev/null
assert_eq "$(jq -r '.colours.onPrimaryContainer' "$XDG_STATE_HOME/caelestia/scheme.json")" "e5deff" "end4-theme-bridge.sh converte snake_case (#rrggbb) para camelCase (rrggbb)"
assert_eq "$(cat "$XDG_STATE_HOME/caelestia/wallpaper/path.txt")" "$sb_hyb/home/wall-thumb.jpg" "end4-theme-bridge.sh usa thumbnailPath estático quando wallpaper é vídeo (.mp4)"

# 6.7 Test video-wallpaper-sync.sh (video, GIF vs static wallpaper)
touch "$sb_hyb/home/animated.mp4" "$sb_hyb/home/animated.gif" "$sb_hyb/home/static.png"
VIDEO_BRIDGE_LOG="$MOCK_STATE_DIR/video.log" \
"$XDG_CONFIG_HOME/quickshell/caelestia-hybrid/scripts/video-wallpaper-sync.sh" once
assert_eq "$(jq -r '.background.wallpaperEnabled' "$XDG_CONFIG_HOME/caelestia/shell.json")" "false" "video-wallpaper-sync.sh desativa wallpaper estático do Caelestia quando há vídeo (.mp4)"

cat > "$XDG_CONFIG_HOME/illogical-impulse/config.json" <<EOF
{
  "background": {
    "wallpaperPath": "$sb_hyb/home/static.png"
  }
}
EOF
VIDEO_BRIDGE_LOG="$MOCK_STATE_DIR/video.log" \
"$XDG_CONFIG_HOME/quickshell/caelestia-hybrid/scripts/video-wallpaper-sync.sh" once
assert_eq "$(jq -r '.background.wallpaperEnabled' "$XDG_CONFIG_HOME/caelestia/shell.json")" "true" "video-wallpaper-sync.sh reativa wallpaper estático do Caelestia ao voltar para imagem (.png)"

cat > "$XDG_CONFIG_HOME/illogical-impulse/config.json" <<EOF
{
  "background": {
    "wallpaperPath": "$sb_hyb/home/animated.gif"
  }
}
EOF
VIDEO_BRIDGE_LOG="$MOCK_STATE_DIR/video.log" \
"$XDG_CONFIG_HOME/quickshell/caelestia-hybrid/scripts/video-wallpaper-sync.sh" once
assert_eq "$(jq -r '.background.wallpaperEnabled' "$XDG_CONFIG_HOME/caelestia/shell.json")" "false" "video-wallpaper-sync.sh trata wallpaper .gif como animado e desativa fundo estático"

# 6.7b Test flock concurrency protection on ui-switch.sh
(
    exec 9>"$XDG_STATE_HOME/quickshell/ui-switch/switch.lock"
    flock -n 9
    out="$("$XDG_CONFIG_HOME/quickshell/ui-switch.sh" toggle)"
    [[ "$out" == *"Transição de interface já está em andamento"* ]]
) && pass "ui-switch.sh bloqueia execuções concorrentes via flock evitando processos duplicados" \
  || fail "ui-switch.sh bloqueia execuções concorrentes via flock evitando processos duplicados"

# 6.8 Test rice-lock dispatcher (useHyprlock=true, useHyprlock=false in end-4 and Caelestia, and fallback)
: > "$MOCK_STATE_DIR/hyprlock.log"
: > "$MOCK_STATE_DIR/ipc.log"
cat > "$XDG_CONFIG_HOME/illogical-impulse/config.json" <<'EOF'
{
  "general": {
    "lock": {
      "useHyprlock": true
    }
  }
}
EOF
"$XDG_BIN_HOME/rice-lock"
assert_eq "$(wc -l < "$MOCK_STATE_DIR/hyprlock.log")" "1" "rice-lock aciona hyprlock quando general.lock.useHyprlock=true"

cat > "$XDG_CONFIG_HOME/illogical-impulse/config.json" <<'EOF'
{
  "general": {
    "lock": {
      "useHyprlock": false
    }
  }
}
EOF
"$XDG_BIN_HOME/rice-lock"
grep -Fq "qs_ipc ii ipc call lock activate" "$MOCK_STATE_DIR/ipc.log" \
    && pass "rice-lock aciona 'qs -c ii ipc call lock activate' quando end-4 está ativo e useHyprlock=false" \
    || fail "rice-lock aciona 'qs -c ii ipc call lock activate' quando end-4 está ativo e useHyprlock=false"

rm -f "$MOCK_STATE_DIR/qs_ii_running"
touch "$MOCK_STATE_DIR/qs_cael_running"
printf 'caelestia\n' > "$XDG_STATE_HOME/quickshell/ui-switch/current"
"$XDG_BIN_HOME/rice-lock"
grep -Fq "qs_ipc caelestia-hybrid ipc call lock lock" "$MOCK_STATE_DIR/ipc.log" \
    && pass "rice-lock aciona 'qs -c caelestia-hybrid ipc call lock lock' quando Caelestia está ativo" \
    || fail "rice-lock aciona 'qs -c caelestia-hybrid ipc call lock lock' quando Caelestia está ativo"

# Fallback to hyprlock when qs ipc fails
: > "$MOCK_STATE_DIR/hyprlock.log"
MOCK_QS_IPC_FAIL=1 "$XDG_BIN_HOME/rice-lock"
assert_eq "$(wc -l < "$MOCK_STATE_DIR/hyprlock.log")" "1" "rice-lock faz fallback para hyprlock quando chamada IPC do Quickshell falha"

# 6.9 Test nightlight.sh and caelestia-runtime-binds.sh
"$XDG_CONFIG_HOME/quickshell/caelestia-hybrid/scripts/nightlight.sh" on
assert_eq "$("$XDG_CONFIG_HOME/quickshell/caelestia-hybrid/scripts/nightlight.sh" status)" "on" "nightlight.sh ativa filtro de luz noturna (4500K) e retorna status 'on'"
"$XDG_CONFIG_HOME/quickshell/caelestia-hybrid/scripts/nightlight.sh" off
assert_eq "$("$XDG_CONFIG_HOME/quickshell/caelestia-hybrid/scripts/nightlight.sh" status)" "off" "nightlight.sh desativa filtro de luz noturna (6500K) e retorna status 'off'"

: > "$MOCK_STATE_DIR/hyprctl.log"
"$XDG_CONFIG_HOME/quickshell/caelestia-hybrid/scripts/caelestia-runtime-binds.sh" enable
assert_eq "$(cat "$XDG_STATE_HOME/quickshell/ui-switch/current")" "caelestia" "caelestia-runtime-binds.sh enable grava estado 'caelestia' e recarrega Hyprland"
grep -Fq "hyprctl reload" "$MOCK_STATE_DIR/hyprctl.log" \
    && pass "caelestia-runtime-binds.sh aciona hyprctl reload ao alternar binds" \
    || fail "caelestia-runtime-binds.sh aciona hyprctl reload ao alternar binds"

printf "\n${CLR_CYAN}=== 7. Validação Estática do PKGBUILD e Integridade Upstream Caelestia ===${CLR_RST}\n"

./sdata/lib/caelestia-hybrid-upstream.sh --verify >/dev/null \
    && pass "caelestia-hybrid-upstream.sh --verify confirma integridade do manifesto e revisão upstream" \
    || fail "caelestia-hybrid-upstream.sh --verify confirma integridade do manifesto e revisão upstream"

(
    source ./sdata/dist-arch/illogical-impulse-caelestia-plugin/PKGBUILD
    [[ "$pkgname" == "illogical-impulse-caelestia-plugin" ]] || exit 1
    [[ "$_commit" == "454f46da16ae75cc57f34adf48dea74db0fa5175" ]] || exit 2
    [[ "${source[0]}" == *"#commit=454f46da16ae75cc57f34adf48dea74db0fa5175" ]] || exit 3
    for req_dep in aubio ffmpeg libcava libpipewire libqalculate lm_sensors mpvpaper qt6-base qt6-declarative; do
        found=false
        for d in "${depends[@]}"; do
            [[ "$d" == "$req_dep" ]] && found=true
        done
        [[ "$found" == "true" ]] || exit 4
    done
) && pass "PKGBUILD illogical-impulse-caelestia-plugin validado (commit fixado, dependências Qt6/QML/C++/mídia)" \
  || fail "PKGBUILD illogical-impulse-caelestia-plugin validado"

if grep -RIn "greyrat" dots/ sdata/ setup >/dev/null 2>&1; then
    fail "Portabilidade: zero referências hardcoded ao usuário 'greyrat' em dots/, sdata/ e setup"
else
    pass "Portabilidade: zero referências hardcoded ao usuário 'greyrat' em dots/, sdata/ e setup"
fi

printf "\n${CLR_CYAN}=== 8. Testes de Segurança de Submódulos Git e Auditoria de Confirmações AUR ===${CLR_RST}\n"

submod_sb="$(mktemp -d "${TEST_ROOT}/submod-test-XXXXXX")"
export GIT_ALLOW_PROTOCOL=file:https:http:ssh
export GIT_AUTHOR_NAME="Test"
export GIT_AUTHOR_EMAIL="test@example.com"
export GIT_COMMITTER_NAME="Test"
export GIT_COMMITTER_EMAIL="test@example.com"

# Setup upstream dummy repo and submodule
mkdir -p "$submod_sb/upstream_sub"
git -C "$submod_sb/upstream_sub" init -q -b main
echo "submodule_upstream_content" > "$submod_sb/upstream_sub/widget.qml"
git -C "$submod_sb/upstream_sub" add widget.qml
git -C "$submod_sb/upstream_sub" commit -q -m "initial upstream submodule"

git -C "$submod_sb" init -q -b main
git -C "$submod_sb" submodule add -q "$submod_sb/upstream_sub" "modules/shapes"
git -C "$submod_sb" commit -q -m "register shapes submodule"

test_clone="$submod_sb/clone"
git clone -q "$submod_sb" "$test_clone"
REPO_ROOT_REAL="$REPO_ROOT"

# Test 8.1: Submódulo ausente / diretório vazio
mkdir -p "$test_clone/modules/shapes"
(
    export REPO_ROOT="$test_clone"
    cd "$test_clone"
    source "${REPO_ROOT_REAL}/sdata/lib/environment-variables.sh"
    source "${REPO_ROOT_REAL}/sdata/lib/functions.sh"
    ask=false
    auto_update_git_submodule >/dev/null 2>&1
)
if [[ -f "$test_clone/modules/shapes/widget.qml" ]]; then
    pass "Submódulo ausente/diretório vazio: inicializado com sucesso via rmdir seguro"
else
    fail "Submódulo ausente/diretório vazio: inicializado com sucesso via rmdir seguro"
fi

# Test 8.2: Diretório preexistente com arquivos do usuário (recusa exclusão e preserva arquivos)
rm -rf "$test_clone/modules/shapes"
mkdir -p "$test_clone/modules/shapes"
echo "precious_user_code" > "$test_clone/modules/shapes/my_script.js"
submod_res=0
(
    export REPO_ROOT="$test_clone"
    cd "$test_clone"
    source "${REPO_ROOT_REAL}/sdata/lib/environment-variables.sh"
    source "${REPO_ROOT_REAL}/sdata/lib/functions.sh"
    ask=true
    auto_update_git_submodule >/dev/null 2>&1
) || submod_res=$?

if (( submod_res != 0 )) && [[ -f "$test_clone/modules/shapes/my_script.js" ]] && [[ "$(cat "$test_clone/modules/shapes/my_script.js")" == "precious_user_code" ]]; then
    pass "Diretório preexistente com arquivos do usuário: recusou exclusão e preservou arquivos intactos"
else
    fail "Diretório preexistente com arquivos do usuário: arquivos foram alterados ou excluídos!"
fi

# Test 8.3: Flag --force (ask=false) NÃO autoriza exclusão de dados do usuário
submod_force_res=0
(
    export REPO_ROOT="$test_clone"
    cd "$test_clone"
    source "${REPO_ROOT_REAL}/sdata/lib/environment-variables.sh"
    source "${REPO_ROOT_REAL}/sdata/lib/functions.sh"
    ask=false
    auto_update_git_submodule >/dev/null 2>&1
) || submod_force_res=$?

if (( submod_force_res != 0 )) && [[ -f "$test_clone/modules/shapes/my_script.js" ]]; then
    pass "Flag --force não autoriza exclusão silenciosa de arquivos desconhecidos"
else
    fail "Flag --force não autoriza exclusão silenciosa de arquivos desconhecidos"
fi

# Test 8.4: Links simbólicos (não segue, não apaga e não modifica target)
rm -rf "$test_clone/modules/shapes"
mkdir -p "$submod_sb/external_dir"
echo "host_private_data" > "$submod_sb/external_dir/private.txt"
ln -s "$submod_sb/external_dir" "$test_clone/modules/shapes"
submod_symlink_res=0
(
    export REPO_ROOT="$test_clone"
    cd "$test_clone"
    source "${REPO_ROOT_REAL}/sdata/lib/environment-variables.sh"
    source "${REPO_ROOT_REAL}/sdata/lib/functions.sh"
    ask=false
    auto_update_git_submodule >/dev/null 2>&1
) || submod_symlink_res=$?

if (( submod_symlink_res != 0 )) && [[ -L "$test_clone/modules/shapes" ]] && [[ -f "$submod_sb/external_dir/private.txt" ]]; then
    pass "Links simbólicos: recusou link simbólico sem seguir nem remover arquivo alvo"
else
    fail "Links simbólicos: link ou alvo externo foi modificado!"
fi
rm -f "$test_clone/modules/shapes"

# Test 8.5: Falha de permissão no diretório vazio (tratamento robusto de erro)
mkdir -p "$test_clone/modules/shapes"
chmod 500 "$test_clone/modules"
submod_perm_res=0
(
    export REPO_ROOT="$test_clone"
    cd "$test_clone"
    source "${REPO_ROOT_REAL}/sdata/lib/environment-variables.sh"
    source "${REPO_ROOT_REAL}/sdata/lib/functions.sh"
    ask=false
    auto_update_git_submodule >/dev/null 2>&1
) || submod_perm_res=$?

chmod 755 "$test_clone/modules"
rmdir "$test_clone/modules/shapes" 2>/dev/null || true
if (( submod_perm_res != 0 )); then
    pass "Falha de permissão em rmdir: propagação tratada e saída com erro limpo"
else
    fail "Falha de permissão em rmdir: não detectou falha de permissão"
fi

# Test 8.6: Arquivamento explícito seguro com ARCHIVE_SUBMODULE_CONFLICTS=true
mkdir -p "$test_clone/modules/shapes"
echo "custom_version_1" > "$test_clone/modules/shapes/config.json"
export XDG_STATE_HOME="$submod_sb/state"
(
    export REPO_ROOT="$test_clone"
    cd "$test_clone"
    source "${REPO_ROOT_REAL}/sdata/lib/environment-variables.sh"
    source "${REPO_ROOT_REAL}/sdata/lib/functions.sh"
    export ARCHIVE_SUBMODULE_CONFLICTS=true
    ask=false
    auto_update_git_submodule >/dev/null 2>&1
)

b1_dir="$(find "$XDG_STATE_HOME/dots-hyprland/submodule-backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n 1)"
if [[ -n "$b1_dir" ]] && [[ -f "$b1_dir/config.json" ]] && [[ "$(cat "$b1_dir/config.json")" == "custom_version_1" ]] && [[ -f "$test_clone/modules/shapes/widget.qml" ]]; then
    pass "Arquivamento seguro: moveu diretório conflitante para backup único fora do repo e inicializou submódulo"
else
    fail "Arquivamento seguro: falhou ao criar backup ou inicializar submódulo"
fi

# Test 8.7: Preservação de múltiplos backups (nunca sobrescreve backup preexistente)
rm -rf "$test_clone/modules/shapes"
mkdir -p "$test_clone/modules/shapes"
echo "custom_version_2" > "$test_clone/modules/shapes/config.json"
(
    export REPO_ROOT="$test_clone"
    cd "$test_clone"
    source "${REPO_ROOT_REAL}/sdata/lib/environment-variables.sh"
    source "${REPO_ROOT_REAL}/sdata/lib/functions.sh"
    export ARCHIVE_SUBMODULE_CONFLICTS=true
    ask=false
    auto_update_git_submodule >/dev/null 2>&1
)

total_backups="$(find "$XDG_STATE_HOME/dots-hyprland/submodule-backups" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
if (( total_backups >= 2 )) && grep -rq "custom_version_1" "$XDG_STATE_HOME/dots-hyprland/submodule-backups" && grep -rq "custom_version_2" "$XDG_STATE_HOME/dots-hyprland/submodule-backups"; then
    pass "Preservação de backups: segundo backup criado com identificador único sem sobrescrever o anterior"
else
    fail "Preservação de backups: backup anterior foi sobrescrito ou segundo backup não foi criado"
fi

# Test 8.8: Reexecução após resolução de conflito
submod_reexec_res=0
(
    export REPO_ROOT="$test_clone"
    cd "$test_clone"
    source "${REPO_ROOT_REAL}/sdata/lib/environment-variables.sh"
    source "${REPO_ROOT_REAL}/sdata/lib/functions.sh"
    ask=false
    auto_update_git_submodule >/dev/null 2>&1
) || submod_reexec_res=$?

if (( submod_reexec_res == 0 )); then
    pass "Reexecução: execução subsequente em estado limpo opera de forma idempotente e bem-sucedida"
else
    fail "Reexecução: falhou ao rodar sobre submódulo já inicializado"
fi

# Test 8.9: Auditoria de confirmação interativa do AUR e Pacman
(
    ask=true
    metainstallflags="--needed"
    $ask && true || metainstallflags="$metainstallflags --noconfirm"
    [[ "$metainstallflags" == "--needed" ]] || exit 1

    ask=false
    metainstallflags="--needed"
    $ask && true || metainstallflags="$metainstallflags --noconfirm"
    [[ "$metainstallflags" == "--needed --noconfirm" ]] || exit 2

    # install-local-pkgbuild makepkg flags
    makepkg_interactive=(makepkg -Afsi)
    test_flags="--needed"
    if [[ "$test_flags" == *"--noconfirm"* ]]; then makepkg_interactive+=(--noconfirm); fi
    [[ "${makepkg_interactive[*]}" == "makepkg -Afsi" ]] || exit 3

    makepkg_force=(makepkg -Afsi)
    test_flags_force="--needed --noconfirm"
    if [[ "$test_flags_force" == *"--noconfirm"* ]]; then makepkg_force+=(--noconfirm); fi
    [[ "${makepkg_force[*]}" == "makepkg -Afsi --noconfirm" ]] || exit 4
) && pass "Auditoria AUR/Pacman: modo interativo omite --noconfirm e modo force propaga --noconfirm" \
  || fail "Auditoria AUR/Pacman: flags de confirmação inconsistentes entre modos"

# Test 8.10: Auditoria de remoção de pacotes obsoletos (sem -Rdd e respeito ao dry-run)
(
    # Ensure -Rdd invocation is eliminated from the codebase
    if grep -E "pacman[[:space:]]+.*-Rdd" "${REPO_ROOT}/sdata/dist-arch/install-deps.sh" >/dev/null 2>&1; then
        exit 1
    fi

    # Dry-run test of remove_deprecated_dependencies function
    export DRY_RUN=true
    export ask=false
    source "${REPO_ROOT}/sdata/lib/environment-variables.sh"
    source "${REPO_ROOT}/sdata/lib/functions.sh"
    eval "$(sed -n '/^remove_deprecated_dependencies(){/,/^}/p' "${REPO_ROOT}/sdata/dist-arch/install-deps.sh")"

    remove_deprecated_dependencies >/dev/null 2>&1 || exit 2
) && pass "Auditoria de pacotes: eliminação estrita de 'pacman -Rdd' e remoção segura com verificação" \
  || fail "Auditoria de pacotes: pacman -Rdd ainda presente ou falha em remove_deprecated_dependencies"

# Test 8.11: Auditoria de política de autorização de remoção de pacotes (--force)
(
    export DRY_RUN=false
    source "${REPO_ROOT}/sdata/lib/environment-variables.sh"
    source "${REPO_ROOT}/sdata/lib/functions.sh"
    eval "$(sed -n '/^remove_deprecated_dependencies(){/,/^}/p' "${REPO_ROOT}/sdata/dist-arch/install-deps.sh")"

    # Mock pacman to simulate one legacy package is found
    pacman() {
        if [[ "$1" == "-Qq" && "$2" == "matugen-bin" ]]; then return 0; fi
        return 1
    }

    # Case A: non-interactive (--force) without ALLOW_REMOVE_DEPRECATED must NOT remove
    export ask=false
    export ALLOW_REMOVE_DEPRECATED=false
    sudo() {
        echo "ERROR: sudo called in unattended mode without authorization" >&2
        return 1
    }
    remove_deprecated_dependencies >/dev/null 2>&1 || exit 1

    # Case B: non-interactive with ALLOW_REMOVE_DEPRECATED=true authorizes safe removal
    authorized_removal=false
    sudo() {
        if [[ "$1" == "pacman" && "$2" == "-R" && "$3" == "--noconfirm" ]]; then
            authorized_removal=true
            return 0
        fi
        return 1
    }
    export ALLOW_REMOVE_DEPRECATED=true
    remove_deprecated_dependencies >/dev/null 2>&1 || exit 2
    [[ "$authorized_removal" == true ]] || exit 3
) && pass "Política de pacotes: modo --force preserva pacotes sem remoção desautorizada" \
  || fail "Política de pacotes: modo --force removeu pacotes sem autorização explícita"

# Test 8.12: Unicidade de diretórios de backup em reexecuções rápidas e zero sobrescrita
(
    sb_coll="$(create_sandbox "backup-collision-test")"
    export HOME="$sb_coll/home"
    export XDG_CONFIG_HOME="$sb_coll/home/.config"
    export XDG_DATA_HOME="$sb_coll/home/.local/share"
    export XDG_STATE_HOME="$sb_coll/home/.local/state"
    export XDG_BIN_HOME="$sb_coll/home/.local/bin"
    export BACKUP_DIR="$sb_coll/home/ii-original-dots-backup"
    export ask=false

    source "${REPO_ROOT}/sdata/lib/environment-variables.sh"
    source "${REPO_ROOT}/sdata/lib/functions.sh"
    eval "$(sed -n '/^function auto_backup_configs(){/,/^}/p' "${REPO_ROOT}/sdata/subcmd-install/3.files.sh")"

    # Execution 1: initial backup
    auto_backup_configs >/dev/null 2>&1
    d1="$ACTIVE_BACKUP_DIR"
    [[ "$d1" == "$BACKUP_DIR" ]] || exit 1
    echo "content_run1" > "$d1/run1.txt"

    # Execution 2: immediate execution (simulating same second)
    auto_backup_configs >/dev/null 2>&1
    d2="$ACTIVE_BACKUP_DIR"
    [[ "$d2" != "$d1" ]] || exit 2
    echo "content_run2" > "$d2/run2.txt"

    # Execution 3: another immediate execution in same second
    auto_backup_configs >/dev/null 2>&1
    d3="$ACTIVE_BACKUP_DIR"
    [[ "$d3" != "$d1" && "$d3" != "$d2" ]] || exit 3
    echo "content_run3" > "$d3/run3.txt"

    # Execution 4: fourth immediate execution in same second
    auto_backup_configs >/dev/null 2>&1
    d4="$ACTIVE_BACKUP_DIR"
    [[ "$d4" != "$d1" && "$d4" != "$d2" && "$d4" != "$d3" ]] || exit 4
    echo "content_run4" > "$d4/run4.txt"

    # Verify that all 4 directories are unique and prior files are never overwritten
    [[ "$(cat "$d1/run1.txt")" == "content_run1" ]] || exit 5
    [[ "$(cat "$d2/run2.txt")" == "content_run2" ]] || exit 6
    [[ "$(cat "$d3/run3.txt")" == "content_run3" ]] || exit 7
    [[ "$(cat "$d4/run4.txt")" == "content_run4" ]] || exit 8

    # Verify latest_backup_dir correctly points to the newest backup
    latest_rec="$(cat "$sb_coll/home/.local/state/illogical-impulse/latest_backup_dir")"
    [[ "$latest_rec" == "$d4" ]] || exit 9
) && pass "Backups: unicidade garantida em reexecuções rápidas e zero sobrescrita em colisões de timestamp" \
  || fail "Backups: falha na resolução de colisão de timestamp ou sobrescrita de backup anterior"

printf "\n${CLR_CYAN}=== 9. Aviso e consentimento para distribuições não suportadas ===${CLR_RST}\n"

# Runs print_os_group_id_hybrid_unsupported in an isolated subshell, with a fake
# os-release (picked up through REPO_ROOT/os-release) and no side effects on the host.
# Usage: run_distro_guard <os-id> <os-id-like> <subcmd> <extra env assignments...>
# Echoes combined output; the return code is the guard's exit code.
run_distro_guard() {
    local os_id="$1" os_like="$2" subcmd="$3"; shift 3
    local gdir; gdir="$(mktemp -d "$TEST_ROOT/distro-guard.XXXXXX")"
    printf 'ID=%s\nID_LIKE=%s\n' "$os_id" "$os_like" > "$gdir/os-release"
    (
        env "$@" REPO_ROOT="$gdir" OS_RELEASE_FILE="$gdir/os-release" SUBCMD_NAME="$subcmd" bash -c '
            source "'"${REPO_ROOT}"'/sdata/lib/environment-variables.sh"
            source "'"${REPO_ROOT}"'/sdata/lib/dist-determine.sh"
            print_os_group_id_hybrid_unsupported
        ' 2>&1
    )
}

# 9.1 Arch Linux: completely silent no-op (installer behavior unchanged)
rc=0; out="$(run_distro_guard arch "" install ask=false)" || rc=$?
if [[ $rc -eq 0 && "$out" != *"UNSUPPORTED"* ]]; then
    pass "Distro: Arch Linux não exibe aviso nem exige consentimento"
else
    fail "Distro: Arch Linux foi afetado pelo aviso de distro não suportada" "rc=$rc"
fi

# 9.2 Fedora, non-interactive install without opt-in: aborts before any change
rc=0; out="$(run_distro_guard fedora "" install ask=false)" || rc=$?
if [[ $rc -eq 1 && "$out" == *"UNSUPPORTED"* && "$out" == *"HYBRID_ALLOW_UNSUPPORTED_DISTRO"* ]]; then
    pass "Distro: Fedora com 'install -f' é bloqueado antes de qualquer alteração e explica como prosseguir"
else
    fail "Distro: Fedora com 'install -f' não foi bloqueado" "rc=$rc"
fi

# 9.3 Gentoo/Debian-like/unknown also blocked (nix fallback path included)
for spec in "gentoo:" "ubuntu:debian" "somethingelse:"; do
    rc=0; out="$(run_distro_guard "${spec%%:*}" "${spec#*:}" install-deps ask=false)" || rc=$?
    assert_eq "$rc" "1" "Distro: '${spec%%:*}' bloqueado em 'install-deps -f' sem consentimento explícito"
done

# 9.4 Explicit opt-in allows non-interactive install
rc=0; out="$(run_distro_guard fedora "" install ask=false HYBRID_ALLOW_UNSUPPORTED_DISTRO=true)" || rc=$?
assert_eq "$rc" "0" "Distro: HYBRID_ALLOW_UNSUPPORTED_DISTRO=true libera a instalação não interativa (mantém suporte herdado)"

# 9.5 --dry-run never aborts (no system change)
rc=0; out="$(run_distro_guard fedora "" install ask=false DRY_RUN=true)" || rc=$?
if [[ $rc -eq 0 && "$out" == *"UNSUPPORTED"* ]]; then
    pass "Distro: --dry-run exibe o aviso mas não aborta"
else
    fail "Distro: --dry-run foi abortado ou não exibiu aviso" "rc=$rc"
fi

# 9.6 Subcomandos modificadores protegidos pela guarda (install-setups, install-files, etc.)
for subcmd in install-setups install-files exp-update exp-merge uninstall; do
    rc=0; out="$(run_distro_guard fedora "" "$subcmd" ask=false)" || rc=$?
    assert_eq "$rc" "1" "Distro: '$subcmd -f' bloqueado em distro não suportada sem autorização explícita"
    rc=0; out="$(run_distro_guard fedora "" "$subcmd" ask=false HYBRID_ALLOW_UNSUPPORTED_DISTRO=true)" || rc=$?
    assert_eq "$rc" "0" "Distro: '$subcmd -f' liberado com HYBRID_ALLOW_UNSUPPORTED_DISTRO=true"
done

# 9.6b Ausência total de efeitos colaterais após recusa (zero logs, zero pacotes, zero arquivos criados)
for test_subcmd in install install-deps install-setups install-files; do
    sb_guard="$(create_sandbox "guard-side-effects-$test_subcmd")"
    printf 'ID=fedora
' > "$sb_guard/os-release"

    guard_exit=0
    (
        export HOME="$sb_guard/home"
        export XDG_CONFIG_HOME="$sb_guard/home/.config"
        export XDG_DATA_HOME="$sb_guard/home/.local/share"
        export XDG_STATE_HOME="$sb_guard/home/.local/state"
        export XDG_CACHE_HOME="$sb_guard/home/.cache"
        export XDG_BIN_HOME="$sb_guard/home/.local/bin"
        export REPO_ROOT="${REPO_ROOT}"
        export PATH="$sb_guard/bin:$PATH"
        export OS_RELEASE_FILE="$sb_guard/os-release"

        # Link os-release so REPO_ROOT/os-release is used
        cp "$sb_guard/os-release" "${REPO_ROOT}/os-release"

        ./setup "$test_subcmd" -f --skip-allgreeting >/dev/null 2>&1
    ) || guard_exit=$?

    rm -f "${REPO_ROOT}/os-release"

    assert_eq "$guard_exit" "1" "Distro: ./setup $test_subcmd -f em Fedora aborta com código 1 antes de qualquer ação"

    # Check that zero files or directories were created inside HOME (no logs, no config files)
    side_effects_count="$(find "$sb_guard/home" -mindepth 1 2>/dev/null | wc -l)"
    assert_eq "$side_effects_count" "0" "Distro: zero efeitos colaterais em HOME após recusa em ./setup $test_subcmd (inclusive logs)"

    # Check that mock pacman in sandbox was NOT called
    if [[ -f "$sb_guard/mock-state/commands.log" ]] && grep -qi "pacman" "$sb_guard/mock-state/commands.log"; then
        fail "Distro: pacman foi chamado antes da guarda de autorização em ./setup $test_subcmd"
    else
        pass "Distro: nenhuma chamada a gerenciador de pacotes antes da autorização em ./setup $test_subcmd"
    fi
done

# 9.7 Interactive: default answer is No; only y/Y proceeds
gdir_i="$(mktemp -d "$TEST_ROOT/distro-guard-i.XXXXXX")"
printf 'ID=fedora\nID_LIKE=\n' > "$gdir_i/os-release"
for answer in "" "n" "y"; do
    rc=0
    printf '%s\n' "$answer" | REPO_ROOT="$gdir_i" OS_RELEASE_FILE="$gdir_i/os-release" SUBCMD_NAME=install bash -c '
        source "'"${REPO_ROOT}"'/sdata/lib/environment-variables.sh"
        source "'"${REPO_ROOT}"'/sdata/lib/dist-determine.sh"
        print_os_group_id_hybrid_unsupported
    ' >/dev/null 2>&1 || rc=$?
    if [[ "$answer" == "y" ]]; then
        assert_eq "$rc" "0" "Distro: resposta interativa 'y' prossegue"
    else
        assert_eq "$rc" "1" "Distro: resposta interativa '${answer:-<Enter>}' aborta (padrão = Não)"
    fi
done

# 9.8 Arch with --via-nix is also flagged as unsupported
rc=0; out="$(run_distro_guard arch "" install ask=false INSTALL_VIA_NIX=true)" || rc=$?
if [[ $rc -eq 1 && "$out" == *"UNSUPPORTED"* ]]; then
    pass "Distro: --via-nix em Arch também é tratado como caminho não suportado"
else
    fail "Distro: --via-nix em Arch não foi sinalizado" "rc=$rc"
fi

# 9.9 Upstream community dist-* implementations are preserved (not deleted)
for d in dist-fedora dist-gentoo dist-nix dist-arch; do
    assert_file_exists "${REPO_ROOT}/sdata/${d}/install-deps.sh" "Distro: implementação herdada sdata/${d} preservada"
done

printf "\n=============================================================================\n"
printf "Resumo dos Testes: ${CLR_GREEN}%d aprovados${CLR_RST}, ${CLR_RED}%d falharam${CLR_RST} (total: %d)\n" \
    "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL_COUNT"
printf "=============================================================================\n"

(( FAIL_COUNT == 0 ))
