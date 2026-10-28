#!/usr/bin/env python3
import os
import sys
import json
import fcntl
import subprocess

STATE_DIR = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
CAEL_STATE_DIR = os.path.join(STATE_DIR, "caelestia")
STATE_FILE = os.path.join(CAEL_STATE_DIR, "gamemode.json")
RUNTIME_DIR = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
LOCK_FILE = os.path.join(RUNTIME_DIR, "caelestia-gamemode.lock")

OPTIONS = [
    "general:gaps_in",
    "general:gaps_out",
    "general:border_size",
    "decoration:rounding",
    "animations:enabled",
    "decoration:shadow:enabled",
    "decoration:blur:enabled",
]

DEFAULT_SAVED = {
    "general:gaps_in": {"type": "css", "value": "4 4 4 4"},
    "general:gaps_out": {"type": "css", "value": "5 5 5 5"},
    "general:border_size": {"type": "int", "value": 1},
    "decoration:rounding": {"type": "int", "value": 18},
    "animations:enabled": {"type": "bool", "value": True},
    "decoration:shadow:enabled": {"type": "bool", "value": True},
    "decoration:blur:enabled": {"type": "bool", "value": True},
}

def is_using_lua():
    try:
        res = subprocess.run(["hyprctl", "eval", "return 1"], capture_output=True, text=True, timeout=2)
        return res.returncode == 0
    except Exception:
        return False

def query_option(key):
    try:
        res = subprocess.run(["hyprctl", "-j", "getoption", key], capture_output=True, text=True, check=True, timeout=2)
        data = json.loads(res.stdout)
        for k in ("css", "int", "bool", "float", "str"):
            if k in data:
                return {"type": k, "value": data[k]}
    except Exception as e:
        sys.stderr.write(f"Warning: failed to query option {key}: {e}\n")
    return None

def query_all_options():
    result = {}
    for opt in OPTIONS:
        val = query_option(opt)
        if val is not None:
            result[opt] = val
        elif opt in DEFAULT_SAVED:
            result[opt] = DEFAULT_SAVED[opt]
    return result

def css_to_lua_table(css_str):
    parts = [int(x) for x in str(css_str).split()]
    if len(parts) == 1:
        top = right = bottom = left = parts[0]
    elif len(parts) == 2:
        top = bottom = parts[0]
        right = left = parts[1]
    elif len(parts) >= 4:
        top, right, bottom, left = parts[0], parts[1], parts[2], parts[3]
    else:
        top = right = bottom = left = 0
    return f"{{ top = {top}, right = {right}, bottom = {bottom}, left = {left} }}"

def apply_hyprland_lua(lua_body):
    cmd = ["hyprctl", "eval", lua_body]
    res = subprocess.run(cmd, capture_output=True, text=True, timeout=3)
    if res.returncode != 0:
        raise RuntimeError(f"hyprctl eval failed ({res.returncode}): {res.stderr.strip() or res.stdout.strip()}")

def apply_hyprland_legacy(keywords):
    batch = "; ".join([f"keyword {k} {v}" for k, v in keywords.items()])
    res = subprocess.run(["hyprctl", "--batch", batch], capture_output=True, text=True, timeout=3)
    if res.returncode != 0:
        raise RuntimeError(f"hyprctl legacy keyword failed: {res.stderr.strip() or res.stdout.strip()}")

def apply_gamemode_on():
    if is_using_lua():
        lua = """hl.config({
    general = {
        gaps_in = 0,
        gaps_out = 0,
        border_size = 0
    },
    decoration = {
        rounding = 0,
        shadow = { enabled = false },
        blur = { enabled = false }
    },
    animations = {
        enabled = false
    }
})"""
        apply_hyprland_lua(lua)
    else:
        keywords = {
            "general:gaps_in": 0,
            "general:gaps_out": 0,
            "general:border_size": 0,
            "decoration:rounding": 0,
            "animations:enabled": 0,
            "decoration:shadow:enabled": 0,
            "decoration:blur:enabled": 0,
        }
        apply_hyprland_legacy(keywords)

def apply_gamemode_off(saved):
    gaps_in = saved.get("general:gaps_in", DEFAULT_SAVED["general:gaps_in"])
    gaps_out = saved.get("general:gaps_out", DEFAULT_SAVED["general:gaps_out"])
    border_size = saved.get("general:border_size", DEFAULT_SAVED["general:border_size"])
    rounding = saved.get("decoration:rounding", DEFAULT_SAVED["decoration:rounding"])
    anim = saved.get("animations:enabled", DEFAULT_SAVED["animations:enabled"])
    shadow = saved.get("decoration:shadow:enabled", DEFAULT_SAVED["decoration:shadow:enabled"])
    blur = saved.get("decoration:blur:enabled", DEFAULT_SAVED["decoration:blur:enabled"])

    if is_using_lua():
        lua = f"""hl.config({{
    general = {{
        gaps_in = {css_to_lua_table(gaps_in['value'])},
        gaps_out = {css_to_lua_table(gaps_out['value'])},
        border_size = {int(border_size['value'])}
    }},
    decoration = {{
        rounding = {int(rounding['value'])},
        shadow = {{ enabled = {'true' if shadow['value'] else 'false'} }},
        blur = {{ enabled = {'true' if blur['value'] else 'false'} }}
    }},
    animations = {{
        enabled = {'true' if anim['value'] else 'false'}
    }}
}})"""
        apply_hyprland_lua(lua)
    else:
        keywords = {
            "general:gaps_in": gaps_in["value"],
            "general:gaps_out": gaps_out["value"],
            "general:border_size": border_size["value"],
            "decoration:rounding": rounding["value"],
            "animations:enabled": 1 if anim["value"] else 0,
            "decoration:shadow:enabled": 1 if shadow["value"] else 0,
            "decoration:blur:enabled": 1 if blur["value"] else 0,
        }
        apply_hyprland_legacy(keywords)

def load_state():
    if not os.path.exists(STATE_FILE):
        return None
    try:
        with open(STATE_FILE, "r") as f:
            return json.load(f)
    except Exception:
        return None

def save_state(state):
    os.makedirs(CAEL_STATE_DIR, exist_ok=True)
    temp_file = STATE_FILE + ".tmp"
    with open(temp_file, "w") as f:
        json.dump(state, f, indent=2)
    os.replace(temp_file, STATE_FILE)

def get_status():
    state = load_state()
    if not state or not state.get("active", False):
        return "off"
    
    # Verify with compositor
    gaps_in = query_option("general:gaps_in")
    rounding = query_option("decoration:rounding")
    if gaps_in and gaps_in.get("value") == "0 0 0 0" and rounding and rounding.get("value") == 0:
        return "on"
    else:
        # Compositor was reloaded/reset externally; sync state
        state["active"] = False
        save_state(state)
        return "off"

def cmd_status():
    print(get_status())
    return 0

def cmd_on():
    status = get_status()
    if status == "on":
        print("on")
        return 0
    
    current_opts = query_all_options()
    apply_gamemode_on()
    state = {
        "active": True,
        "saved": current_opts
    }
    save_state(state)
    print("on")
    return 0

def cmd_off():
    status = get_status()
    state = load_state()
    saved = state.get("saved", DEFAULT_SAVED) if state else DEFAULT_SAVED
    
    apply_gamemode_off(saved)
    if state:
        state["active"] = False
        save_state(state)
    print("off")
    return 0

def cmd_toggle():
    status = get_status()
    if status == "on":
        return cmd_off()
    else:
        return cmd_on()

def cmd_reapply():
    state = load_state()
    if state and state.get("active", False):
        apply_gamemode_on()
        print("on")
    else:
        print("off")
    return 0

def main():
    action = sys.argv[1] if len(sys.argv) > 1 else "status"

    os.makedirs(RUNTIME_DIR, exist_ok=True)
    with open(LOCK_FILE, "w") as lock_fd:
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_EX)
        except Exception:
            pass

        if action in ("status", "--status"):
            return cmd_status()
        elif action in ("on", "enable", "--enable"):
            return cmd_on()
        elif action in ("off", "disable", "--disable"):
            return cmd_off()
        elif action in ("toggle", "--toggle"):
            return cmd_toggle()
        elif action in ("reapply", "--reapply"):
            return cmd_reapply()
        else:
            sys.stderr.write(f"Usage: {sys.argv[0]} [status|on|off|toggle|reapply]\n")
            return 2

if __name__ == "__main__":
    sys.exit(main())
