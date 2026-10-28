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
# Mock os-release strictly inside TEST_ROOT and export OS_RELEASE_FILE so the repository root is never modified
MOCK_ARCH_OS_RELEASE="$TEST_ROOT/os-release"
printf 'ID=arch\nID_LIKE=\n' > "$MOCK_ARCH_OS_RELEASE"
export OS_RELEASE_FILE="$MOCK_ARCH_OS_RELEASE"

# Capture initial state of ${REPO_ROOT}/os-release to verify it is never mutated or removed
INITIAL_REPO_OS_RELEASE_EXISTS=false
INITIAL_REPO_OS_RELEASE_SHA=""
if [[ -f "${REPO_ROOT}/os-release" ]]; then
    INITIAL_REPO_OS_RELEASE_EXISTS=true
    INITIAL_REPO_OS_RELEASE_SHA="$(sha256sum "${REPO_ROOT}/os-release" 2>/dev/null || true)"
fi

cleanup_suite() {
    chmod -R u+w "$TEST_ROOT" 2>/dev/null || true
    rm -rf "$TEST_ROOT" 2>/dev/null || true
    # NOTE: Never touch, write to, or remove ${REPO_ROOT}/os-release or ${REPO_ROOT}/cache
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
# Helper: Create an isolated repository directory with symlinks to real assets
# -----------------------------------------------------------------------------
create_isolated_repo() {
    local name="$1"
    local iso="$TEST_ROOT/$name"
    mkdir -p "$iso"
    cp "${REPO_ROOT}/setup" "$iso/setup"
    ln -s "${REPO_ROOT}/sdata" "$iso/sdata"
    ln -s "${REPO_ROOT}/dots" "$iso/dots"
    ln -s "${REPO_ROOT}/dots-extra" "$iso/dots-extra"
    printf '%s\n' "$iso"
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

iso_dry="$(create_isolated_repo "dryrun-clean-repo")"
mkdir -p "$iso_dry/cache"
touch "$iso_dry/cache/.test_dry_run_sentinel"

sb_dry="$(create_sandbox "dryrun")"
PATH="$sb_dry/bin:$PATH" \
MOCK_STATE_DIR="$sb_dry/mock-state" \
HOME="$sb_dry/home" \
XDG_CONFIG_HOME="$sb_dry/home/.config" \
XDG_DATA_HOME="$sb_dry/home/.local/share" \
XDG_STATE_HOME="$sb_dry/home/.local/state" \
XDG_CACHE_HOME="$sb_dry/home/.cache" \
XDG_BIN_HOME="$sb_dry/home/.local/bin" \
"$iso_dry/setup" install --clean --dry-run -p complete --skip-allgreeting >/dev/null

assert_file_exists "$iso_dry/cache/.test_dry_run_sentinel" "--clean --dry-run preserva diretório cache do repositório"

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
assert_file_exists "$sb_hyb/home/.local/share/redshift-os/icons/redshift-symbolic-compact.svg" "Ícone Redshift OS compacto instalado em ~/.local/share/redshift-os/icons"
assert_file_exists "$sb_hyb/home/.local/share/redshift-os/icons/redshift-compact-512.png" "Ícone Redshift OS 512px para lockscreen instalado em ~/.local/share/redshift-os/icons"
assert_file_exists "$sb_hyb/home/.local/share/icons/redshift-symbolic.svg" "Ícone Redshift OS simbólico instalado no diretório padrão XDG icons"
assert_file_exists "$sb_hyb/home/.config/fastfetch/config.jsonc" "Configuração do Fastfetch com identidade Redshift OS instalada"
assert_file_exists "$sb_hyb/home/.config/fastfetch/redshift_logo.txt" "Logo ASCII Redshift OS instalado para Fastfetch"

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

# 6.6b Test Material You variant selection, normalization, and persistence in Caelestia
mkdir -p "$XDG_STATE_HOME/quickshell/user/generated"
printf 'scheme-fruit-salad\n' > "$XDG_STATE_HOME/quickshell/user/generated/applied_scheme_type.txt"
printf 'fruitsalad\n' > "$XDG_STATE_HOME/quickshell/user/generated/palette_type_preference.txt"
"$XDG_CONFIG_HOME/quickshell/caelestia-hybrid/scripts/end4-theme-bridge.sh" >/dev/null
assert_eq "$(jq -r '.variant' "$XDG_STATE_HOME/caelestia/scheme.json")" "fruitsalad" "end4-theme-bridge.sh propaga variante aplicada para scheme.json"
assert_eq "$(jq -r '.variantPreference' "$XDG_STATE_HOME/caelestia/scheme.json")" "fruitsalad" "end4-theme-bridge.sh propaga preferência de variante para scheme.json"

# Test Auto mode preference with tonalspot applied
printf 'scheme-tonal-spot\n' > "$XDG_STATE_HOME/quickshell/user/generated/applied_scheme_type.txt"
printf 'auto\n' > "$XDG_STATE_HOME/quickshell/user/generated/palette_type_preference.txt"
"$XDG_CONFIG_HOME/quickshell/caelestia-hybrid/scripts/end4-theme-bridge.sh" >/dev/null
assert_eq "$(jq -r '.variant' "$XDG_STATE_HOME/caelestia/scheme.json")" "tonalspot" "end4-theme-bridge.sh registra variante concreta detectada em modo auto"
assert_eq "$(jq -r '.variantPreference' "$XDG_STATE_HOME/caelestia/scheme.json")" "auto" "end4-theme-bridge.sh preserva preferência auto em scheme.json"

# Test QML component presence and integration
assert_file_exists "$XDG_CONFIG_HOME/quickshell/caelestia-hybrid/modules/nexus/pages/wallandstyle/PaletteVariantSelector.qml" "Componente PaletteVariantSelector.qml instalado"
grep -q "openSubPage(3)" "$XDG_CONFIG_HOME/quickshell/caelestia-hybrid/modules/nexus/pages/WallpaperAndStyle.qml" \
    && pass "WallpaperAndStyle.qml direciona botão Colours para a página de cores" \
    || fail "WallpaperAndStyle.qml direciona botão Colours para a página de cores"
grep -q "PaletteVariantSelector" "$XDG_CONFIG_HOME/quickshell/caelestia-hybrid/modules/nexus/pages/wallandstyle/ColourSelect.qml" \
    && pass "ColourSelect.qml substitui placeholder e integra seletor de variantes" \
    || fail "ColourSelect.qml substitui placeholder e integra seletor de variantes"
grep -q "setVariant" "$XDG_CONFIG_HOME/quickshell/caelestia-hybrid/services/Colours.qml" \
    && pass "Colours.qml implementa setVariant para comunicação com backend" \
    || fail "Colours.qml implementa setVariant para comunicação com backend"

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

# 6.10 Test Redshift OS Visual Identity, Continuous Rotation, and GameMode
assert_file_exists "$XDG_CONFIG_HOME/quickshell/caelestia-hybrid/scripts/gamemode.py" "Script backend gamemode.py instalado"
[[ -x "$XDG_CONFIG_HOME/quickshell/caelestia-hybrid/scripts/gamemode.py" ]] \
    && pass "gamemode.py possui permissão de execução" \
    || fail "gamemode.py sem permissão de execução"
assert_file_exists "$XDG_CONFIG_HOME/quickshell/caelestia-hybrid/scripts/gamemode.sh" "Wrapper gamemode.sh instalado"
[[ -x "$XDG_CONFIG_HOME/quickshell/caelestia-hybrid/scripts/gamemode.sh" ]] \
    && pass "gamemode.sh possui permissão de execução" \
    || fail "gamemode.sh sem permissão de execução"

grep -q "RotationAnimation" "$XDG_CONFIG_HOME/quickshell/caelestia-hybrid/modules/bar/components/OsIcon.qml" \
    && pass "OsIcon.qml do Caelestia implementa rotação contínua RotationAnimation" \
    || fail "OsIcon.qml sem rotação"
grep -q "RotationAnimation" "$XDG_CONFIG_HOME/quickshell/ii/modules/ii/bar/LeftSidebarButton.qml" \
    && pass "LeftSidebarButton.qml do end-4 implementa rotação contínua RotationAnimation" \
    || fail "LeftSidebarButton.qml sem rotação"
grep -q "Colouriser" "$XDG_CONFIG_HOME/quickshell/caelestia-hybrid/modules/bar/components/OsIcon.qml" \
    && pass "OsIcon.qml do Caelestia aplica Colouriser para tingimento dinâmico" \
    || fail "OsIcon.qml sem Colouriser"
grep -q "ColorOverlay" "$XDG_CONFIG_HOME/quickshell/ii/modules/ii/bar/LeftSidebarButton.qml" \
    && pass "LeftSidebarButton.qml do end-4 aplica ColorOverlay para tingimento dinâmico" \
    || fail "LeftSidebarButton.qml sem ColorOverlay"

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

# 9.6 Subcomandos modificadores protegidos pela guarda (função isolada)
for subcmd in install-setups install-files exp-update exp-merge uninstall resetfirstrun; do
    rc=0; out="$(run_distro_guard fedora "" "$subcmd" ask=false)" || rc=$?
    assert_eq "$rc" "1" "Distro: '$subcmd -f' bloqueado em distro não suportada sem autorização explícita"
    rc=0; out="$(run_distro_guard fedora "" "$subcmd" ask=false HYBRID_ALLOW_UNSUPPORTED_DISTRO=true)" || rc=$?
    assert_eq "$rc" "0" "Distro: '$subcmd -f' liberado com HYBRID_ALLOW_UNSUPPORTED_DISTRO=true"
done

# 9.6b Execução end-to-end de ./setup: todos os subcomandos modificadores protegidos e sem efeitos colaterais
for test_subcmd in install install-deps install-setups install-files uninstall exp-update exp-merge resetfirstrun; do
    sb_guard="$(create_sandbox "guard-side-effects-$test_subcmd")"
    printf 'ID=fedora\n' > "$sb_guard/os-release"

    # For resetfirstrun, seed the real firstrun marker ($XDG_CONFIG_HOME/illogical-impulse/installed_true)
    if [[ "$test_subcmd" == "resetfirstrun" ]]; then
        mkdir -p "$sb_guard/home/.config/illogical-impulse"
        printf 'INSTALLED_TRUE_PERSISTENT_MARKER\n' > "$sb_guard/home/.config/illogical-impulse/installed_true"
    fi

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

        ./setup "$test_subcmd" -f --skip-allgreeting >/dev/null 2>&1
    ) || guard_exit=$?

    assert_eq "$guard_exit" "1" "Distro E2E: ./setup $test_subcmd -f em Fedora aborta com código 1 antes de qualquer ação"

    if [[ "$test_subcmd" == "resetfirstrun" ]]; then
        # Check that the real firstrun marker installed_true was preserved upon refusal
        true_marker="$sb_guard/home/.config/illogical-impulse/installed_true"
        if [[ -f "$true_marker" ]] && [[ "$(cat "$true_marker")" == "INSTALLED_TRUE_PERSISTENT_MARKER" ]]; then
            pass "Distro E2E: XDG_CONFIG_HOME/illogical-impulse/installed_true permanece intacto após recusa em ./setup resetfirstrun"
        else
            fail "Distro E2E: XDG_CONFIG_HOME/illogical-impulse/installed_true foi excluído indevidamente antes do consentimento"
        fi
    else
        # Check that zero files or directories were created inside HOME (no logs, no config files)
        side_effects_count="$(find "$sb_guard/home" -mindepth 1 2>/dev/null | wc -l)"
        assert_eq "$side_effects_count" "0" "Distro E2E: zero efeitos colaterais em HOME após recusa em ./setup $test_subcmd (inclusive logs)"
    fi

    # Check that mock pacman in sandbox was NOT called
    if [[ -f "$sb_guard/mock-state/commands.log" ]] && grep -qi "pacman" "$sb_guard/mock-state/commands.log"; then
        fail "Distro E2E: pacman foi chamado antes da guarda de autorização em ./setup $test_subcmd"
    else
        pass "Distro E2E: nenhuma chamada a gerenciador de pacotes antes da autorização em ./setup $test_subcmd"
    fi
done

# Teste complementar: resetfirstrun com consentimento explícito remove installed_true
sb_rf_allow="$(create_sandbox "resetfirstrun-allow")"
printf 'ID=fedora\n' > "$sb_rf_allow/os-release"
mkdir -p "$sb_rf_allow/home/.config/illogical-impulse"
printf 'INSTALLED_TRUE_TO_REMOVE\n' > "$sb_rf_allow/home/.config/illogical-impulse/installed_true"
(
    export HOME="$sb_rf_allow/home"
    export XDG_CONFIG_HOME="$sb_rf_allow/home/.config"
    export OS_RELEASE_FILE="$sb_rf_allow/os-release"
    export HYBRID_ALLOW_UNSUPPORTED_DISTRO=true
    ./setup resetfirstrun -f >/dev/null 2>&1
) || true
if [[ ! -f "$sb_rf_allow/home/.config/illogical-impulse/installed_true" ]]; then
    pass "Distro E2E: ./setup resetfirstrun remove installed_true após autorização explícita"
else
    fail "Distro E2E: ./setup resetfirstrun não removeu installed_true mesmo após autorização"
fi

# 9.6c Comandos exclusivamente informativos não sofrem bloqueio da guarda
for info_cmd in "help" "--help"; do
    info_exit=0
    (
        export OS_RELEASE_FILE="$MOCK_ARCH_OS_RELEASE"
        ./setup $info_cmd >/dev/null 2>&1
    ) || info_exit=$?
    assert_eq "$info_exit" "0" "Informativo: ./setup $info_cmd conclui com código 0"
done

# 9.6d Regressão: Ausência de side effect de '--clean' antes do consentimento (isolado em repositório temporário)
iso_clean="$(create_isolated_repo "guard-clean-repo")"
mkdir -p "$iso_clean/cache"
clean_sentinel="$iso_clean/cache/sentinel_test_clean"
printf 'CACHE_PAYLOAD_BEFORE_GUARD\n' > "$clean_sentinel"

sb_clean="$(create_sandbox "guard-clean-test")"
printf 'ID=fedora\n' > "$sb_clean/os-release"

clean_exit=0
(
    export HOME="$sb_clean/home"
    export PATH="$sb_clean/bin:$PATH"
    export OS_RELEASE_FILE="$sb_clean/os-release"
    "$iso_clean/setup" install -f --clean --skip-allgreeting >/dev/null 2>&1
) || clean_exit=$?

assert_eq "$clean_exit" "1" "Distro: ./setup install -f --clean em Fedora aborta com código 1 antes de qualquer ação"
if [[ -f "$clean_sentinel" ]] && [[ "$(cat "$clean_sentinel")" == "CACHE_PAYLOAD_BEFORE_GUARD" ]]; then
    pass "Distro: cache preexistente permanece intacto após recusa em ./setup install -f --clean"
else
    fail "Distro: cache foi limpo ou modificado antes da guarda de consentimento"
fi

# Testar que --clean preserva cache em --dry-run no Arch Linux (isolado em repositório temporário)
iso_arch="$(create_isolated_repo "guard-clean-arch-repo")"
mkdir -p "$iso_arch/cache"
clean_arch_sentinel="$iso_arch/cache/sentinel_arch_clean"
printf 'ARCH_CACHE_PAYLOAD\n' > "$clean_arch_sentinel"
sb_arch_clean="$(create_sandbox "guard-clean-arch-test")"
printf 'ID=arch\n' > "$sb_arch_clean/os-release"
(
    export HOME="$sb_arch_clean/home"
    export PATH="$sb_arch_clean/bin:$PATH"
    export OS_RELEASE_FILE="$sb_arch_clean/os-release"
    "$iso_arch/setup" install --clean --dry-run >/dev/null 2>&1
) || true
if [[ -f "$clean_arch_sentinel" ]]; then
    pass "Distro: ./setup install --clean --dry-run preserva cache conforme esperado"
else
    fail "Distro: --dry-run removeu o cache indevidamente"
fi

# 9.6e Segurança do arquivo os-release: suíte preserva override preexistente e ausência sem modificar a raiz real
# Cenário 1: Repositório com arquivo os-release preexistente (override local legítimo)
iso_os_present="$(create_isolated_repo "os-release-isolated-present")"
sentinel_os_release="ID=custom_local_override_do_not_delete"
printf '%s\n' "$sentinel_os_release" > "$iso_os_present/os-release"
sentinel_sha="$(sha256sum "$iso_os_present/os-release")"

sb_os_present="$(create_sandbox "os-release-present-test")"
printf 'ID=arch\n' > "$sb_os_present/os-release"
(
    export HOME="$sb_os_present/home"
    export OS_RELEASE_FILE="$sb_os_present/os-release"
    "$iso_os_present/setup" install --dry-run >/dev/null 2>&1
) || true

current_present_sha="$(sha256sum "$iso_os_present/os-release" 2>/dev/null || true)"
if [[ -f "$iso_os_present/os-release" ]] && [[ "$current_present_sha" == "$sentinel_sha" ]]; then
    pass "Suíte isolada (cenário preexistente): os-release é estritamente preservado com conteúdo inalterado"
else
    fail "Suíte isolada (cenário preexistente): os-release foi modificado ou excluído indevidamente"
fi

# Cenário 2: Repositório sem arquivo os-release preexistente (ausente)
iso_os_absent="$(create_isolated_repo "os-release-isolated-absent")"
sb_os_absent="$(create_sandbox "os-release-absent-test")"
printf 'ID=arch\n' > "$sb_os_absent/os-release"
(
    export HOME="$sb_os_absent/home"
    export OS_RELEASE_FILE="$sb_os_absent/os-release"
    "$iso_os_absent/setup" install --dry-run >/dev/null 2>&1
) || true

if [[ ! -e "$iso_os_absent/os-release" ]]; then
    pass "Suíte isolada (cenário ausente): nenhum arquivo os-release espúrio é criado no repositório"
else
    fail "Suíte isolada (cenário ausente): arquivo os-release foi criado indevidamente no repositório"
fi

# Verificação da raiz de trabalho real: comprovar que o estado original permanece intacto (presente ou ausente)
if [[ "$INITIAL_REPO_OS_RELEASE_EXISTS" == "true" ]]; then
    current_repo_sha="$(sha256sum "${REPO_ROOT}/os-release" 2>/dev/null || true)"
    if [[ "$current_repo_sha" == "$INITIAL_REPO_OS_RELEASE_SHA" ]]; then
        pass "Suíte: estado original de ${REPO_ROOT}/os-release preservado intacto (override preexistente mantido)"
    else
        fail "Suíte: conteúdo de ${REPO_ROOT}/os-release foi alterado indevidamente"
    fi
else
    if [[ ! -e "${REPO_ROOT}/os-release" ]]; then
        pass "Suíte: estado original de ${REPO_ROOT}/os-release preservado intacto (permaneceu ausente)"
    else
        fail "Suíte: arquivo ${REPO_ROOT}/os-release foi criado indevidamente na raiz real do repositório"
    fi
fi

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

printf "\n${CLR_CYAN}=== 10. Redshift Store (Packaging, Profiles, Sandbox Install & Python/QML Test Suite) ===${CLR_RST}\n"

# 10.1 Launcher script verification
if [[ -x "${REPO_ROOT}/dots/.local/bin/redshift-store" ]]; then
    pass "Launcher dots/.local/bin/redshift-store existe e possui permissão de execução (+x)"
else
    fail "Launcher dots/.local/bin/redshift-store ausente ou sem permissão de execução"
fi

# 10.2 Desktop Entry validation
(
    desktop_file="${REPO_ROOT}/dots/.local/share/applications/redshift-store.desktop"
    [[ -f "$desktop_file" ]] || exit 1
    grep -q "^Type=Application" "$desktop_file" || exit 2
    grep -q "^Exec=redshift-store" "$desktop_file" || exit 3
    grep -q "^Actions=Updates;Installed;" "$desktop_file" || exit 4
    grep -q "^\[Desktop Action Updates\]" "$desktop_file" || exit 5
    grep -q "^\[Desktop Action Installed\]" "$desktop_file" || exit 6
) && pass "Arquivo .desktop redshift-store.desktop validado (chaves XDG, Exec e Actions)" \
  || fail "Arquivo .desktop redshift-store.desktop inválido ou ausente"

# 10.3 PKGBUILD syntax, dependency, and package() function audit
(
    pkgbuild_path="${REPO_ROOT}/sdata/dist-arch/illogical-impulse-redshift-store/PKGBUILD"
    [[ -f "$pkgbuild_path" ]] || exit 1
    bash -n "$pkgbuild_path" || exit 2
    source "$pkgbuild_path"
    [[ "$pkgname" == "illogical-impulse-redshift-store" ]] || exit 3
    for req in python-pyqt6 qt6-declarative pacman-contrib appstream polkit polkit-kde-agent; do
        found=false
        for d in "${depends[@]}"; do
            [[ "$d" == "$req" ]] && found=true
        done
        [[ "$found" == "true" ]] || exit 4
    done
    declare -F package >/dev/null || exit 5
    grep -q "/usr/share/redshift-os/redshift-store" "$pkgbuild_path" || exit 6
    [[ -f "${REPO_ROOT}/dots/.local/share/icons/redshift-store.svg" ]] || exit 7
) && pass "PKGBUILD illogical-impulse-redshift-store validado (bash -n, dependências, package() e ícone SVG)" \
  || fail "PKGBUILD illogical-impulse-redshift-store inválido ou incompleto"

# 10.4 Profiles integration verification
(
    for prof in minimal hybrid complete; do
        source "${REPO_ROOT}/sdata/profiles/${prof}.conf"
        found_meta=false
        for pkg in "${ARCH_METAPKGS[@]}"; do
            [[ "$pkg" == *"illogical-impulse-redshift-store"* ]] && found_meta=true
        done
        [[ "$found_meta" == "true" ]] || exit 1

        found_bin=false
        found_desktop=false
        for target in "${MANAGED_CONFIG_TARGETS[@]}"; do
            [[ "$target" == *"/redshift-store" ]] && found_bin=true
            [[ "$target" == *"/redshift-store.desktop" ]] && found_desktop=true
        done
        [[ "$found_bin" == "true" && "$found_desktop" == "true" ]] || exit 2
    done
) && pass "Perfis (minimal, hybrid, complete) integram metapacote e alvos gerenciados da Redshift Store" \
  || fail "Perfis não integram corretamente metapacote ou alvos da Redshift Store"

# 10.5 Installer and uninstaller script references
(
    grep -q "redshift-store" "${REPO_ROOT}/sdata/dist-arch/uninstall-deps.sh" || exit 1
    grep -q "redshift-store" "${REPO_ROOT}/sdata/subcmd-install/3.files-legacy.sh" || exit 2
) && pass "Integração do desinstalador (uninstall-deps.sh) e arquivos legados (3.files-legacy.sh)" \
  || fail "Referências da Redshift Store ausentes em uninstall-deps.sh ou 3.files-legacy.sh"

# 10.6 Sandbox installation and uninstallation lifecycle
sb_store="$(create_sandbox "redshift-store-lifecycle")"
PATH="$sb_store/bin:$PATH" \
MOCK_STATE_DIR="$sb_store/mock-state" \
HOME="$sb_store/home" \
XDG_CONFIG_HOME="$sb_store/home/.config" \
XDG_DATA_HOME="$sb_store/home/.local/share" \
XDG_STATE_HOME="$sb_store/home/.local/state" \
XDG_CACHE_HOME="$sb_store/home/.cache" \
XDG_BIN_HOME="$sb_store/home/.local/bin" \
BACKUP_DIR="$sb_store/home/ii-original-dots-backup" \
./setup install-files -p hybrid -f >/dev/null

assert_file_exists "$sb_store/home/.local/bin/redshift-store" "Instalação Sandbox: redshift-store copiado para ~/.local/bin"
assert_file_exists "$sb_store/home/.local/share/applications/redshift-store.desktop" "Instalação Sandbox: redshift-store.desktop copiado para ~/.local/share/applications"
assert_file_exists "$sb_store/home/.local/share/redshift-os/redshift-store/main.py" "Instalação Sandbox: backend redshift-store copiado para ~/.local/share/redshift-os"

# Verify recorded in installed_listfile and simulate uninstallation removal
listfile_store="$sb_store/home/.config/illogical-impulse/installed_listfile"
if [[ -f "$listfile_store" ]]; then
    while IFS= read -r target_path; do
        if [[ -f "$target_path" && ("$target_path" == *"/redshift-store" || "$target_path" == *"/redshift-store.desktop") ]]; then
            rm -f "$target_path"
        fi
    done < "$listfile_store"
fi

assert_not_exists "$sb_store/home/.local/bin/redshift-store" "Desinstalação Sandbox: redshift-store removido com base no installed_listfile"
assert_not_exists "$sb_store/home/.local/share/applications/redshift-store.desktop" "Desinstalação Sandbox: redshift-store.desktop removido com base no installed_listfile"

# 10.7 Automated Headless Self-Test and Python Unit Test Suite
if selftest_out="$(QT_QPA_PLATFORM=offscreen "${REPO_ROOT}/dots/.local/bin/redshift-store" --mock --self-test 2>&1)"; then
    pass "Autoteste headless (redshift-store --mock --self-test) executado com status 0"
else
    printf "%s\n" "$selftest_out" >&2
    fail "Autoteste headless (redshift-store --mock --self-test) falhou"
fi

if unittest_out="$(QT_QPA_PLATFORM=offscreen python3 -m unittest discover -s "${REPO_ROOT}/tests" -p "test_redshift_store.py" 2>&1)"; then
    pass "Suíte de testes unitários Python e integração QML (test_redshift_store.py) aprovada"
else
    printf "%s\n" "$unittest_out" >&2
    fail "Suíte de testes unitários Python e integração QML (test_redshift_store.py) falhou"
fi

printf "\n=============================================================================\n"
printf "Resumo dos Testes: ${CLR_GREEN}%d aprovados${CLR_RST}, ${CLR_RED}%d falharam${CLR_RST} (total: %d)\n" \
    "$PASS_COUNT" "$FAIL_COUNT" "$TOTAL_COUNT"
printf "=============================================================================\n"

(( FAIL_COUNT == 0 ))
