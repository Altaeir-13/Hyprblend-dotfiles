#!/usr/bin/env bash
# =============================================================================
# Post-install verification — run INSIDE the disposable VM, as the unprivileged
# test user, after:  ./setup install -p <profile> -f ...
#
#   guest-verify.sh <minimal|hybrid|complete> [--seeded]
#
#   --seeded  also assert that the user files seeded by guest-seed.sh survived.
#
# Read-only except for a scratch dir under $TMPDIR. NEVER run on the host:
# it refuses to run unless it detects a hypervisor (override: ALLOW_HOST=1 is
# deliberately NOT provided).
# =============================================================================
set -uo pipefail

profile="${1:?usage: guest-verify.sh <minimal|hybrid|complete> [--seeded]}"
seeded=false; [[ "${2:-}" == "--seeded" ]] && seeded=true
case "$profile" in minimal|hybrid|complete) ;; *) echo "bad profile"; exit 2;; esac

if ! systemd-detect-virt -q 2>/dev/null; then
    echo "REFUSING: no hypervisor detected. This script must only run inside the test VM." >&2
    exit 3
fi

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
XDG_BIN_HOME="${XDG_BIN_HOME:-$HOME/.local/bin}"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "[PASS] $*"; }
bad()  { FAIL=$((FAIL+1)); echo "[FAIL] $*"; }
chk()  { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }

echo "== VM: $(systemd-detect-virt) | user: $(id -un) | HOME=$HOME | profile=$profile =="

# --- files common to all profiles -------------------------------------------
chk "quickshell/ii/shell.qml"            test -f "$XDG_CONFIG_HOME/quickshell/ii/shell.qml"
chk "ui-switch.sh executable (all profiles)" test -x "$XDG_CONFIG_HOME/quickshell/ui-switch.sh"
chk "rice-lock executable"               test -x "$XDG_BIN_HOME/rice-lock"
chk "hypr/hyprland.lua"                  test -f "$XDG_CONFIG_HOME/hypr/hyprland.lua"
chk "hypr/hyprlock/ synced"              test -d "$XDG_CONFIG_HOME/hypr/hyprlock"
chk "installed_listfile exists"          test -s "$XDG_CONFIG_HOME/illogical-impulse/installed_listfile"
chk "installed_true marker"              test -f "$XDG_CONFIG_HOME/illogical-impulse/installed_true"
chk "kb layout us,br in custom/general.lua" grep -q 'us,br' "$XDG_CONFIG_HOME/hypr/custom/general.lua"

# --- profile-specific ---------------------------------------------------------
if [[ "$profile" == minimal ]]; then
    chk "minimal: NO caelestia-hybrid dir"   test ! -e "$XDG_CONFIG_HOME/quickshell/caelestia-hybrid"
    chk "minimal: ui-switch state = end4"    test "$(cat "$XDG_STATE_HOME/quickshell/ui-switch/current" 2>/dev/null)" = end4
    chk "minimal: caelestia plugin pkg absent" bash -c '! pacman -Q illogical-impulse-caelestia-plugin'
else
    chk "caelestia-hybrid/shell.qml"         test -f "$XDG_CONFIG_HOME/quickshell/caelestia-hybrid/shell.qml"
    chk "caelestia/shell.json"               test -f "$XDG_CONFIG_HOME/caelestia/shell.json"
    if ! $seeded; then
        chk "no hardware monitors/ shipped"      test ! -e "$XDG_CONFIG_HOME/caelestia/monitors/eDP-1"
    else
        chk "seed: caelestia/monitors/eDP-1 kept" test -f "$XDG_CONFIG_HOME/caelestia/monitors/eDP-1"
    fi
    chk "plugin package installed"           pacman -Q illogical-impulse-caelestia-plugin
    chk "Caelestia/qmldir at /usr/lib/qt6/qml" test -f /usr/lib/qt6/qml/Caelestia/qmldir
fi
if [[ "$profile" == complete ]]; then
    for p in easyeffects fish foot kitty starship; do chk "complete: pkg $p" pacman -Q "$p"; done
fi

# --- portability: no developer-machine leakage in installed user files --------
leak="$(grep -rIl -e '/home/greyrat' -e 'quickshell-port' "$XDG_CONFIG_HOME/quickshell" "$XDG_CONFIG_HOME/hypr" "$XDG_BIN_HOME/rice-lock" 2>/dev/null | head -5)"
if [[ -z "$leak" ]]; then ok "no /home/greyrat or quickshell-port in installed files"
else bad "developer paths leaked into: $leak"; fi

# --- native plugin: isolated dlopen of every plugin .so (hybrid/complete) -----
if [[ "$profile" != minimal && -d /usr/lib/qt6/qml/Caelestia ]]; then
    while IFS= read -r so; do
        if python3 - "$so" <<'PY' 2>/tmp/dlopen.err
import ctypes, sys
ctypes.CDLL(sys.argv[1], mode=ctypes.RTLD_GLOBAL)
PY
        then ok "dlopen (fresh process): ${so#/usr/lib/qt6/qml/}"
        else bad "dlopen FAILED: ${so#/usr/lib/qt6/qml/} :: $(head -1 /tmp/dlopen.err)"; fi
    done < <(find /usr/lib/qt6/qml/Caelestia -name 'lib*plugin.so' | sort)

    out="$(/usr/bin/env bash "$(dirname "$0")/check-plugin-package.sh" /usr/lib/qt6/qml/.. 2>&1 | tail -1)"
    echo "[INFO] ELF layout check on installed tree: $out"
fi

# --- seeded user files must have survived ------------------------------------
if $seeded; then
    chk "seed: ~/.config/hypr/monitors.lua kept"          test -f "$XDG_CONFIG_HOME/hypr/monitors.lua"
    chk "seed: ~/.config/hypr/workspaces.lua kept"        test -f "$XDG_CONFIG_HOME/hypr/workspaces.lua"
    chk "seed: quickshell/my-custom-widget kept"          test -f "$XDG_CONFIG_HOME/quickshell/my-custom-widget/shell.qml"
    chk "seed: hypr/custom/user-extra.lua kept"           test -f "$XDG_CONFIG_HOME/hypr/custom/user-extra.lua"
    chk "seed: fish/conf.d/secret.fish kept"              test -f "$XDG_CONFIG_HOME/fish/conf.d/secret.fish"
    chk "seed: original fuzzel.ini in backup dir"         grep -q old_fuzzel_config "$HOME/ii-original-dots-backup/.config/fuzzel/fuzzel.ini"
fi

echo; echo "RESULT: $PASS pass, $FAIL fail"
(( FAIL == 0 ))
