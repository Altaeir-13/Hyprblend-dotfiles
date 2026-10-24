#!/usr/bin/env bash

set -euo pipefail

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

END4_SWITCH="$XDG_CONFIG_HOME/quickshell/ii/scripts/colors/switchwall.sh"
END4_COLORS="$XDG_STATE_HOME/quickshell/user/generated/colors.json"
END4_WALL_FILE="$XDG_STATE_HOME/quickshell/user/generated/wallpaper/path.txt"
END4_CONFIG="$XDG_CONFIG_HOME/illogical-impulse/config.json"

CAEL_STATE="$XDG_STATE_HOME/caelestia"
CAEL_WALL_DIR="$CAEL_STATE/wallpaper"
CAEL_SCHEME="$CAEL_STATE/scheme.json"
CAEL_WALL="$CAEL_WALL_DIR/path.txt"

mkdir -p "$CAEL_WALL_DIR"

# Se o bridge recebeu argumentos, eles pertencem ao
# switchwall.sh original do end-4.
if (( $# > 0 )); then
    "$END4_SWITCH" "$@"
fi


# ------------------------------------------------------------
# Wallpaper
# ------------------------------------------------------------

is_video_path() {
    case "${1,,}" in
        *.mp4|*.webm|*.mkv|*.mov|*.m4v|*.avi)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

wallpaper=""

if [[ -f "$END4_WALL_FILE" ]]; then
    wallpaper="$(head -n 1 "$END4_WALL_FILE" | tr -d '\r\n')"
fi

if [[ -f "$END4_CONFIG" ]]; then
    if [[ -z "$wallpaper" ]]; then
        wallpaper="$(
            jq -r '.background.wallpaperPath // empty' \
                "$END4_CONFIG" 2>/dev/null || true
        )"
    fi

    if [[ -n "$wallpaper" ]] && is_video_path "$wallpaper"; then
        thumb="$(
            jq -r '.background.thumbnailPath // empty' \
                "$END4_CONFIG" 2>/dev/null || true
        )"
        if [[ -n "$thumb" && -f "$thumb" ]]; then
            wallpaper="$thumb"
        fi
    fi
fi

if [[ -n "$wallpaper" ]]; then
    printf '%s\n' "$wallpaper" > "$CAEL_WALL.tmp"
    mv "$CAEL_WALL.tmp" "$CAEL_WALL"
fi


# ------------------------------------------------------------
# Material palette
# ------------------------------------------------------------

mode="dark"

if command -v gsettings >/dev/null 2>&1; then
    current_scheme="$(
        gsettings get \
            org.gnome.desktop.interface \
            color-scheme 2>/dev/null || true
    )"

    if [[ "$current_scheme" == *light* ]]; then
        mode="light"
    elif [[ "$current_scheme" == *dark* ]]; then
        mode="dark"
    fi
fi

MODE="$mode" \
END4_COLORS="$END4_COLORS" \
CAEL_SCHEME="$CAEL_SCHEME" \
python3 <<'PY'
import json
import os
import re
from pathlib import Path

source = Path(os.environ["END4_COLORS"])
target = Path(os.environ["CAEL_SCHEME"])
mode = os.environ["MODE"]

FALLBACK_COLOURS = {
    "background": "141318",
    "error": "ffb4ab",
    "errorContainer": "93000a",
    "inverseOnSurface": "313036",
    "inversePrimary": "5f5791",
    "inverseSurface": "e6e1e9",
    "onBackground": "e6e1e9",
    "onError": "690005",
    "onErrorContainer": "ffdad6",
    "onPrimary": "30285f",
    "onPrimaryContainer": "e5deff",
    "onPrimaryFixed": "1b1149",
    "onPrimaryFixedVariant": "473f77",
    "onSecondary": "312e41",
    "onSecondaryContainer": "e5dff9",
    "onSecondaryFixed": "1c192b",
    "onSecondaryFixedVariant": "474459",
    "onSurface": "e6e1e9",
    "onSurfaceVariant": "c9c5d0",
    "onTertiary": "482537",
    "onTertiaryContainer": "ffd8e8",
    "onTertiaryFixed": "301122",
    "onTertiaryFixedVariant": "613b4e",
    "outline": "928f99",
    "outlineVariant": "48454e",
    "primary": "c9bfff",
    "primaryContainer": "473f77",
    "primaryFixed": "e5deff",
    "primaryFixedDim": "c9bfff",
    "scrim": "000000",
    "secondary": "c9c3dc",
    "secondaryContainer": "474459",
    "secondaryFixed": "e5dff9",
    "secondaryFixedDim": "c9c3dc",
    "shadow": "000000",
    "surface": "141318",
    "surfaceBright": "3a383e",
    "surfaceContainer": "201f25",
    "surfaceContainerHigh": "2b292f",
    "surfaceContainerHighest": "36343a",
    "surfaceContainerLow": "1c1b20",
    "surfaceContainerLowest": "0f0d13",
    "surfaceDim": "141318",
    "surfaceTint": "c9bfff",
    "surfaceVariant": "48454e",
    "tertiary": "ebb8cf",
    "tertiaryContainer": "613b4e",
    "tertiaryFixed": "ffd8e8",
    "tertiaryFixedDim": "ebb8cf"
}

colours = {}

if source.is_file():
    try:
        data = json.loads(source.read_text())
    except Exception:
        data = {}

    for name, value in data.items():
        if not isinstance(value, str):
            continue

        if not value.startswith("#"):
            continue

        camel = re.sub(
            r"_([a-z])",
            lambda m: m.group(1).upper(),
            name
        )

        colours[camel] = value.lstrip("#")

if not colours:
    colours = dict(FALLBACK_COLOURS)
    scheme_name = "end4-fallback"
else:
    scheme_name = "end4-dynamic"

scheme = {
    "name": scheme_name,
    "flavour": "end4",
    "mode": mode,
    "colours": colours
}

target.parent.mkdir(parents=True, exist_ok=True)
tmp = target.with_suffix(".json.tmp")
tmp.write_text(
    json.dumps(
        scheme,
        indent=2,
        ensure_ascii=False
    ) + "\n"
)

tmp.replace(target)

print(
    f"Bridge: {len(colours)} cores ({scheme_name}) -> {target}"
)
PY

echo "Bridge: sincronização concluída."
