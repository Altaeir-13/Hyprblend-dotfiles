#!/usr/bin/env bash
# VM management helper for automated testing
set -euo pipefail

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/workspace" && pwd)"
SSH_KEY="$WORKSPACE_DIR/ssh/id_ed25519"
SSH_PORT=2222
SSH_USER="arch"
SSH_HOST="127.0.0.1"
SSH_OPTS=(-i "$SSH_KEY" -p "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR)

start_vm() {
    local disk_img="$1"
    local name="${2:-arch-test-vm}"

    if pgrep -f "qemu-system-x86_64.*$name" >/dev/null; then
        echo "VM $name already running"
        return 0
    fi

    # Ensure fresh NVRAM vars if needed
    if [[ ! -f "$WORKSPACE_DIR/OVMF_VARS.4m.fd" ]]; then
        cp /usr/share/edk2/x64/OVMF_VARS.4m.fd "$WORKSPACE_DIR/OVMF_VARS.4m.fd"
    fi

    rm -f "$WORKSPACE_DIR/qemu-monitor.sock" "$WORKSPACE_DIR/qemu.pid"

    qemu-system-x86_64 \
        -name "$name" \
        -machine q35,accel=kvm \
        -cpu host \
        -smp 4 \
        -m 4096 \
        -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
        -drive if=pflash,format=raw,file="$WORKSPACE_DIR/OVMF_VARS.4m.fd" \
        -drive file="$disk_img",if=virtio \
        -drive file="$WORKSPACE_DIR/cidata.img",format=raw,index=1,media=disk \
        -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:2222-:22 \
        -device virtio-vga-gl \
        -display egl-headless,rendernode=/dev/dri/renderD128 \
        -monitor unix:"$WORKSPACE_DIR/qemu-monitor.sock",server,nowait \
        -pidfile "$WORKSPACE_DIR/qemu.pid" \
        -daemonize

    echo "Started VM $name with disk $disk_img"
}

stop_vm() {
    if [[ -f "$WORKSPACE_DIR/qemu.pid" ]]; then
        local pid
        pid="$(cat "$WORKSPACE_DIR/qemu.pid" 2>/dev/null || true)"
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo "Stopping VM (PID $pid)..."
            # Try graceful ACPI / ssh shutdown first
            ssh "${SSH_OPTS[@]}" "$SSH_USER@$SSH_HOST" 'sudo poweroff' 2>/dev/null || true
            for i in {1..15}; do
                if ! kill -0 "$pid" 2>/dev/null; then break; fi
                sleep 1
            done
            if kill -0 "$pid" 2>/dev/null; then
                echo "Force terminating PID $pid"
                kill -9 "$pid" 2>/dev/null || true
            fi
        fi
        rm -f "$WORKSPACE_DIR/qemu.pid" "$WORKSPACE_DIR/qemu-monitor.sock"
    fi
    pkill -f "qemu-system-x86_64" 2>/dev/null || true
}

wait_ssh() {
    local max_attempts="${1:-60}"
    echo -n "Waiting for SSH on 127.0.0.1:$SSH_PORT..."
    for ((i=1; i<=max_attempts; i++)); do
        if ssh "${SSH_OPTS[@]}" "$SSH_USER@$SSH_HOST" 'true' 2>/dev/null; then
            echo " Connected! (attempt $i)"
            return 0
        fi
        echo -n "."
        sleep 2
    done
    echo " FAILED to connect after $max_attempts attempts" >&2
    return 1
}

wait_cloud_init() {
    echo "Waiting for cloud-init to finish inside VM..."
    ssh "${SSH_OPTS[@]}" "$SSH_USER@$SSH_HOST" 'cloud-init status --wait' || true
}

vm_ssh() {
    ssh "${SSH_OPTS[@]}" "$SSH_USER@$SSH_HOST" "$@"
}

vm_scp() {
    scp -i "$SSH_KEY" -P "$SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR "$@"
}

vm_screenshot() {
    local outfile="${1:-$WORKSPACE_DIR/screenshot.png}"
    local ppm="/tmp/vm_screen_$$.ppm"
    if [[ -S "$WORKSPACE_DIR/qemu-monitor.sock" ]]; then
        python3 - "$WORKSPACE_DIR/qemu-monitor.sock" "$ppm" <<'PY' 2>/dev/null || true
import socket, sys, time
sock_path = sys.argv[1]
ppm_path = sys.argv[2]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sock_path)
s.recv(1024)
s.sendall(f"screendump {ppm_path}\n".encode())
time.sleep(0.5)
s.close()
PY
        if [[ -f "$ppm" ]]; then
            magick "$ppm" "$outfile" 2>/dev/null || convert "$ppm" "$outfile" 2>/dev/null || cp "$ppm" "$outfile"
            rm -f "$ppm"
            echo "Saved monitor screenshot to $outfile"
            return 0
        fi
    fi
    # Fallback to grim inside VM
    vm_ssh 'XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-1 grim /tmp/grim.png 2>/dev/null || true'
    vm_scp "$SSH_USER@$SSH_HOST:/tmp/grim.png" "$outfile" 2>/dev/null || true
    if [[ -f "$outfile" ]]; then
        echo "Saved grim screenshot to $outfile"
        return 0
    fi
    echo "WARNING: Could not take screenshot" >&2
    return 1
}

case "${1:-}" in
    start) shift; start_vm "$@" ;;
    stop) stop_vm ;;
    wait-ssh) shift; wait_ssh "$@" ;;
    wait-cloud-init) wait_cloud_init ;;
    ssh) shift; vm_ssh "$@" ;;
    scp) shift; vm_scp "$@" ;;
    screenshot) shift; vm_screenshot "$@" ;;
    *) echo "Usage: $0 {start <disk> [name]|stop|wait-ssh [attempts]|wait-cloud-init|ssh <cmd>|scp <args>|screenshot <outfile>}"; exit 1 ;;
esac
