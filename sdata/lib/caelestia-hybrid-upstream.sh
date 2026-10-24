#!/usr/bin/env bash
# Reproducible verification and overlay management for caelestia-hybrid
# Upstream: https://github.com/caelestia-dots/shell.git

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HYBRID_DIR="${REPO_ROOT}/dots/.config/quickshell/caelestia-hybrid"
REV_FILE="${HYBRID_DIR}/UPSTREAM_REVISION"

CUSTOM_FILES=(
    "HYBRID_MANIFEST.md"
    "UPSTREAM_REVISION"
    "modules/VideoWallpaperBridge.qml"
    "modules/bar/components/UiFrontendSwitchButton.qml"
    "modules/bar/popouts/StatusCenter.qml"
    "scripts/caelestia-runtime-binds.sh"
    "scripts/end4-theme-bridge.sh"
    "scripts/nightlight.sh"
    "scripts/video-wallpaper-sync.sh"
)

MODIFIED_FILES=(
    "assets/kurukuru.gif"
    "modules/Shortcuts.qml"
    "modules/bar/Bar.qml"
    "modules/bar/components/Clock.qml"
    "modules/bar/components/StatusIcons.qml"
    "modules/bar/popouts/ClipWrapper.qml"
    "modules/bar/popouts/Content.qml"
    "modules/bar/popouts/Wrapper.qml"
    "modules/drawers/Panels.qml"
    "modules/session/Content.qml"
    "modules/utilities/Wrapper.qml"
    "modules/utilities/cards/Toggles.qml"
    "services/Colours.qml"
    "services/Wallpapers.qml"
    "shell.qml"
)

usage() {
    cat <<EOF
Usage: $0 <command> [args]

Commands:
  status                          Print pinned upstream revision and tracked overlay files
  verify <upstream-clone-dir>     Verify caelestia-hybrid against an upstream caelestia-dots/shell clone
  export-diff <upstream-dir> <out-patch>
                                  Export a unified diff of all modified QML files against upstream
EOF
}

cmd_status() {
    local rev
    rev="$(tr -d '\r\n' < "$REV_FILE")"
    echo "Pinned upstream repository : https://github.com/caelestia-dots/shell.git"
    echo "Pinned upstream revision   : $rev"
    echo "Custom files               : ${#CUSTOM_FILES[@]}"
    echo "Modified upstream files    : ${#MODIFIED_FILES[@]}"
}

cmd_verify() {
    local upstream_dir="${1:-}"
    local expected_rev
    expected_rev="$(tr -d '\r\n' < "$REV_FILE")"
    echo "Expected revision: $expected_rev"

    if [[ -n "$upstream_dir" ]]; then
        if [[ ! -d "$upstream_dir" ]]; then
            echo "Error: Provide a valid path to a caelestia-dots/shell clone." >&2
            exit 1
        fi
        local actual_rev
        actual_rev="$(git -C "$upstream_dir" rev-parse HEAD 2>/dev/null || echo "unknown")"
        echo "Upstream HEAD    : $actual_rev"
        if [[ "$expected_rev" != "$actual_rev" ]]; then
            echo "WARNING: Upstream clone HEAD does not match UPSTREAM_REVISION." >&2
            exit 1
        fi
    fi

    local f
    for f in "${CUSTOM_FILES[@]}"; do
        if [[ ! -f "${HYBRID_DIR}/${f}" ]]; then
            echo "MISSING custom file: ${f}" >&2
            exit 1
        fi
    done

    for f in "${MODIFIED_FILES[@]}"; do
        if [[ ! -f "${HYBRID_DIR}/${f}" ]]; then
            echo "MISSING modified file: ${f}" >&2
            exit 1
        fi
    done

    echo "All ${#CUSTOM_FILES[@]} custom files and ${#MODIFIED_FILES[@]} modified files verified."
}

cmd_export_diff() {
    local upstream_dir="${1:-}"
    local out_patch="${2:-}"
    if [[ -z "$upstream_dir" ]] || [[ -z "$out_patch" ]]; then
        usage
        exit 1
    fi

    : > "$out_patch"
    local f
    for f in "${MODIFIED_FILES[@]}"; do
        if [[ "$f" == *.gif ]]; then
            continue
        fi
        diff -u "${upstream_dir}/${f}" "${HYBRID_DIR}/${f}" >> "$out_patch" || true
    done
    echo "Exported unified diff to: $out_patch"
}

case "${1:-status}" in
    status|--status)
        cmd_status
        ;;
    verify|--verify)
        cmd_verify "${2:-}"
        ;;
    export-diff|--export-diff)
        cmd_export_diff "${2:-}" "${3:-}"
        ;;
    *)
        usage
        exit 2
        ;;
esac
