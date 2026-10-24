#!/usr/bin/env bash
# Seeds pre-existing user files inside the VM BEFORE the first install, so the
# backup / no-deletion guarantees are tested for real (not only in the mock
# suite). Refuses to run outside a hypervisor.
set -euo pipefail
systemd-detect-virt -q || { echo "REFUSING: not inside a VM" >&2; exit 3; }

C="${XDG_CONFIG_HOME:-$HOME/.config}"
mkdir -p "$C/hypr/custom" "$C/quickshell/my-custom-widget" "$C/caelestia/monitors" \
         "$C/fish/conf.d" "$C/fuzzel"
echo '# user hypridle'                > "$C/hypr/hypridle.conf"
echo '# nwg-displays monitors'        > "$C/hypr/monitors.lua"
echo '# nwg-displays workspaces'      > "$C/hypr/workspaces.lua"
echo '# user rule'                    > "$C/hypr/custom/user-extra.lua"
printf 'import QtQuick\nItem {}\n'    > "$C/quickshell/my-custom-widget/shell.qml"
echo '{"scale": 1.6}'                 > "$C/caelestia/monitors/eDP-1"
echo '{"custom":"user_shell_json"}'   > "$C/caelestia/shell.json"
echo 'set -gx SECRET_TOKEN 123'       > "$C/fish/conf.d/secret.fish"
echo 'old_fuzzel_config'              > "$C/fuzzel/fuzzel.ini"
echo "seeded user files under $C"
