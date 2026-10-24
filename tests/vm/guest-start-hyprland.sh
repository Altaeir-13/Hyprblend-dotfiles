#!/usr/bin/env bash
# Helper to launch Hyprland inside the VM for automated graphical testing
set -euo pipefail

if ! systemd-detect-virt -q 2>/dev/null; then
    echo "REFUSING: no hypervisor detected. This script must only run inside the test VM." >&2
    exit 3
fi

# Ensure user is in necessary groups
sudo usermod -aG video,render,seat "$USER" 2>/dev/null || true

# Ensure seatd is running if available
if systemctl list-unit-files seatd.service &>/dev/null; then
    sudo systemctl enable --now seatd 2>/dev/null || true
fi

# Ensure /dev/uinput permissions
if [[ -e /dev/uinput ]]; then
    sudo chmod 660 /dev/uinput 2>/dev/null || true
fi

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_TYPE=wayland
export XDG_SESSION_DESKTOP=Hyprland
export WLR_NO_HARDWARE_CURSORS=1
export LIBSEAT_BACKEND=seatd

# Kill any existing Hyprland session
pkill -9 -f "Hyprland" 2>/dev/null || true
pkill -9 -f "quickshell" 2>/dev/null || true
sleep 1

# Launch Hyprland
echo "Starting Hyprland session in VM..."
Hyprland > "$HOME/hyprland-session.log" 2>&1 &
HYPR_PID=$!

echo "Waiting for Wayland display to initialize..."
for i in {1..30}; do
    if ls "$XDG_RUNTIME_DIR"/wayland-* 1>/dev/null 2>&1; then
        export WAYLAND_DISPLAY="$(basename "$(ls "$XDG_RUNTIME_DIR"/wayland-* | head -1)")"
        echo "Hyprland running on $WAYLAND_DISPLAY (PID $HYPR_PID)"
        break
    fi
    sleep 0.5
done

if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
    echo "ERROR: Hyprland failed to create wayland socket" >&2
    cat "$HOME/hyprland-session.log" | tail -n 20 >&2
    exit 1
fi

sleep 3
hyprctl monitors || true
echo "Hyprland graphical session ready."
