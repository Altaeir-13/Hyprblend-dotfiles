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

APPLIED_TYPE_FILE="$XDG_STATE_HOME/quickshell/user/generated/applied_scheme_type.txt"
PREF_TYPE_FILE="$XDG_STATE_HOME/quickshell/user/generated/palette_type_preference.txt"

mkdir -p "$CAEL_WALL_DIR"

to_caelestia_variant() {
    case "${1,,}" in
        content|scheme-content) echo "content" ;;
        expressive|scheme-expressive) echo "expressive" ;;
        fidelity|scheme-fidelity) echo "fidelity" ;;
        fruitsalad|fruit-salad|scheme-fruit-salad) echo "fruitsalad" ;;
        monochrome|scheme-monochrome) echo "monochrome" ;;
        neutral|scheme-neutral) echo "neutral" ;;
        rainbow|scheme-rainbow) echo "rainbow" ;;
        tonalspot|tonal-spot|scheme-tonal-spot) echo "tonalspot" ;;
        vibrant|scheme-vibrant) echo "vibrant" ;;
        auto) echo "auto" ;;
        *) echo "tonalspot" ;;
    esac
}

to_switchwall_type() {
    case "${1,,}" in
        content|scheme-content) echo "scheme-content" ;;
        expressive|scheme-expressive) echo "scheme-expressive" ;;
        fidelity|scheme-fidelity) echo "scheme-fidelity" ;;
        fruitsalad|fruit-salad|scheme-fruit-salad) echo "scheme-fruit-salad" ;;
        monochrome|scheme-monochrome) echo "scheme-monochrome" ;;
        neutral|scheme-neutral) echo "scheme-neutral" ;;
        rainbow|scheme-rainbow) echo "scheme-rainbow" ;;
        tonalspot|tonal-spot|scheme-tonal-spot) echo "scheme-tonal-spot" ;;
        vibrant|scheme-vibrant) echo "scheme-vibrant" ;;
        auto) echo "auto" ;;
        *) echo "scheme-tonal-spot" ;;
    esac
}

# ------------------------------------------------------------
# Modo de pré-visualização não destrutivo (--preview)
# ------------------------------------------------------------
if [[ "${1:-}" == "--preview" ]]; then
    shift
    preview_img=""
    preview_type="auto"
    preview_mode="dark"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)
                preview_type="$2"
                shift 2
                ;;
            --mode)
                preview_mode="$2"
                shift 2
                ;;
            *)
                if [[ -z "$preview_img" ]]; then
                    preview_img="$1"
                fi
                shift
                ;;
        esac
    done

    if [[ -z "$preview_img" && -f "$CAEL_WALL" ]]; then
        preview_img="$(head -n 1 "$CAEL_WALL" | tr -d '\r\n')"
    fi

    sw_type="$(to_switchwall_type "$preview_type")"
    if [[ "$sw_type" == "auto" && -n "$preview_img" && -f "$preview_img" ]]; then
        venv_path="${XDG_STATE_HOME}/quickshell/.venv"
        if [[ -d "$venv_path" ]]; then
            source "$venv_path/bin/activate"
            detected="$("$XDG_CONFIG_HOME/quickshell/ii/scripts/colors/scheme_for_image.py" "$preview_img" 2>/dev/null || echo "scheme-tonal-spot")"
            deactivate
            sw_type="${detected:-scheme-tonal-spot}"
        else
            sw_type="scheme-tonal-spot"
        fi
    fi

    cael_var="$(to_caelestia_variant "$sw_type")"
    cael_pref="$(to_caelestia_variant "$preview_type")"

    venv_path="${XDG_STATE_HOME}/quickshell/.venv"
    if [[ -f "$preview_img" && -d "$venv_path" ]]; then
        source "$venv_path/bin/activate"
        raw_colors="$(python3 "$XDG_CONFIG_HOME/quickshell/ii/scripts/colors/generate_colors_material.py" \
            --path "$preview_img" \
            --scheme "$sw_type" \
            --mode "$preview_mode" 2>/dev/null || true)"
        deactivate

        python3 - <<PY
import json
import re

raw = """$raw_colors"""
colours = {}
for line in raw.splitlines():
    line = line.strip()
    if not line or not line.startswith("$"):
        continue
    parts = line.split(":", 1)
    if len(parts) != 2:
        continue
    k = parts[0].lstrip("$").strip()
    v = parts[1].rstrip(";").strip()
    if v.startswith("#"):
        camel = re.sub(r"_([a-z])", lambda m: m.group(1).upper(), k)
        colours[camel] = v.lstrip("#")

scheme = {
    "name": "preview-dynamic",
    "flavour": "end4",
    "mode": "$preview_mode",
    "variant": "$cael_var",
    "variantPreference": "$cael_pref",
    "colours": colours
}
print(json.dumps(scheme, indent=2))
PY
        exit 0
    fi
    exit 1
fi

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

# Determine applied variant and preference
applied_type="scheme-tonal-spot"
if [[ -f "$APPLIED_TYPE_FILE" ]]; then
    applied_type="$(tr -d '\r\n' < "$APPLIED_TYPE_FILE")"
fi

type_pref="auto"
if [[ -f "$PREF_TYPE_FILE" ]]; then
    type_pref="$(tr -d '\r\n' < "$PREF_TYPE_FILE")"
elif [[ -f "$END4_CONFIG" ]]; then
    type_pref="$(jq -r '.appearance.palette.type // "auto"' "$END4_CONFIG" 2>/dev/null || echo "auto")"
fi

cael_variant="$(to_caelestia_variant "$applied_type")"
cael_pref="$(to_caelestia_variant "$type_pref")"

MODE="$mode" \
VARIANT="$cael_variant" \
VARIANT_PREFERENCE="$cael_pref" \
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
variant = os.environ.get("VARIANT", "tonalspot")
variant_preference = os.environ.get("VARIANT_PREFERENCE", "auto")

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
    "variant": variant,
    "variantPreference": variant_preference,
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
