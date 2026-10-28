#!/usr/bin/env python3
"""Main entry point for Redshift Store application.

Sets up PyQt6 application, registers ThemeBridge and StoreBridge context
properties, configures native XDG icon provider (image://xdgicon/<name>),
configures QML engine, and starts the event loop.
Supports CLI flags: --mock, --self-test, --page <name>.
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
from pathlib import Path

# Configure logging before importing Qt modules
logging.basicConfig(
    level=logging.INFO,
    format="[%(asctime)s] [%(levelname)s] [%(name)s] %(message)s",
    datefmt="%H:%M:%S",
)
logger = logging.getLogger("redshift_store.main")

VERSION = "1.0.0"

GENERIC_FALLBACK_ICONS = frozenset({
    "applications-other",
    "applications-utilities",
    "applications-multimedia",
    "applications-internet",
    "applications-development",
    "applications-games",
    "applications-system",
    "applications-office",
    "package-x-generic",
    "emblem-favorite",
})

COMMON_ICON_ALIASES: dict[str, tuple[str, ...]] = {
    "visual-studio-code": ("com.visualstudio.code.oss", "code", "visual-studio-code-bin"),
    "visual-studio-code-bin": ("visual-studio-code", "com.visualstudio.code.oss", "code"),
    "nvim": ("neovim", "nvim-qt"),
    "telegram": ("org.telegram.desktop", "telegram-desktop"),
    "telegram-desktop": ("telegram", "org.telegram.desktop"),
    "vlc": ("vlc",),
    "spotify-client": ("spotify",),
    "spotify": ("spotify-client",),
    "obs-studio": ("com.obsproject.Studio", "obs"),
    "gimp": ("gimp", "org.gimp.GIMP"),
    "inkscape": ("org.inkscape.Inkscape", "inkscape"),
    "libreoffice-fresh": ("libreoffice-main", "libreoffice-startcenter"),
}

ICON_SEARCH_DIRS = (
    "/usr/share/icons/hicolor/scalable/apps",
    "/usr/share/icons/hicolor/256x256/apps",
    "/usr/share/icons/hicolor/128x128/apps",
    "/usr/share/icons/hicolor/64x64/apps",
    "/usr/share/icons/hicolor/48x48/apps",
    "/usr/share/pixmaps",
)

# PyQt6 GUI imports at module level
from PyQt6.QtCore import QSize, Qt, QUrl
from PyQt6.QtGui import QFont, QGuiApplication, QIcon, QPixmap
from PyQt6.QtQml import QQmlApplicationEngine
from PyQt6.QtQuick import QQuickImageProvider

from backend import (
    CatalogService,
    StoreController,
    ThemeService,
    TransactionService,
    is_mock_mode,
)


class XdgIconImageProvider(QQuickImageProvider):
    """Provides native XDG system icons to QML via image://xdgicon/<name>."""

    def __init__(self) -> None:
        super().__init__(QQuickImageProvider.ImageType.Pixmap)

    def requestPixmap(self, id_str: str, requestedSize: QSize) -> tuple[QPixmap, QSize]:
        """Resolve and render XDG icon from theme or file paths."""
        icon_id = id_str.split("?")[0].strip()

        # Reject generic fallback tokens so QML displays semantic Material Symbols instead
        if not icon_id or icon_id in GENERIC_FALLBACK_ICONS:
            return QPixmap(), QSize(0, 0)

        # Target dimensions
        target_w = requestedSize.width() if (requestedSize and requestedSize.width() > 0) else 64
        target_h = requestedSize.height() if (requestedSize and requestedSize.height() > 0) else 64

        # Direct absolute path provided
        if icon_id.startswith("/") and os.path.isfile(icon_id):
            pix = QPixmap(icon_id)
            if not pix.isNull():
                if target_w > 0 and target_h > 0:
                    pix = pix.scaled(
                        target_w,
                        target_h,
                        Qt.AspectRatioMode.KeepAspectRatio,
                        Qt.TransformationMode.SmoothTransformation,
                    )
                return pix, pix.size()

        # Build list of lookup candidate names
        candidates = [icon_id]
        if icon_id in COMMON_ICON_ALIASES:
            candidates.extend(COMMON_ICON_ALIASES[icon_id])

        # 1. Lookup via active XDG Icon Theme
        for cand in candidates:
            icon = QIcon.fromTheme(cand)
            if not icon.isNull():
                pix = icon.pixmap(target_w, target_h)
                if not pix.isNull():
                    return pix, pix.size()

        # 2. Lookup via direct filesystem paths
        for cand in candidates:
            for sdir in ICON_SEARCH_DIRS:
                for ext in (".svg", ".png", ".xpm"):
                    p = os.path.join(sdir, f"{cand}{ext}")
                    if os.path.isfile(p):
                        pix = QPixmap(p)
                        if not pix.isNull():
                            if target_w > 0 and target_h > 0:
                                pix = pix.scaled(
                                    target_w,
                                    target_h,
                                    Qt.AspectRatioMode.KeepAspectRatio,
                                    Qt.TransformationMode.SmoothTransformation,
                                )
                            return pix, pix.size()

        return QPixmap(), QSize(0, 0)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        prog="redshift-store",
        description="Redshift Store — Loja Nativa de Aplicativos do Redshift OS",
    )
    parser.add_argument(
        "--mock",
        action="store_true",
        help="Executar em modo simulado/mock (sem alterar pacotes reais do sistema)",
    )
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="Executar autoteste de inicialização headless e sair",
    )
    parser.add_argument(
        "--page",
        type=str,
        default="home",
        choices=["home", "catalog", "installed", "updates"],
        help="Página inicial a ser aberta (home, catalog, installed, updates)",
    )
    parser.add_argument(
        "--version",
        action="version",
        version=f"%(prog)s {VERSION}",
    )
    return parser.parse_args(argv)


def main() -> int:
    """Initialize and run Redshift Store."""
    args = parse_args()

    # Enable mock mode if requested via CLI
    if args.mock:
        os.environ["REDSHIFT_STORE_MOCK"] = "1"
        logger.info("Modo Mock ativado via CLI (--mock)")

    # For self-test in headless/CI environments, force offscreen platform if no display
    is_headless = not (os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY"))
    if args.self_test and is_headless:
        os.environ["QT_QPA_PLATFORM"] = "offscreen"

    # Suppress non-critical portal registration warning when running outside flatpak/portal sandbox
    os.environ.setdefault("QT_LOGGING_RULES", "qt.qpa.services.warning=false")

    app = QGuiApplication(sys.argv)
    app.setApplicationName("Redshift Store")
    app.setOrganizationName("Redshift OS")
    app.setDesktopFileName("redshift-store")

    # Set Application Icon
    icon_candidates = [
        os.path.expanduser("~/.local/share/redshift-os/icons/redshift-compact.png"),
        os.path.expanduser("~/.local/share/icons/hicolor/scalable/apps/redshift-store.svg"),
        "/usr/share/icons/hicolor/scalable/apps/system-software-install.svg",
    ]
    for ic_path in icon_candidates:
        if os.path.isfile(ic_path):
            app.setWindowIcon(QIcon(ic_path))
            break
    else:
        app.setWindowIcon(QIcon.fromTheme("system-software-install"))

    # Resolve directories
    base_dir = Path(__file__).resolve().parent
    qml_dir = base_dir / "qml"
    main_qml = qml_dir / "Main.qml"

    # Instantiate Bridges
    mock_active = is_mock_mode()
    theme_bridge = ThemeService(parent=app)
    catalog_service = CatalogService(mock_mode=mock_active)
    tx_service = TransactionService(parent=app, mock_mode=mock_active)
    store_bridge = StoreController(
        parent=app,
        catalog_service=catalog_service,
        transaction_service=tx_service,
        mock_mode=mock_active,
    )

    # Initialize QML Engine (do not parent to app so engine can be destroyed before QGuiApplication teardown)
    engine = QQmlApplicationEngine()

    # Register XDG Icon Image Provider
    icon_provider = XdgIconImageProvider()
    engine.addImageProvider("xdgicon", icon_provider)

    # Configure Import Paths
    engine.addImportPath(str(qml_dir))
    engine.addImportPath(str(qml_dir / "theme"))
    engine.addImportPath(str(qml_dir / "components"))
    engine.addImportPath(str(qml_dir / "pages"))

    # Register Context Properties
    ctx = engine.rootContext()
    ctx.setContextProperty("ThemeBridge", theme_bridge)
    ctx.setContextProperty("StoreBridge", store_bridge)
    ctx.setContextProperty("InitialPage", args.page)

    # Self-test validation
    if args.self_test:
        logger.info("=== Executando Autoteste Headless do Redshift Store ===")
        assert theme_bridge is not None, "ThemeBridge não foi instanciado"
        assert store_bridge is not None, "StoreBridge não foi instanciado"
        assert store_bridge.catalogModel is not None, "catalogModel não disponível"
        assert store_bridge.featuredModel is not None, "featuredModel não disponível"
        assert store_bridge.installedModel is not None, "installedModel não disponível"
        assert store_bridge.updatesModel is not None, "updatesModel não disponível"
        logger.info("Featured packages count: %d", store_bridge.featuredModel.count)
        logger.info("Installed packages count: %d", store_bridge.installedCount)
        logger.info("Operation state: %s", store_bridge.operationState)
        logger.info("Mock mode active: %s", mock_active)

        # Validate XdgIconImageProvider
        test_pix, test_sz = icon_provider.requestPixmap("firefox", QSize(64, 64))
        logger.info("XDG Icon 'firefox' resolved: %s (size: %s)", not test_pix.isNull(), test_sz)
        fallback_pix, fallback_sz = icon_provider.requestPixmap("applications-other", QSize(64, 64))
        assert fallback_pix.isNull(), "Generic fallback must return empty pixmap"

        if main_qml.is_file():
            logger.info("Carregando Main.qml para validação de sintaxe QML...")
            engine.load(QUrl.fromLocalFile(str(main_qml)))
            if not engine.rootObjects():
                logger.error("Falha ao instanciar root object de Main.qml")
                del engine
                return 1
            app.processEvents()
            logger.info("QML Main.qml carregado com sucesso.")
        else:
            logger.info("Main.qml ainda não presente no worktree local (validação de backend concluída com sucesso).")

        del engine
        app.processEvents()
        logger.info("=== AUTOTESTE CONCLUÍDO COM SUCESSO (Status 0) ===")
        return 0

    # Normal Execution: Load Main.qml
    if not main_qml.is_file():
        logger.error("Arquivo principal QML não encontrado: %s", main_qml)
        del engine
        return 1

    engine.load(QUrl.fromLocalFile(str(main_qml)))
    if not engine.rootObjects():
        logger.error("Não foi possível carregar a interface QML principal.")
        del engine
        return 1

    exit_code = app.exec()
    del engine
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
