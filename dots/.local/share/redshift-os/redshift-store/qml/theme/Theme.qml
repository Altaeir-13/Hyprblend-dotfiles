import QtQuick

/**
 * Redshift OS — Material 3 Expressive Design System Tokens (Theme.qml)
 *
 * Provides reactive semantic color tokens, typography constants, border radii,
 * and animation curves for the Redshift Store.
 *
 * CRITICAL ARCHITECTURE NOTE (Qt 6.12 QML):
 * In QML, properties starting with 'on' followed by an uppercase letter (e.g. 'onSurface')
 * collide with signal handlers for existing properties (e.g. 'surface' -> 'onSurface:'),
 * causing the compiler to treat them as signal handlers and leaving the color uninitialized
 * to #000000 (black).
 *
 * To prevent this, all 'on*' tokens are declared strictly as:
 * 1. snake_case: 'on_surface', 'on_primary', 'on_secondary', etc.
 * 2. m3 prefix: 'm3onSurface', 'm3onPrimary', 'm3onSecondary', etc.
 * 3. The getToken(key, fallback) helper resolves both camelCase and snake_case keys.
 */
QtObject {
    id: root

    // -----------------------------------------------------------------------
    // Bridge Integration & Reactive Status
    // -----------------------------------------------------------------------

    readonly property var bridge: (typeof ThemeBridge !== "undefined") ? ThemeBridge : null
    readonly property var colors: (bridge && bridge.colors) ? bridge.colors : (bridge && bridge.palette) ? bridge.palette : ({})
    readonly property var palette: colors

    readonly property bool isDark: (bridge && typeof bridge.isDark !== "undefined") ? bridge.isDark : true
    readonly property string schemeVariant: (bridge && bridge.schemeVariant) ? bridge.schemeVariant : "scheme-tonal-spot"
    readonly property string variant: (bridge && bridge.variant) ? bridge.variant : schemeVariant
    readonly property string wallpaperPath: (bridge && bridge.wallpaperPath) ? bridge.wallpaperPath : ""
    readonly property string frontendMode: (bridge && bridge.frontendMode) ? bridge.frontendMode : (bridge && bridge.activeShellMode) ? bridge.activeShellMode : "end4"
    readonly property string frontend: (bridge && bridge.frontend) ? bridge.frontend : frontendMode
    readonly property string activeShellMode: frontendMode

    // Safe color resolution helper
    function _color(key, fallbackDark, fallbackLight) {
        if (colors) {
            if (colors[key] !== undefined) return colors[key];
            let snake = key.replace(/([A-Z])/g, "_$1").toLowerCase();
            if (colors[snake] !== undefined) return colors[snake];
            let camel = key.replace(/_([a-z])/g, (m, c) => c.toUpperCase());
            if (colors[camel] !== undefined) return colors[camel];
        }
        return isDark ? fallbackDark : fallbackLight;
    }

    /**
     * Unified token resolver for components.
     * Looks up tokens in bridge QVariantMap first, then in root properties,
     * handling camelCase, snake_case, and m3* transparently.
     */
    function getToken(key, fallback) {
        if (colors) {
            if (colors[key] !== undefined) return colors[key];
            let snake = key.replace(/([A-Z])/g, "_$1").toLowerCase();
            if (colors[snake] !== undefined) return colors[snake];
            let camel = key.replace(/_([a-z])/g, (m, c) => c.toUpperCase());
            if (colors[camel] !== undefined) return colors[camel];
            if (colors[`m3${key}`] !== undefined) return colors[`m3${key}`];
            if (colors[`m3${camel}`] !== undefined) return colors[`m3${camel}`];
        }
        if (root[key] !== undefined) return root[key];
        let snakeKey = key.replace(/([A-Z])/g, "_$1").toLowerCase();
        if (root[snakeKey] !== undefined) return root[snakeKey];
        if (root[`m3${key}`] !== undefined) return root[`m3${key}`];
        return fallback;
    }

    // -----------------------------------------------------------------------
    // Material 3 Semantic Color Tokens
    // -----------------------------------------------------------------------

    // Surface & Background
    readonly property color background: _color("background", "#141318", "#fdf8fd")
    readonly property color surface: _color("surface", "#141318", "#fdf8fd")
    readonly property color surfaceDim: _color("surfaceDim", "#141318", "#ded8dd")
    readonly property color surfaceBright: _color("surfaceBright", "#3a383e", "#fdf8fd")

    readonly property color surfaceContainerLowest: _color("surfaceContainerLowest", "#0f0d13", "#ffffff")
    readonly property color surfaceContainerLow: _color("surfaceContainerLow", "#1c1b20", "#f7f2f7")
    readonly property color surfaceContainer: _color("surfaceContainer", "#201f25", "#f1ecf1")
    readonly property color surfaceContainerHigh: _color("surfaceContainerHigh", "#2b292f", "#ece6eb")
    readonly property color surfaceContainerHighest: _color("surfaceContainerHighest", "#36343a", "#e6e0e5")

    readonly property color surfaceVariant: _color("surfaceVariant", "#48454e", "#e6e0eb")
    readonly property color inverseSurface: _color("inverseSurface", "#e6e1e9", "#323035")
    readonly property color inversePrimary: _color("inversePrimary", "#5f5791", "#c9bfff")

    // Outlines & Borders
    readonly property color outline: _color("outline", "#928f99", "#79757f")
    readonly property color outlineVariant: _color("outlineVariant", "#48454e", "#c9c5d0")

    // Primary Accents
    readonly property color primary: _color("primary", "#c9bfff", "#5f5791")
    readonly property color primaryContainer: _color("primaryContainer", "#473f77", "#e5deff")
    readonly property color primaryFixed: _color("primaryFixed", "#e5deff", "#e5deff")
    readonly property color primaryFixedDim: _color("primaryFixedDim", "#c9bfff", "#c9bfff")

    // Secondary Accents
    readonly property color secondary: _color("secondary", "#c9c3dc", "#605b71")
    readonly property color secondaryContainer: _color("secondaryContainer", "#474459", "#e5dff9")
    readonly property color secondaryFixed: _color("secondaryFixed", "#e5dff9", "#e5dff9")
    readonly property color secondaryFixedDim: _color("secondaryFixedDim", "#c9c3dc", "#c9c3dc")

    // Tertiary Accents
    readonly property color tertiary: _color("tertiary", "#ebb8cf", "#7b5266")
    readonly property color tertiaryContainer: _color("tertiaryContainer", "#613b4e", "#ffd8e8")
    readonly property color tertiaryFixed: _color("tertiaryFixed", "#ffd8e8", "#ffd8e8")
    readonly property color tertiaryFixedDim: _color("tertiaryFixedDim", "#ebb8cf", "#ebb8cf")

    // Feedback & Status
    readonly property color error: _color("error", "#ffb4ab", "#ba1a1a")
    readonly property color errorContainer: _color("errorContainer", "#93000a", "#ffdad6")
    readonly property color success: _color("success", "#b5ccba", "#386a42")
    readonly property color successContainer: _color("successContainer", "#374b3e", "#b7f1be")
    readonly property color warning: _color("warning", "#ffb951", "#825500")
    readonly property color warningContainer: _color("warningContainer", "#643f00", "#ffddb4")
    readonly property color info: _color("info", "#82cfff", "#0061a4")
    readonly property color infoContainer: _color("infoContainer", "#00497d", "#d1e4ff")

    // Elevation & Decorators
    readonly property color shadow: _color("shadow", "#000000", "#000000")
    readonly property color scrim: _color("scrim", "#000000", "#000000")
    readonly property color surfaceTint: _color("surfaceTint", "#c9bfff", "#5f5791")

    // -----------------------------------------------------------------------
    // Material 3 "on_*" Tokens (snake_case - Safe against QML signal collisions)
    // -----------------------------------------------------------------------

    readonly property color on_background: _color("on_background", "#e6e1e9", "#1d1b20")
    readonly property color on_surface: _color("on_surface", "#e6e1e9", "#1d1b20")
    readonly property color on_surface_variant: _color("on_surface_variant", "#c9c5d0", "#48454e")

    readonly property color on_primary: _color("on_primary", "#30285f", "#ffffff")
    readonly property color on_primary_container: _color("on_primary_container", "#e5deff", "#1b1149")
    readonly property color on_primary_fixed: _color("on_primary_fixed", "#1b1149", "#1b1149")
    readonly property color on_primary_fixed_variant: _color("on_primary_fixed_variant", "#473f77", "#473f77")

    readonly property color on_secondary: _color("on_secondary", "#312e41", "#ffffff")
    readonly property color on_secondary_container: _color("on_secondary_container", "#e5dff9", "#1c192b")
    readonly property color on_secondary_fixed: _color("on_secondary_fixed", "#1c192b", "#1c192b")
    readonly property color on_secondary_fixed_variant: _color("on_secondary_fixed_variant", "#474459", "#474459")

    readonly property color on_tertiary: _color("on_tertiary", "#482537", "#ffffff")
    readonly property color on_tertiary_container: _color("on_tertiary_container", "#ffd8e8", "#301122")
    readonly property color on_tertiary_fixed: _color("on_tertiary_fixed", "#301122", "#301122")
    readonly property color on_tertiary_fixed_variant: _color("on_tertiary_fixed_variant", "#613b4e", "#613b4e")

    readonly property color on_error: _color("on_error", "#690005", "#ffffff")
    readonly property color on_error_container: _color("on_error_container", "#ffdad6", "#410002")

    readonly property color on_success: _color("on_success", "#213528", "#ffffff")
    readonly property color on_success_container: _color("on_success_container", "#d1e9d6", "#00210b")

    readonly property color on_warning: _color("on_warning", "#452b00", "#ffffff")
    readonly property color on_warning_container: _color("on_warning_container", "#ffddb4", "#2a1700")

    readonly property color on_info: _color("on_info", "#003258", "#ffffff")
    readonly property color on_info_container: _color("on_info_container", "#d1e4ff", "#001d36")

    readonly property color inverse_on_surface: _color("inverse_on_surface", "#313036", "#f5eff4")

    // -----------------------------------------------------------------------
    // Material 3 "m3on*" Tokens (m3 prefix - Safe against QML signal collisions)
    // -----------------------------------------------------------------------

    readonly property color m3onBackground: on_background
    readonly property color m3onSurface: on_surface
    readonly property color m3onSurfaceVariant: on_surface_variant

    readonly property color m3onPrimary: on_primary
    readonly property color m3onPrimaryContainer: on_primary_container
    readonly property color m3onPrimaryFixed: on_primary_fixed
    readonly property color m3onPrimaryFixedVariant: on_primary_fixed_variant

    readonly property color m3onSecondary: on_secondary
    readonly property color m3onSecondaryContainer: on_secondary_container
    readonly property color m3onSecondaryFixed: on_secondary_fixed
    readonly property color m3onSecondaryFixedVariant: on_secondary_fixed_variant

    readonly property color m3onTertiary: on_tertiary
    readonly property color m3onTertiaryContainer: on_tertiary_container
    readonly property color m3onTertiaryFixed: on_tertiary_fixed
    readonly property color m3onTertiaryFixedVariant: on_tertiary_fixed_variant

    readonly property color m3onError: on_error
    readonly property color m3onErrorContainer: on_error_container

    readonly property color m3onSuccess: on_success
    readonly property color m3onSuccessContainer: on_success_container

    readonly property color m3onWarning: on_warning
    readonly property color m3onWarningContainer: on_warning_container

    readonly property color m3onInfo: on_info
    readonly property color m3onInfoContainer: on_info_container

    readonly property color m3inverseOnSurface: inverse_on_surface

    // -----------------------------------------------------------------------
    // snake_case Aliases for All Other M3 Tokens
    // -----------------------------------------------------------------------

    readonly property color surface_container: surfaceContainer
    readonly property color surface_container_low: surfaceContainerLow
    readonly property color surface_container_lowest: surfaceContainerLowest
    readonly property color surface_container_high: surfaceContainerHigh
    readonly property color surface_container_highest: surfaceContainerHighest
    readonly property color surface_dim: surfaceDim
    readonly property color surface_bright: surfaceBright
    readonly property color surface_variant: surfaceVariant
    readonly property color inverse_surface: inverseSurface
    readonly property color inverse_primary: inversePrimary
    readonly property color outline_variant: outlineVariant

    readonly property color primary_container: primaryContainer
    readonly property color primary_fixed: primaryFixed
    readonly property color primary_fixed_dim: primaryFixedDim

    readonly property color secondary_container: secondaryContainer
    readonly property color secondary_fixed: secondaryFixed
    readonly property color secondary_fixed_dim: secondaryFixedDim

    readonly property color tertiary_container: tertiaryContainer
    readonly property color tertiary_fixed: tertiaryFixed
    readonly property color tertiary_fixed_dim: tertiaryFixedDim

    readonly property color error_container: errorContainer
    readonly property color success_container: successContainer
    readonly property color warning_container: warningContainer
    readonly property color info_container: infoContainer
    readonly property color surface_tint: surfaceTint

    // -----------------------------------------------------------------------
    // Typography
    // -----------------------------------------------------------------------

    readonly property string fontFamily: "Google Sans Flex"
    readonly property string monoFontFamily: "JetBrains Mono NF"
    readonly property string iconFontFamily: "Material Symbols Rounded"

    // -----------------------------------------------------------------------
    // Border Radii (Corner Rounding)
    // -----------------------------------------------------------------------

    readonly property real radiusSmall: 8
    readonly property real radiusNormal: 12
    readonly property real radiusLarge: 18
    readonly property real radiusFull: 9999

    // -----------------------------------------------------------------------
    // Animation Timings (in Milliseconds)
    // -----------------------------------------------------------------------

    readonly property int animFast: 180
    readonly property int animNormal: 300
    readonly property int animSlow: 450

    // -----------------------------------------------------------------------
    // Color Manipulation Utilities
    // -----------------------------------------------------------------------

    function withAlpha(c: color, a: real): color {
        return Qt.rgba(c.r, c.g, c.b, Math.max(0.0, Math.min(1.0, a)));
    }

    function getLuminance(c: color): real {
        return Math.sqrt(0.299 * (c.r ** 2) + 0.587 * (c.g ** 2) + 0.114 * (c.b ** 2));
    }

    function alterColor(c: color, factor: real): color {
        const lum = getLuminance(c);
        if (lum <= 0) return c;
        const scale = Math.max(0.0, Math.min(2.0, 1.0 + factor));
        const r = Math.max(0.0, Math.min(1.0, c.r * scale));
        const g = Math.max(0.0, Math.min(1.0, c.g * scale));
        const b = Math.max(0.0, Math.min(1.0, c.b * scale));
        return Qt.rgba(r, g, b, c.a);
    }
}
