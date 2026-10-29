"""
Redshift OS — ThemeService (Material You / Matugen Dynamic Colors)
Integrates Redshift Store with end-4 (illogical-impulse) and Caelestia Shell.
"""

from __future__ import annotations

import json
import os
import re
from pathlib import Path
from typing import Any, Dict, Optional

from PyQt6.QtCore import (
    QFileSystemWatcher,
    QObject,
    QTimer,
    pyqtProperty,
    pyqtSignal,
    pyqtSlot,
)

# ---------------------------------------------------------------------------
# Fallback M3 Palettes (49 Standard Tokens for Dark and Light Modes)
# ---------------------------------------------------------------------------

FALLBACK_M3_DARK: Dict[str, str] = {
    "background": "#141318",
    "error": "#ffb4ab",
    "error_container": "#93000a",
    "inverse_on_surface": "#313036",
    "inverse_primary": "#5f5791",
    "inverse_surface": "#e6e1e9",
    "on_background": "#e6e1e9",
    "on_error": "#690005",
    "on_error_container": "#ffdad6",
    "on_primary": "#30285f",
    "on_primary_container": "#e5deff",
    "on_primary_fixed": "#1b1149",
    "on_primary_fixed_variant": "#473f77",
    "on_secondary": "#312e41",
    "on_secondary_container": "#e5dff9",
    "on_secondary_fixed": "#1c192b",
    "on_secondary_fixed_variant": "#474459",
    "on_surface": "#e6e1e9",
    "on_surface_variant": "#c9c5d0",
    "on_tertiary": "#482537",
    "on_tertiary_container": "#ffd8e8",
    "on_tertiary_fixed": "#301122",
    "on_tertiary_fixed_variant": "#613b4e",
    "outline": "#928f99",
    "outline_variant": "#48454e",
    "primary": "#c9bfff",
    "primary_container": "#473f77",
    "primary_fixed": "#e5deff",
    "primary_fixed_dim": "#c9bfff",
    "scrim": "#000000",
    "secondary": "#c9c3dc",
    "secondary_container": "#474459",
    "secondary_fixed": "#e5dff9",
    "secondary_fixed_dim": "#c9c3dc",
    "shadow": "#000000",
    "surface": "#141318",
    "surface_bright": "#3a383e",
    "surface_container": "#201f25",
    "surface_container_high": "#2b292f",
    "surface_container_highest": "#36343a",
    "surface_container_low": "#1c1b20",
    "surface_container_lowest": "#0f0d13",
    "surface_dim": "#141318",
    "surface_tint": "#c9bfff",
    "surface_variant": "#48454e",
    "tertiary": "#ebb8cf",
    "tertiary_container": "#613b4e",
    "tertiary_fixed": "#ffd8e8",
    "tertiary_fixed_dim": "#ebb8cf",
}

FALLBACK_M3_LIGHT: Dict[str, str] = {
    "background": "#fdf8fd",
    "error": "#ba1a1a",
    "error_container": "#ffdad6",
    "inverse_on_surface": "#f5eff4",
    "inverse_primary": "#c9bfff",
    "inverse_surface": "#323035",
    "on_background": "#1d1b20",
    "on_error": "#ffffff",
    "on_error_container": "#410002",
    "on_primary": "#ffffff",
    "on_primary_container": "#1b1149",
    "on_primary_fixed": "#1b1149",
    "on_primary_fixed_variant": "#473f77",
    "on_secondary": "#ffffff",
    "on_secondary_container": "#1c192b",
    "on_secondary_fixed": "#1c192b",
    "on_secondary_fixed_variant": "#474459",
    "on_surface": "#1d1b20",
    "on_surface_variant": "#48454e",
    "on_tertiary": "#ffffff",
    "on_tertiary_container": "#301122",
    "on_tertiary_fixed": "#301122",
    "on_tertiary_fixed_variant": "#613b4e",
    "outline": "#79757f",
    "outline_variant": "#c9c5d0",
    "primary": "#5f5791",
    "primary_container": "#e5deff",
    "primary_fixed": "#e5deff",
    "primary_fixed_dim": "#c9bfff",
    "scrim": "#000000",
    "secondary": "#605b71",
    "secondary_container": "#e5dff9",
    "secondary_fixed": "#e5dff9",
    "secondary_fixed_dim": "#c9c3dc",
    "shadow": "#000000",
    "surface": "#fdf8fd",
    "surface_bright": "#fdf8fd",
    "surface_container": "#f1ecf1",
    "surface_container_high": "#ece6eb",
    "surface_container_highest": "#e6e0e5",
    "surface_container_low": "#f7f2f7",
    "surface_container_lowest": "#ffffff",
    "surface_dim": "#ded8dd",
    "surface_tint": "#5f5791",
    "surface_variant": "#e6e0eb",
    "tertiary": "#7b5266",
    "tertiary_container": "#ffd8e8",
    "tertiary_fixed": "#ffd8e8",
    "tertiary_fixed_dim": "#ebb8cf",
}


def _calc_is_dark(background_hex: str) -> bool:
    """Calculates whether a background color is dark based on HSL lightness."""
    try:
        clean = background_hex.strip().lstrip("#")
        if len(clean) == 6:
            r = int(clean[0:2], 16) / 255.0
            g = int(clean[2:4], 16) / 255.0
            b = int(clean[4:6], 16) / 255.0
            lightness = (max(r, g, b) + min(r, g, b)) / 2.0
            return lightness < 0.5
    except Exception:
        pass
    return True


def _srgb_luminance(hex_str: str) -> float:
    """Calculates relative luminance (WCAG definition) for an sRGB hex color."""
    try:
        clean = hex_str.strip().lstrip("#")
        if len(clean) == 6:
            r = int(clean[0:2], 16) / 255.0
            g = int(clean[2:4], 16) / 255.0
            b = int(clean[4:6], 16) / 255.0

            def _gamma(c: float) -> float:
                return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

            return 0.2126 * _gamma(r) + 0.7152 * _gamma(g) + 0.0722 * _gamma(b)
    except Exception:
        pass
    return 0.5


def _ensure_contrast(
    fg_hex: str,
    bg_hex: str,
    target_dark: str = "#1d1b20",
    target_light: str = "#e5e3d8",
    min_contrast: float = 3.0,
) -> str:
    """
    Enforces minimum readable contrast between foreground (on_*) and background.
    If contrast ratio is below min_contrast (or text is dark on dark background),
    replaces fg with a guaranteed high-contrast token.
    """
    bg_lum = _srgb_luminance(bg_hex)
    fg_lum = _srgb_luminance(fg_hex)
    contrast = (max(bg_lum, fg_lum) + 0.05) / (min(bg_lum, fg_lum) + 0.05)
    if contrast < min_contrast or (bg_lum < 0.5 and fg_lum < 0.25 and min_contrast >= 3.0):
        return target_light if bg_lum < 0.5 else target_dark
    return fg_hex


class ThemeService(QObject):
    """
    Reactive Material You / Matugen dynamic theme service for Redshift Store.
    Monitors colors.json and scheme.json in real time via QFileSystemWatcher.
    """

    themeChanged = pyqtSignal()
    paletteChanged = pyqtSignal()

    def __init__(self, parent: Optional[QObject] = None) -> None:
        super().__init__(parent)

        # Resolve paths with environment variable overrides for test sandboxing
        home = Path.home()
        state_dir = Path(os.environ.get("XDG_STATE_HOME") or (home / ".local/state"))

        self._colors_json_path = Path(
            os.environ.get(
                "REDSHIFT_COLORS_JSON_PATH",
                state_dir / "quickshell/user/generated/colors.json",
            )
        )
        self._caelestia_scheme_path = Path(
            os.environ.get(
                "REDSHIFT_CAELESTIA_SCHEME_PATH",
                state_dir / "caelestia/scheme.json",
            )
        )
        self._ui_switch_path = Path(
            os.environ.get(
                "REDSHIFT_UI_SWITCH_STATE_PATH",
                state_dir / "quickshell/ui-switch/current",
            )
        )
        self._wallpaper_path_file = Path(
            os.environ.get(
                "REDSHIFT_WALLPAPER_PATH_FILE",
                state_dir / "quickshell/user/generated/wallpaper/path.txt",
            )
        )
        self._applied_scheme_type_path = Path(
            os.environ.get(
                "REDSHIFT_APPLIED_SCHEME_TYPE_PATH",
                state_dir / "quickshell/user/generated/applied_scheme_type.txt",
            )
        )
        self._color_txt_path = Path(
            os.environ.get(
                "REDSHIFT_COLOR_TXT_PATH",
                state_dir / "quickshell/user/generated/color.txt",
            )
        )

        # State storage
        self._colors: Dict[str, str] = {}
        self._is_dark: bool = True
        self._scheme_variant: str = "scheme-tonal-spot"
        self._wallpaper_path: str = ""
        self._frontend_mode: str = "end4"
        self._preview_override_is_dark: Optional[bool] = None

        # Debounce timer for inotify file events (80ms)
        self._debounce_timer = QTimer(self)
        self._debounce_timer.setInterval(80)
        self._debounce_timer.setSingleShot(True)
        self._debounce_timer.timeout.connect(self._on_debounced_change)

        # File watcher
        self._watcher = QFileSystemWatcher(self)
        self._watcher.fileChanged.connect(self._on_fs_event)
        self._watcher.directoryChanged.connect(self._on_fs_event)

        # Initial load and watcher registration
        self._setup_watcher()
        self.reloadTheme()

    # -----------------------------------------------------------------------
    # File Watching & Inotify Management
    # -----------------------------------------------------------------------

    def _setup_watcher(self) -> None:
        """Adds target files and their parent directories to QFileSystemWatcher."""
        watched_files = [
            self._colors_json_path,
            self._caelestia_scheme_path,
            self._ui_switch_path,
            self._wallpaper_path_file,
            self._applied_scheme_type_path,
            self._color_txt_path,
        ]

        for file_path in watched_files:
            # Watch parent directory to capture file recreation / atomic moves
            parent = file_path.parent
            if parent.exists():
                try:
                    self._watcher.addPath(str(parent))
                except Exception:
                    pass
            elif parent.parent.exists():
                try:
                    self._watcher.addPath(str(parent.parent))
                except Exception:
                    pass

            if file_path.exists():
                try:
                    self._watcher.addPath(str(file_path))
                except Exception:
                    pass

    def _on_fs_event(self, _path: str) -> None:
        """Restarts the debounce timer when any watched path reports a change."""
        self._debounce_timer.start()

    def _on_debounced_change(self) -> None:
        """Handles settled file change events and re-attaches any unlinked inodes."""
        # Reset preview override so disk changes take precedence
        self._preview_override_is_dark = None

        # Check if any watched file or directory was replaced atomically (new inode)
        current_dirs = set(self._watcher.directories())
        current_files = set(self._watcher.files())
        for file_path in [
            self._colors_json_path,
            self._caelestia_scheme_path,
            self._ui_switch_path,
            self._wallpaper_path_file,
            self._applied_scheme_type_path,
            self._color_txt_path,
        ]:
            parent = file_path.parent
            parent_str = str(parent)
            if parent.exists() and parent_str not in current_dirs:
                try:
                    self._watcher.addPath(parent_str)
                    current_dirs.add(parent_str)
                except Exception:
                    pass

            path_str = str(file_path)
            if file_path.exists() and path_str not in current_files:
                try:
                    self._watcher.addPath(path_str)
                    current_files.add(path_str)
                except Exception:
                    pass

        self.reloadTheme()

    # -----------------------------------------------------------------------
    # Theme Loading & Token Expansion
    # -----------------------------------------------------------------------

    def _normalize_tokens(self, raw_tokens: Dict[str, str], is_dark: bool) -> Dict[str, str]:
        """
        Normalizes token map into a unified dictionary containing:
        - snake_case (e.g. 'primary_container')
        - camelCase (e.g. 'primaryContainer')
        - m3 prefixed (e.g. 'm3primaryContainer' and 'm3PrimaryContainer')
        - Functional status tokens (success, on_success, warning, on_warning, etc.)
        Applies WCAG contrast guards for low-contrast palettes.
        """
        normalized: Dict[str, str] = {}

        def set_token(key: str, hex_value: str) -> None:
            if not isinstance(hex_value, str):
                return
            clean_hex = hex_value.strip()
            if not clean_hex.startswith("#"):
                clean_hex = f"#{clean_hex}"
            clean_k = key.replace("-", "_")
            snake_k = re.sub(r"([A-Z])", r"_\1", clean_k).lower()
            snake_k = re.sub(r"_+", "_", snake_k).strip("_")
            camel_k = re.sub(r"_([a-z])", lambda m: m.group(1).upper(), snake_k)
            pascal_k = camel_k[0].upper() + camel_k[1:] if camel_k else ""
            normalized[snake_k] = clean_hex
            normalized[camel_k] = clean_hex
            normalized[f"m3{camel_k}"] = clean_hex
            normalized[f"m3{pascal_k}"] = clean_hex

        for k, v in raw_tokens.items():
            set_token(k, v)

        # Functional and semantic support tokens (Material 3 semantics)
        functional = {
            "success": normalized.get("success", "#b5ccba" if is_dark else "#386a42"),
            "on_success": normalized.get("on_success", "#213528" if is_dark else "#ffffff"),
            "success_container": normalized.get("success_container", "#374b3e" if is_dark else "#b7f1be"),
            "on_success_container": normalized.get("on_success_container", "#d1e9d6" if is_dark else "#00210b"),
            "warning": normalized.get("warning", "#ffb951" if is_dark else "#825500"),
            "on_warning": normalized.get("on_warning", "#452b00" if is_dark else "#ffffff"),
            "warning_container": normalized.get("warning_container", "#643f00" if is_dark else "#ffddb4"),
            "on_warning_container": normalized.get("on_warning_container", "#ffddb4" if is_dark else "#2a1700"),
            "info": normalized.get("info", "#82cfff" if is_dark else "#0061a4"),
            "on_info": normalized.get("on_info", "#003258" if is_dark else "#ffffff"),
            "info_container": normalized.get("info_container", "#00497d" if is_dark else "#d1e4ff"),
            "on_info_container": normalized.get("on_info_container", "#d1e4ff" if is_dark else "#001d36"),
        }

        for fk, fv in functional.items():
            set_token(fk, fv)

        # 1. Accent contrast checks:
        # primary, secondary, and tertiary validated with min_contrast >= 2.5 against surface and surface_container
        accent_checks = [
            ("primary", "#4f378b", "#d0bcff"),
            ("secondary", "#4a4458", "#ccc2dc"),
            ("tertiary", "#633b48", "#efb8c8"),
        ]
        for accent_key, light_fb, dark_fb in accent_checks:
            accent_val = normalized.get(accent_key, dark_fb if is_dark else light_fb)
            for bg_key in ("surface", "surface_container"):
                bg_val = normalized.get(bg_key)
                if bg_val:
                    accent_val = _ensure_contrast(
                        accent_val, bg_val, target_dark=light_fb, target_light=dark_fb, min_contrast=2.5
                    )
            set_token(accent_key, accent_val)

        # 2. General contrast checks for Material 3 foreground/background pairs (min_contrast >= 3.0)
        contrast_pairs = [
            ("on_background", "background", "#1d1b20", "#e5e3d8"),
            ("on_surface", "surface", "#1d1b20", "#e5e3d8"),
            ("on_surface_variant", "surface_variant", "#48454e", "#c9c5d0"),
            ("on_primary", "primary", "#30285f", "#ffffff"),
            ("on_primary_container", "primary_container", "#1b1149", "#e5deff"),
            ("on_secondary", "secondary", "#312e41", "#ffffff"),
            ("on_secondary_container", "secondary_container", "#1c192b", "#e5dff9"),
            ("on_tertiary", "tertiary", "#482537", "#ffffff"),
            ("on_tertiary_container", "tertiary_container", "#301122", "#ffd8e8"),
            ("on_error", "error", "#690005", "#ffffff"),
            ("on_error_container", "error_container", "#410002", "#ffdad6"),
            ("on_success", "success", "#213528", "#ffffff"),
            ("on_success_container", "success_container", "#00210b", "#d1e9d6"),
            ("on_warning", "warning", "#452b00", "#ffffff"),
            ("on_warning_container", "warning_container", "#2a1700", "#ffddb4"),
            ("on_info", "info", "#003258", "#ffffff"),
            ("on_info_container", "info_container", "#001d36", "#d1e4ff"),
        ]

        for fg_key, bg_key, target_dark, target_light in contrast_pairs:
            fg_val = normalized.get(fg_key)
            bg_val = normalized.get(bg_key)
            if fg_val and bg_val:
                fixed_fg = _ensure_contrast(fg_val, bg_val, target_dark, target_light, min_contrast=3.0)
                set_token(fg_key, fixed_fg)

        # 3. Reinforced multi-surface checks:
        # on_surface validated against surface, surface_container, and surface_container_low (min_contrast >= 3.0)
        on_surface_val = normalized.get("on_surface", "#e5e3d8" if is_dark else "#1d1b20")
        for bg_key in ("surface", "surface_container", "surface_container_low"):
            bg_val = normalized.get(bg_key)
            if bg_val:
                on_surface_val = _ensure_contrast(
                    on_surface_val, bg_val, target_dark="#1d1b20", target_light="#e5e3d8", min_contrast=3.0
                )
        set_token("on_surface", on_surface_val)

        # on_surface_variant validated against surface_variant, surface, and surface_container (min_contrast >= 3.0)
        on_surface_var = normalized.get("on_surface_variant", "#c9c5d0" if is_dark else "#48454e")
        for bg_key in ("surface_variant", "surface", "surface_container"):
            bg_val = normalized.get(bg_key)
            if bg_val:
                on_surface_var = _ensure_contrast(
                    on_surface_var, bg_val, target_dark="#48454e", target_light="#c9c5d0", min_contrast=3.0
                )
        set_token("on_surface_variant", on_surface_var)

        return normalized

    @pyqtSlot()
    def reloadTheme(self) -> None:
        """Reloads tokens from disk or fallbacks and emits themeChanged."""
        # 1. Determine frontendMode
        if self._ui_switch_path.exists():
            try:
                content = self._ui_switch_path.read_text(encoding="utf-8").strip()
                self._frontend_mode = "caelestia" if "caelestia" in content.lower() else "end4"
            except Exception:
                self._frontend_mode = "end4"
        else:
            self._frontend_mode = "end4"

        # 2. Determine wallpaperPath
        wall_path = ""
        if self._wallpaper_path_file.exists():
            try:
                wall_path = self._wallpaper_path_file.read_text(encoding="utf-8").strip()
            except Exception:
                wall_path = ""
        self._wallpaper_path = wall_path

        # 3. Determine schemeVariant
        variant = "scheme-tonal-spot"
        applied_mtime = 0.0
        if self._applied_scheme_type_path.exists():
            try:
                v = self._applied_scheme_type_path.read_text(encoding="utf-8").strip()
                if v:
                    variant = v
                applied_mtime = self._applied_scheme_type_path.stat().st_mtime
            except Exception:
                pass
        self._scheme_variant = variant

        # 4. Read tokens & detect dark mode
        raw_colors: Dict[str, str] = {}
        detected_dark = True
        found_source = False

        if self._preview_override_is_dark is not None:
            detected_dark = self._preview_override_is_dark
            raw_colors = dict(FALLBACK_M3_DARK if detected_dark else FALLBACK_M3_LIGHT)
            found_source = True
        else:
            def _to_snake_dict(d: Dict[str, Any]) -> Dict[str, str]:
                res: Dict[str, str] = {}
                for k, v in d.items():
                    if isinstance(v, str):
                        clean_k = k.replace("-", "_")
                        snake_k = re.sub(r"([A-Z])", r"_\1", clean_k).lower()
                        snake_k = re.sub(r"_+", "_", snake_k).strip("_")
                        res[snake_k] = v.strip()
                return res

            colors_data: Dict[str, str] = {}
            colors_mtime: float = 0.0
            if self._colors_json_path.exists():
                try:
                    c_data = json.loads(self._colors_json_path.read_text(encoding="utf-8"))
                    if isinstance(c_data, dict) and len(c_data) > 0:
                        colors_data = _to_snake_dict(c_data)
                        colors_mtime = self._colors_json_path.stat().st_mtime
                except Exception:
                    pass

            scheme_colours: Dict[str, str] = {}
            scheme_mode: Optional[str] = None
            scheme_variant: Optional[str] = None
            scheme_mtime: float = 0.0
            if self._caelestia_scheme_path.exists():
                try:
                    s_data = json.loads(self._caelestia_scheme_path.read_text(encoding="utf-8"))
                    if isinstance(s_data, dict):
                        cols = s_data.get("colours")
                        if isinstance(cols, dict) and len(cols) > 0:
                            scheme_colours = _to_snake_dict(cols)
                            scheme_mode = s_data.get("mode")
                            if s_data.get("variant"):
                                scheme_variant = str(s_data["variant"])
                            scheme_mtime = self._caelestia_scheme_path.stat().st_mtime
                except Exception:
                    pass

            # Prioridade Inteligente:
            # - Caelestia como fonte primária quando:
            #   * frontend_mode == "caelestia" (com scheme_colours disponível)
            #   * ou scheme.json tiver st_mtime mais recente que colors.json (com scheme_colours disponível)
            #   * ou colors.json não existir/estiver vazio
            # - end-4 como fonte primária quando:
            #   * frontend_mode == "end4" (e colors.json for mais recente ou igual)
            #   * ou scheme.json não existir/estiver vazio
            use_caelestia_primary = False
            if scheme_colours:
                if not colors_data:
                    use_caelestia_primary = True
                elif self._frontend_mode == "caelestia":
                    use_caelestia_primary = True
                elif self._frontend_mode == "end4":
                    use_caelestia_primary = (scheme_mtime > colors_mtime)
                else:
                    use_caelestia_primary = (scheme_mtime > colors_mtime)

            colors_dark = _calc_is_dark(colors_data.get("background", "#141318")) if colors_data else True
            if scheme_mode in ("dark", "light"):
                scheme_dark = (scheme_mode == "dark")
            elif "background" in scheme_colours:
                scheme_dark = _calc_is_dark(scheme_colours["background"])
            else:
                scheme_dark = colors_dark
            same_polarity = (colors_dark == scheme_dark)

            if use_caelestia_primary:
                raw_colors = dict(colors_data) if same_polarity else {}
                raw_colors.update(scheme_colours)
                found_source = True
                detected_dark = scheme_dark

                if scheme_variant and applied_mtime <= scheme_mtime:
                    self._scheme_variant = scheme_variant
            elif colors_data:
                raw_colors = dict(scheme_colours) if same_polarity else {}
                raw_colors.update(colors_data)
                found_source = True
                detected_dark = colors_dark
            elif scheme_colours:
                raw_colors = dict(scheme_colours)
                found_source = True

                if scheme_mode in ("dark", "light"):
                    detected_dark = (scheme_mode == "dark")
                elif "background" in scheme_colours:
                    detected_dark = _calc_is_dark(scheme_colours["background"])

                if scheme_variant and applied_mtime <= scheme_mtime:
                    self._scheme_variant = scheme_variant

            # Base fallback if no valid theme file found
            if not found_source:
                detected_dark = True
                raw_colors = dict(FALLBACK_M3_DARK)

        # Merge raw tokens over the appropriate fallback to ensure all 49 tokens always exist
        base_palette = FALLBACK_M3_DARK if detected_dark else FALLBACK_M3_LIGHT
        merged_palette = dict(base_palette)
        merged_palette.update(raw_colors)

        self._is_dark = detected_dark
        self._colors = self._normalize_tokens(merged_palette, self._is_dark)
        self.themeChanged.emit()
        self.paletteChanged.emit()

    @pyqtSlot()
    def reloadPalette(self) -> None:
        """Reloads the color palette from disk and notifies QML."""
        self.reloadTheme()

    @pyqtSlot()
    def togglePreviewMode(self) -> None:
        """Toggles in-memory preview between dark and light mode, returning to system palette on toggle back."""
        if self._preview_override_is_dark is None:
            self._preview_override_is_dark = not self._is_dark
        else:
            self._preview_override_is_dark = None

        self.reloadTheme()

    @pyqtSlot()
    def toggleColorScheme(self) -> None:
        """
        Toggles color scheme mode. If in sandbox/mock, toggles in-memory preview.
        Safe alias for togglePreviewMode in tests and UI actions.
        """
        self.togglePreviewMode()

    # -----------------------------------------------------------------------
    # Qt Properties (pyqtProperty)
    # -----------------------------------------------------------------------

    @pyqtProperty("QVariantMap", notify=themeChanged)
    def colors(self) -> Dict[str, str]:
        return self._colors

    @pyqtProperty("QVariantMap", notify=paletteChanged)
    def palette(self) -> Dict[str, str]:
        return self._colors

    @pyqtProperty(bool, notify=themeChanged)
    def isDark(self) -> bool:
        return self._is_dark

    @pyqtProperty(str, notify=themeChanged)
    def schemeVariant(self) -> str:
        return self._scheme_variant

    @pyqtProperty(str, notify=themeChanged)
    def wallpaperPath(self) -> str:
        return self._wallpaper_path

    @pyqtProperty(str, notify=themeChanged)
    def frontendMode(self) -> str:
        return self._frontend_mode

    @pyqtProperty(str, notify=themeChanged)
    def activeShellMode(self) -> str:
        return self._frontend_mode
