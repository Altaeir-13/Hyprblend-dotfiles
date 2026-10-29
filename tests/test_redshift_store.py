#!/usr/bin/env python3
"""Automated Test Suite for Redshift Store.

Covers:
1. Security guardrails (package validation, injection prevention, protected packages, non-root enforcement, safe commands).
2. Data models and QAbstractListModel (PackageItem, PackageListModel, roles).
3. Catalog discovery (Mock mode and real read-only /var/lib/pacman/local integration).
4. Material You theme synchronization and token normalization (ThemeService).
5. Asynchronous transaction workflow and StoreController facade.
6. Headless Qt6/QML engine integration and navigation (Main.qml).
"""

from __future__ import annotations

import io
import json
import os
import sys
import tarfile
import tempfile
import time
import unittest
import urllib.error
from pathlib import Path
from unittest.mock import patch

# Force offscreen rendering for headless CI / unit test environments
os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("REDSHIFT_STORE_MOCK", "1")

# Ensure Redshift Store package root is available in sys.path
STORE_ROOT = Path(__file__).resolve().parent.parent / "dots" / ".local" / "share" / "redshift-os" / "redshift-store"
if str(STORE_ROOT) not in sys.path:
    sys.path.insert(0, str(STORE_ROOT))

from PyQt6.QtCore import QCoreApplication, QModelIndex, Qt
from PyQt6.QtGui import QGuiApplication
from PyQt6.QtQml import QQmlApplicationEngine
from PyQt6.QtCore import QUrl

from backend import (
    CatalogService,
    MaintenanceService,
    PackageItem,
    PackageListModel,
    PackageRoles,
    SecurityViolationError,
    StoreController,
    ThemeService,
    TransactionService,
    build_safe_pacman_install_cmd,
    build_safe_pacman_remove_cmd,
    build_safe_pacman_sysupgrade_cmd,
    build_safe_yay_install_cmd,
    build_safe_yay_sysupgrade_cmd,
    ensure_non_root_for_aur,
    ensure_not_protected,
    ensure_polkit_agent,
    ensure_valid_package_name,
    get_protected_reverse_dependencies,
    is_pacman_locked,
    is_polkit_agent_running,
    is_protected_package,
    validate_package_name,
)
from main import XdgIconImageProvider


# Shared Qt Application instance
_QT_APP = None


def get_qt_app() -> QGuiApplication:
    global _QT_APP
    if _QT_APP is None:
        _QT_APP = QGuiApplication.instance() or QGuiApplication(sys.argv)
    return _QT_APP


# =============================================================================
# 1. Testes de Segurança (TestSecurityGuardrails)
# =============================================================================
class TestSecurityGuardrails(unittest.TestCase):
    """Validates input sanitization, flag injection prevention, and security policies."""

    def test_valid_package_names_accepted(self) -> None:
        valid_samples = [
            "firefox",
            "lib32-mesa",
            "gtk4+",
            "c++",
            "quickshell-git",
            "python-pyqt6",
            "xorg-server.common",
            "package@1.2",
            "a",
        ]
        for name in valid_samples:
            with self.subTest(name=name):
                self.assertTrue(validate_package_name(name), f"Expected {name!r} to be valid")
                self.assertEqual(ensure_valid_package_name(name), name)

    def test_malicious_names_and_flags_rejected(self) -> None:
        malicious_samples = [
            "-Syu",
            "--noconfirm",
            "-S",
            "-R",
            "foo; rm -rf /",
            "foo && id",
            "foo | cat",
            "../etc/passwd",
            "`id`",
            "$(id)",
            "$HOME",
            "",
            "   ",
            "\n",
            "-invalid",
            "has space",
            "foo&bar",
            "pkg#test",
            "pkg!name",
        ]
        for name in malicious_samples:
            with self.subTest(name=name):
                self.assertFalse(validate_package_name(name), f"Expected {name!r} to be invalid")
                with self.assertRaises(SecurityViolationError):
                    ensure_valid_package_name(name)

    def test_protected_critical_packages_blocked(self) -> None:
        critical_packages = [
            "pacman",
            "glibc",
            "linux",
            "systemd",
            "hyprland",
            "quickshell-git",
            "python-pyqt6",
        ]
        for pkg in critical_packages:
            with self.subTest(package=pkg):
                self.assertTrue(is_protected_package(pkg), f"Expected {pkg!r} to be protected")
                with self.assertRaises(SecurityViolationError):
                    ensure_not_protected(pkg)
                with self.assertRaises(SecurityViolationError):
                    build_safe_pacman_remove_cmd([pkg])

    def test_ensure_non_root_for_aur(self) -> None:
        with patch("os.geteuid", return_value=0):
            with self.assertRaises(SecurityViolationError):
                ensure_non_root_for_aur()
            with self.assertRaises(SecurityViolationError):
                build_safe_yay_install_cmd(["visual-studio-code-bin"])
            with self.assertRaises(SecurityViolationError):
                build_safe_yay_sysupgrade_cmd()

        with patch("os.geteuid", return_value=1000):
            # Non-root user: must succeed without exception
            ensure_non_root_for_aur()

    def test_safe_command_builders(self) -> None:
        with patch("os.geteuid", return_value=1000):
            # 1. Pacman install
            cmd_inst = build_safe_pacman_install_cmd(["firefox", "lib32-mesa"])
            self.assertEqual(cmd_inst[:2], ["/usr/bin/pkexec", "/usr/bin/pacman"])
            self.assertIn("-S", cmd_inst)
            self.assertIn("--needed", cmd_inst)
            self.assertIn("--", cmd_inst)
            dash_idx = cmd_inst.index("--")
            self.assertEqual(cmd_inst[dash_idx + 1 :], ["firefox", "lib32-mesa"])

            # 2. Pacman remove
            cmd_rem = build_safe_pacman_remove_cmd(["fuzzel"])
            self.assertEqual(cmd_rem[:2], ["/usr/bin/pkexec", "/usr/bin/pacman"])
            self.assertIn("-R", cmd_rem)
            self.assertIn("--", cmd_rem)
            dash_idx = cmd_rem.index("--")
            self.assertEqual(cmd_rem[dash_idx + 1 :], ["fuzzel"])

            # 3. Pacman sysupgrade
            cmd_sysup = build_safe_pacman_sysupgrade_cmd()
            self.assertEqual(cmd_sysup[:3], ["/usr/bin/pkexec", "/usr/bin/pacman", "-Syu"])

            # 4. Yay install (H-BACK1: --cleanmenu and --diffmenu preserved, never --answerclean/--answerdiff None)
            cmd_yay_inst = build_safe_yay_install_cmd(["visual-studio-code-bin"])
            self.assertEqual(cmd_yay_inst[0], "/usr/bin/yay")
            self.assertIn("--sudo", cmd_yay_inst)
            sudo_idx = cmd_yay_inst.index("--sudo")
            self.assertEqual(cmd_yay_inst[sudo_idx + 1], "/usr/bin/pkexec")
            self.assertIn("--cleanmenu", cmd_yay_inst)
            self.assertIn("--diffmenu", cmd_yay_inst)
            self.assertNotIn("--answerclean", cmd_yay_inst)
            self.assertNotIn("--answerdiff", cmd_yay_inst)
            self.assertIn("--", cmd_yay_inst)
            dash_idx = cmd_yay_inst.index("--")
            self.assertEqual(cmd_yay_inst[dash_idx + 1 :], ["visual-studio-code-bin"])

            # 5. Yay sysupgrade (H-BACK1: --cleanmenu and --diffmenu preserved, safe -Syu full upgrade)
            cmd_yay_sys = build_safe_yay_sysupgrade_cmd()
            self.assertEqual(cmd_yay_sys[0], "/usr/bin/yay")
            self.assertIn("-Syu", cmd_yay_sys)
            self.assertNotIn("-Sua", cmd_yay_sys)
            self.assertIn("--sudo", cmd_yay_sys)
            self.assertIn("--cleanmenu", cmd_yay_sys)
            self.assertIn("--diffmenu", cmd_yay_sys)
            self.assertNotIn("--answerclean", cmd_yay_sys)
            self.assertNotIn("--answerdiff", cmd_yay_sys)

            # 6. Verify --noconfirm is never forced in any safe command builder
            for cmd in (cmd_inst, cmd_rem, cmd_sysup, cmd_yay_inst, cmd_yay_sys):
                self.assertNotIn("--noconfirm", cmd)

            # 7. Verify unsafe custom binary/config paths are rejected
            with patch.dict(os.environ, {"REDSHIFT_PACMAN_BIN": "relative/pacman"}):
                with self.assertRaises(SecurityViolationError):
                    build_safe_pacman_install_cmd(["firefox"])
            with patch.dict(os.environ, {"REDSHIFT_PACMAN_CONF": "/tmp/bad path/pacman.conf"}):
                with self.assertRaises(SecurityViolationError):
                    build_safe_pacman_install_cmd(["firefox"])

    def test_pacman_lock_detection(self) -> None:
        with tempfile.NamedTemporaryFile() as tmp:
            with patch.dict(os.environ, {"REDSHIFT_PACMAN_LOCK_PATH": tmp.name}):
                self.assertTrue(is_pacman_locked())

        non_existent = "/tmp/test_pacman_lock_should_not_exist_xyz123.lck"
        if os.path.exists(non_existent):
            os.unlink(non_existent)
        with patch.dict(os.environ, {"REDSHIFT_PACMAN_LOCK_PATH": non_existent}):
            self.assertFalse(is_pacman_locked())

    def test_reverse_dependency_protection_and_polkit_agent(self) -> None:
        """Verify reverse dependency checks and Polkit agent detection."""
        with patch(
            "backend.security.get_protected_reverse_dependencies",
            return_value=["hyprland"],
        ):
            with self.assertRaises(SecurityViolationError):
                ensure_not_protected("custom-wlroots-dep", check_reverse_deps=True)
            with self.assertRaises(SecurityViolationError):
                build_safe_pacman_remove_cmd(["custom-wlroots-dep"])

        # Polkit agent detection via proc_root sandbox
        with tempfile.TemporaryDirectory() as tmp_proc:
            self.assertFalse(is_polkit_agent_running(proc_root=tmp_proc))
            fake_pid_dir = Path(tmp_proc) / "999999"
            fake_pid_dir.mkdir()
            (fake_pid_dir / "comm").write_text("polkit-kde-auth\n", encoding="utf-8")
            (fake_pid_dir / "cmdline").write_bytes(b"/usr/lib/polkit-kde-authentication-agent-1\x00")
            self.assertTrue(is_polkit_agent_running(proc_root=tmp_proc))

        with patch("backend.security.is_polkit_agent_running", return_value=True):
            self.assertTrue(ensure_polkit_agent())


# =============================================================================
# 2. Testes de Modelos (TestPackageModels)
# =============================================================================
class TestPackageModels(unittest.TestCase):
    """Tests PackageItem schema serialization and PackageListModel QML bindings."""

    @classmethod
    def setUpClass(cls) -> None:
        get_qt_app()

    def test_package_item_to_dict_and_from_dict(self) -> None:
        item = PackageItem(
            name="firefox",
            display_name="Firefox Web Browser",
            summary="Fast and private web browser",
            description="Detailed browser description",
            version="130.0-1",
            installed_version="129.0-1",
            repository="extra",
            source="official",
            installed=True,
            explicit=True,
            update_available=True,
            category="internet",
            icon_name="firefox",
            installed_size="120 MiB",
            download_size="65 MiB",
            license="MPL-2.0",
            url="https://mozilla.org/firefox",
            depends=["gtk3", "nss"],
            optdepends=["networkmanager"],
            votes=1250,
            popularity=85.5,
            maintainer="Arch Linux Team",
            is_protected=False,
        )

        d = item.to_dict()
        # Verify snake_case keys
        self.assertEqual(d["name"], "firefox")
        self.assertEqual(d["display_name"], "Firefox Web Browser")
        self.assertEqual(d["installed"], True)
        self.assertEqual(d["update_available"], True)
        self.assertEqual(d["is_protected"], False)

        # Verify camelCase aliases for direct QML property consumption
        self.assertEqual(d["displayName"], "Firefox Web Browser")
        self.assertEqual(d["installedVersion"], "129.0-1")
        self.assertEqual(d["updateAvailable"], True)
        self.assertEqual(d["iconName"], "firefox")
        self.assertEqual(d["installedSize"], "120 MiB")
        self.assertEqual(d["downloadSize"], "65 MiB")
        self.assertEqual(d["isProtected"], False)

        # Roundtrip from_dict
        restored = PackageItem.from_dict(d)
        self.assertEqual(restored.name, item.name)
        self.assertEqual(restored.display_name, item.display_name)
        self.assertEqual(restored.version, item.version)
        self.assertEqual(restored.installed, item.installed)

    def test_package_list_model_roles_and_data(self) -> None:
        model = PackageListModel()
        self.assertEqual(model.rowCount(), 0)
        self.assertEqual(model.count, 0)

        # Validate 34 role names mapping
        roles = model.roleNames()
        self.assertEqual(len(roles), 34)
        role_values = [v.data().decode("utf-8") for v in roles.values()]
        expected_roles = [
            "name",
            "displayName",
            "summary",
            "description",
            "version",
            "installedVersion",
            "repository",
            "source",
            "installed",
            "explicit",
            "updateAvailable",
            "category",
            "iconName",
            "installedSize",
            "downloadSize",
            "license",
            "url",
            "depends",
            "optdepends",
            "votes",
            "popularity",
            "maintainer",
            "isProtected",
            "itemData",
            "isApplication",
            "appId",
            "screenshots",
            "popularitySource",
            "popularityLabel",
            "provenance",
            "provenanceLabel",
            "isFavorite",
            "buildDate",
            "groups",
        ]
        for er in expected_roles:
            self.assertIn(er, role_values, f"Role '{er}' missing from roleNames")

        # Populate items
        item1 = PackageItem(name="neovim", display_name="Neovim", category="development", installed=True)
        item2 = PackageItem(name="kitty", display_name="Kitty Terminal", category="system", installed=False)
        model.set_items([item1, item2])

        self.assertEqual(model.rowCount(), 2)
        self.assertEqual(model.count, 2)

        idx0 = model.index(0, 0)
        self.assertEqual(model.data(idx0, PackageRoles.NameRole), "neovim")
        self.assertEqual(model.data(idx0, PackageRoles.DisplayNameRole), "Neovim")
        self.assertEqual(model.data(idx0, PackageRoles.CategoryRole), "development")
        self.assertEqual(model.data(idx0, PackageRoles.InstalledRole), True)
        self.assertIsInstance(model.data(idx0, PackageRoles.ItemDataRole), dict)

        # Validate incremental append_items
        item3 = PackageItem(name="alacritty", display_name="Alacritty", category="system", installed=False)
        item4 = PackageItem(name="kitty", display_name="Kitty Duplicate", category="system")  # Duplicate should be ignored
        model.append_items([item3, item4])
        self.assertEqual(model.rowCount(), 3)
        self.assertEqual(model.count, 3)
        self.assertEqual(model.get_at(2).name, "alacritty")

        # Lookup methods
        self.assertEqual(model.get_by_name("neovim"), item1)
        self.assertEqual(model.get_by_name("kitty"), item2)
        self.assertIsNone(model.get_by_name("nonexistent"))

        dict_data = model.get_dict_by_name("neovim")
        self.assertEqual(dict_data.get("name"), "neovim")

        # Clear
        model.clear()
        self.assertEqual(model.rowCount(), 0)
        self.assertEqual(model.count, 0)


# =============================================================================
# 3. Testes de Catálogo Real + Mock (TestCatalogService)
# =============================================================================
class TestCatalogService(unittest.TestCase):
    """Tests package indexing, filtering, AppStream/Desktop enrichment and updates."""

    def test_mock_catalog_service_queries(self) -> None:
        cat = CatalogService(mock_mode=True)
        self.assertTrue(cat.mock_mode)

        # 1. Featured packages
        featured = cat.get_featured_packages()
        self.assertGreaterEqual(len(featured), 10, "Expected at least 10 featured packages in mock mode")

        # 2. Text search
        results_code = cat.search(query="code")
        self.assertTrue(any("code" in p.name.lower() or "code" in p.summary.lower() for p in results_code))

        # 3. Source filter (AUR)
        results_aur = cat.search(query="bin", source_filter="aur")
        self.assertTrue(all(p.source == "aur" for p in results_aur))

        # 4. Source filter (Official)
        results_off = cat.search(query="", source_filter="official")
        self.assertTrue(all(p.source == "official" for p in results_off))

        # 5. Category filter
        results_dev = cat.search(query="", category_filter="development")
        self.assertTrue(all(p.category == "development" for p in results_dev))

        # 6. Check updates
        updates = cat.check_updates()
        self.assertGreaterEqual(len(updates), 2)
        self.assertTrue(all(p.update_available for p in updates))

        # 7. Fetch AUR PKGBUILD preview
        pkgbuild = cat.fetch_aur_pkgbuild("visual-studio-code-bin")
        self.assertIn("pkgname=", pkgbuild)
        self.assertIn("pkgver=", pkgbuild)

    def test_real_pacman_local_indexing(self) -> None:
        """Read-only test against real /var/lib/pacman/local if present on host."""
        pacman_dir = "/var/lib/pacman/local"
        if not os.path.isdir(pacman_dir):
            self.skipTest("Host does not have /var/lib/pacman/local (non-Arch environment)")

        cat = CatalogService(mock_mode=False)
        self.assertFalse(cat.mock_mode)

        t0 = time.time()
        installed = cat.get_installed_packages()
        duration = time.time() - t0

        self.assertGreater(len(installed), 100, f"Expected >100 installed packages, found {len(installed)}")
        self.assertLess(duration, 3.0, f"Native indexing took too long: {duration:.2f}s")

        # Verify critical base packages are found and marked protected
        installed_names = {p.name: p for p in installed}
        self.assertIn("pacman", installed_names)
        self.assertIn("python", installed_names)
        self.assertTrue(installed_names["pacman"].is_protected)
        self.assertTrue(installed_names["pacman"].installed)


# =============================================================================
# 4. Testes de Sincronização Material You (TestThemeService)
# =============================================================================
class TestThemeService(unittest.TestCase):
    """Tests dynamic color extraction, 49 M3 tokens, and file watcher reactivity."""

    @classmethod
    def setUpClass(cls) -> None:
        get_qt_app()

    def test_theme_loading_and_tokens(self) -> None:
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp = Path(tmp_dir)
            colors_path = tmp / "colors.json"
            scheme_path = tmp / "scheme.json"
            ui_switch_path = tmp / "ui-switch"
            wall_path = tmp / "wallpaper.txt"
            applied_scheme_path = tmp / "applied_scheme_type.txt"

            # Setup sample colors.json
            sample_colors = {
                "background": "#121316",
                "primary": "#d0bcff",
                "on_primary": "#381e72",
                "primary_container": "#4f378b",
                "on_primary_container": "#eaddff",
                "surface": "#121316",
                "on_surface": "#e6e1e5",
            }
            colors_path.write_text(json.dumps(sample_colors), encoding="utf-8")
            ui_switch_path.write_text("caelestia", encoding="utf-8")
            wall_path.write_text("/usr/share/backgrounds/redshift.png", encoding="utf-8")
            applied_scheme_path.write_text("scheme-tonal-spot", encoding="utf-8")

            with patch.dict(
                os.environ,
                {
                    "REDSHIFT_COLORS_JSON_PATH": str(colors_path),
                    "REDSHIFT_CAELESTIA_SCHEME_PATH": str(scheme_path),
                    "REDSHIFT_UI_SWITCH_STATE_PATH": str(ui_switch_path),
                    "REDSHIFT_WALLPAPER_PATH_FILE": str(wall_path),
                    "REDSHIFT_APPLIED_SCHEME_TYPE_PATH": str(applied_scheme_path),
                },
            ):
                theme = ThemeService()

                self.assertTrue(theme.isDark)
                self.assertEqual(theme.schemeVariant, "scheme-tonal-spot")
                self.assertEqual(theme.activeShellMode, "caelestia")
                self.assertEqual(theme.wallpaperPath, "/usr/share/backgrounds/redshift.png")

                colors = theme.colors
                self.assertIn("primary", colors)
                self.assertIn("primary_container", colors)
                self.assertIn("primaryContainer", colors)
                self.assertIn("m3primaryContainer", colors)
                self.assertIn("surface", colors)
                self.assertIn("success", colors)
                self.assertIn("warning", colors)

                # Test preview toggle (Dark -> Light -> Dark restored)
                self.assertTrue(theme.isDark)
                theme.togglePreviewMode()
                self.assertFalse(theme.isDark, "Expected light mode preview on first toggle")
                theme.togglePreviewMode()
                self.assertTrue(theme.isDark, "Expected original dark mode restored on second toggle")

                # Test atomic file replacement
                updated_colors = {
                    "background": "#fdf8fd",
                    "primary": "#6750a4",
                    "surface": "#fdf8fd",
                }
                new_temp = tmp / "colors.json.tmp"
                new_temp.write_text(json.dumps(updated_colors), encoding="utf-8")
                os.replace(new_temp, colors_path)

                theme.reloadTheme()
                self.assertFalse(theme.isDark, "Expected light mode detected from new background hex")

    def test_caelestia_and_end4_priority_and_low_contrast_guard(self) -> None:
        """Verify H-MAT1 dynamic priority between colors.json and scheme.json, and WCAG low-contrast protection."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp = Path(tmp_dir)
            colors_path = tmp / "colors.json"
            scheme_path = tmp / "scheme.json"
            ui_switch_path = tmp / "ui-switch"

            # 1. Both files present: in caelestia mode, scheme.json takes priority over colors.json
            colors_path.write_text(
                json.dumps({"background": "#121316", "primary": "#ff0000", "surface": "#121316"}),
                encoding="utf-8",
            )
            scheme_path.write_text(
                json.dumps(
                    {
                        "mode": "dark",
                        "variant": "fidelity",
                        "colours": {"background": "141318", "primary": "7bd0ff", "surface": "141318"},
                    }
                ),
                encoding="utf-8",
            )
            ui_switch_path.write_text("caelestia", encoding="utf-8")

            with patch.dict(
                os.environ,
                {
                    "REDSHIFT_COLORS_JSON_PATH": str(colors_path),
                    "REDSHIFT_CAELESTIA_SCHEME_PATH": str(scheme_path),
                    "REDSHIFT_UI_SWITCH_STATE_PATH": str(ui_switch_path),
                },
            ):
                theme = ThemeService()
                self.assertEqual(theme.frontendMode, "caelestia")
                self.assertEqual(theme.colors["primary"].lower(), "#7bd0ff")

                # 2. Switch to end4 mode with newer colors.json: colors.json takes priority
                ui_switch_path.write_text("end4", encoding="utf-8")
                colors_path.write_text(
                    json.dumps({"background": "#121316", "primary": "#d0bcff", "surface": "#121316"}),
                    encoding="utf-8",
                )
                os.utime(colors_path, (time.time() + 10, time.time() + 10))
                theme.reloadTheme()
                self.assertEqual(theme.frontendMode, "end4")
                self.assertEqual(theme.colors["primary"].lower(), "#d0bcff")

                # 3. Low-contrast pathological dark palette (primary == surface == #141318, on_surface == #16151a)
                colors_path.write_text(
                    json.dumps(
                        {
                            "background": "#141318",
                            "surface": "#141318",
                            "surface_container": "#151419",
                            "primary": "#141318",
                            "secondary": "#141318",
                            "tertiary": "#141318",
                            "on_surface": "#16151a",
                            "on_surface_variant": "#17161b",
                        }
                    ),
                    encoding="utf-8",
                )
                os.utime(colors_path, (time.time() + 20, time.time() + 20))
                theme.reloadTheme()
                self.assertNotEqual(theme.colors["primary"].lower(), "#141318")
                self.assertNotEqual(theme.colors["on_surface"].lower(), "#16151a")
                self.assertEqual(theme.colors["on_surface"].lower(), "#e5e3d8")


# =============================================================================
# 5. Testes de Transação Assíncrona e Controller (TestStoreControllerAndTransactions)
# =============================================================================
class TestStoreControllerAndTransactions(unittest.TestCase):
    """Tests StoreController QObject facade and simulated async transaction execution."""

    @classmethod
    def setUpClass(cls) -> None:
        get_qt_app()

    def test_controller_initialization_and_mock_transactions(self) -> None:
        app = get_qt_app()
        ctrl = StoreController(mock_mode=True)

        self.assertIsNotNone(ctrl.catalogModel)
        self.assertIsNotNone(ctrl.featuredModel)
        self.assertIsNotNone(ctrl.installedModel)
        self.assertIsNotNone(ctrl.updatesModel)
        self.assertGreater(ctrl.featuredModel.count, 0)
        self.assertEqual(ctrl.operationState, "idle")
        self.assertFalse(ctrl.isBusy)

        # 1. Start mock install operation
        ctrl.installPackage("fastfetch", "official")
        self.assertTrue(ctrl.isBusy)
        self.assertEqual(ctrl.operationState, "installing")

        # Advance mock steps deterministically
        tx = ctrl._tx_service
        for _ in range(5):
            tx._on_mock_step()
            app.processEvents()

        self.assertFalse(ctrl.isBusy)
        self.assertIn(ctrl.operationState, ("idle", "success"))
        self.assertIn("[MOCK SUCESSO]", ctrl.logText)

        # 2. Block removal of protected package
        ctrl.clearLogs()
        remove_success = ctrl._tx_service.remove_package("hyprland")
        self.assertFalse(remove_success, "Removal of 'hyprland' must return False")
        self.assertNotEqual(ctrl.operationState, "removing")

        # 3. Pacman db.lck active simulation
        with tempfile.NamedTemporaryFile() as tmp_lock:
            with patch.dict(os.environ, {"REDSHIFT_PACMAN_LOCK_PATH": tmp_lock.name}):
                self.assertTrue(ctrl.isDbLocked)
                inst_res = ctrl._tx_service.install_package("curl")
                self.assertFalse(inst_res, "Installation must be blocked when pacman is locked")

    def test_stage_aware_cancellation_and_interactive_prompts(self) -> None:
        """Verify stage-aware safe cancellation (no SIGKILL) and interactive prompt handling."""
        ctrl = StoreController(mock_mode=True)
        tx = ctrl._tx_service

        # 1. Verify _force_kill_if_running does not exist and SIGKILL is never invoked
        self.assertFalse(
            hasattr(tx, "_force_kill_if_running"),
            "TransactionService must NEVER have _force_kill_if_running (SIGKILL)",
        )
        tx_source = (STORE_ROOT / "backend" / "transaction_service.py").read_text(encoding="utf-8")
        self.assertNotIn("signal.SIGKILL", tx_source)
        self.assertNotIn(".kill()", tx_source)

        # 2. Verify can_cancel is True in safe stages when db.lck is absent
        non_existent = "/tmp/test_pacman_lock_should_not_exist_xyz123.lck"
        with patch.dict(os.environ, {"REDSHIFT_PACMAN_LOCK_PATH": non_existent}):
            tx._set_state("installing", "Instalando...")
            for safe_stage in ("checking_updates", "authenticating", "downloading", "compiling"):
                tx._set_stage(safe_stage)
                self.assertTrue(tx.can_cancel, f"Expected can_cancel=True in stage {safe_stage}")
                self.assertTrue(ctrl.canCancel)

            # 3. Verify can_cancel is False in 'committing' stage
            tx._set_stage("committing")
            self.assertFalse(tx.can_cancel, "Expected can_cancel=False during committing stage")
            self.assertFalse(ctrl.canCancel)

            blocked_reasons: list[str] = []
            tx.cancellationBlocked.connect(blocked_reasons.append)
            tx.cancel()
            self.assertEqual(len(blocked_reasons), 1, "cancel() must emit cancellationBlocked in committing stage")

        # 4. Verify can_cancel is False whenever pacman db.lck exists, even in downloading stage
        with tempfile.NamedTemporaryFile() as tmp_lock:
            with patch.dict(os.environ, {"REDSHIFT_PACMAN_LOCK_PATH": tmp_lock.name}):
                tx._set_state("installing", "Instalando...")
                tx._set_stage("downloading")
                self.assertFalse(tx.can_cancel, "Expected can_cancel=False when pacman db.lck exists")

        # 5. Verify interactive prompt detection & stage classification
        with patch.dict(os.environ, {"REDSHIFT_PACMAN_LOCK_PATH": non_existent}):
            tx._update_stage_from_log(":: Retrieving packages...")
            self.assertEqual(tx.stage, "downloading")
            tx._update_stage_from_log("==> Making package: visual-studio-code-bin")
            self.assertEqual(tx.stage, "compiling")
            tx._update_stage_from_log("verificando conflitos de arquivos...")
            self.assertEqual(tx.stage, "committing")
            tx.simulate_prompt_for_test(":: Continuar a instalação? [S/n]")
            self.assertTrue(tx.waiting_for_input)
            self.assertIn("[S/n]", tx.current_prompt_text)
            self.assertTrue(ctrl.waitingForInput)
            self.assertIn("[S/n]", ctrl.currentPromptText)

    def test_aur_interactive_menus_and_polkit_dismissal(self) -> None:
        """Verify H-BACK1 multi-line yay AUR menu prompt detection, GIT_PAGER=cat diff streaming, and Polkit 126 refusal."""
        app = get_qt_app()
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp = Path(tmp_dir)
            fake_yay = tmp / "fake-yay.sh"
            fake_yay.write_text(
                "#!/usr/bin/env bash\n"
                "echo '==> Packages to cleanBuild?'\n"
                "echo '==> [N]one [A]ll [Ab]ort [I]nstalled [No]tInstalled or (1 2 3, 1-3, ^4)'\n"
                "printf '==> '\n"
                "read -r ans1\n"
                "echo \"cleanBuild_answer=$ans1\"\n"
                "echo '==> Diffs to show?'\n"
                "echo '==> [N]one [A]ll [Ab]ort [I]nstalled [No]tInstalled or (1 2 3, 1-3, ^4)'\n"
                "printf '==> '\n"
                "read -r ans2\n"
                "if [[ \"$ans2\" == \"A\" ]]; then\n"
                "  echo \"--- a/PKGBUILD\"\n"
                "  echo \"+++ b/PKGBUILD\"\n"
                "  echo \"@@ -1 +1 @@\"\n"
                "  echo \"+pkgver=1.0.0\"\n"
                "  echo \"PAGER_ENV=${GIT_PAGER}:${PAGER}\"\n"
                "fi\n"
                "printf ':: Proceed with install? [Y/n] '\n"
                "read -r ans3\n"
                "if [[ \"$ans3\" == \"y\" || \"$ans3\" == \"Y\" ]]; then exit 0; else exit 1; fi\n",
                encoding="utf-8",
            )
            fake_yay.chmod(0o755)

            fake_pkexec_dismiss = tmp / "fake-pkexec-dismiss.sh"
            fake_pkexec_dismiss.write_text(
                "#!/usr/bin/env bash\n"
                "echo 'Error executing command as another user: Request dismissed' >&2\n"
                "exit 126\n",
                encoding="utf-8",
            )
            fake_pkexec_dismiss.chmod(0o755)

            non_existent = "/tmp/test_pacman_lock_should_not_exist_xyz123.lck"
            with patch.dict(
                os.environ,
                {
                    "REDSHIFT_YAY_BIN": str(fake_yay),
                    "REDSHIFT_PKEXEC_BIN": str(fake_pkexec_dismiss),
                    "REDSHIFT_PACMAN_LOCK_PATH": non_existent,
                },
            ), patch("backend.transaction_service.ensure_polkit_agent", return_value=True), patch("os.geteuid", return_value=1000):
                tx = TransactionService(mock_mode=False)
                logs: list[str] = []
                prompts: list[str] = []
                tx.logLineReceived.connect(logs.append)

                step = {"idx": 0}
                def on_prompt() -> None:
                    if tx.waiting_for_input:
                        prompts.append(tx.current_prompt_text)
                        step["idx"] += 1
                        if step["idx"] == 1:
                            tx.send_input("N")
                        elif step["idx"] == 2:
                            tx.send_input("A")
                        elif step["idx"] >= 3:
                            tx.send_input("y")

                tx.promptChanged.connect(on_prompt)
                done = {"finished": False, "success": False, "msg": ""}
                tx.transactionFinished.connect(
                    lambda s, a, m: done.update({"finished": True, "success": s, "msg": m})
                )

                ok = tx.install_package("yay-bin", "aur")
                self.assertTrue(ok)
                t0 = time.time()
                while not done["finished"] and (time.time() - t0) < 5.0:
                    app.processEvents()
                    time.sleep(0.01)

                self.assertTrue(done["finished"])
                self.assertTrue(done["success"])
                self.assertGreaterEqual(len(prompts), 3)
                full_log = "\n".join(logs)
                self.assertIn("+pkgver=1.0.0", full_log)
                self.assertIn("PAGER_ENV=cat:cat", full_log)

                # Test Polkit refusal (exit 126) on official install
                done["finished"] = False
                ok2 = tx.install_package("firefox", "official")
                self.assertTrue(ok2)
                t0 = time.time()
                while not done["finished"] and (time.time() - t0) < 5.0:
                    app.processEvents()
                    time.sleep(0.01)

                self.assertTrue(done["finished"])
                self.assertFalse(done["success"])
                self.assertEqual(tx.state, "cancelled")
                self.assertIn("Polkit", done["msg"])

    def test_19_non_blocking_startup_check_updates(self) -> None:
        """Verify startup checkUpdates does not block main thread in real mode."""
        app = get_qt_app()
        cat_srv = CatalogService(mock_mode=False)
        cat_srv.refresh_installed = lambda: None
        cat_srv.get_installed_packages = lambda **kwargs: []
        cat_srv.get_featured_packages = lambda: []

        def slow_check_updates():
            time.sleep(0.4)
            return [PackageItem(name="mock-update", version="2.0", installed_version="1.0", update_available=True)]

        cat_srv.check_updates = slow_check_updates

        t0 = time.time()
        ctrl = StoreController(catalog_service=cat_srv)
        t_init = time.time() - t0
        self.assertLess(t_init, 0.35, f"StoreController.__init__ took too long: {t_init:.3f}s")
        self.assertEqual(ctrl.updatesCount, 0)

        # Wait for background thread to complete and emit _updatesLoaded
        t_wait_start = time.time()
        while ctrl.updatesCount == 0 and (time.time() - t_wait_start) < 2.0:
            app.processEvents()
            time.sleep(0.02)

        self.assertEqual(ctrl.updatesCount, 1)
        self.assertEqual(ctrl.updatesModel.get_at(0).name, "mock-update")


# =============================================================================
# 6. Testes de Integração Headless Qt6/QML (TestQmlHeadlessIntegration)
# =============================================================================
class TestQmlHeadlessIntegration(unittest.TestCase):
    """Tests headless instantiation and interactive QML navigation in Main.qml."""

    @classmethod
    def setUpClass(cls) -> None:
        get_qt_app()

    def test_xdg_icon_provider_and_theme_qml_contrast(self) -> None:
        """Verify XdgIconImageProvider resolution and Theme.qml signal-collision prevention."""
        from PyQt6.QtCore import QSize

        provider = XdgIconImageProvider()
        # Generic fallback icon names must return null pixmap so Material Symbols are used
        pix_fallback, _ = provider.requestPixmap("applications-other", QSize(64, 64))
        self.assertTrue(pix_fallback.isNull())

        ctrl = StoreController(mock_mode=True)
        self.assertFalse(ctrl.hasDesktopIcon("applications-multimedia"))
        self.assertFalse(ctrl.hasDesktopIcon("utilities-terminal"))
        self.assertFalse(ctrl.hasDesktopIcon(""))

        # Verify Theme.qml does not declare any `property color on<Upper>*` which collides with QML signal handlers
        theme_qml_text = (STORE_ROOT / "qml" / "theme" / "Theme.qml").read_text(encoding="utf-8")
        import re
        bad_props = re.findall(r"property\s+color\s+on[A-Z]\w*", theme_qml_text)
        self.assertEqual(
            bad_props,
            [],
            f"Theme.qml must not declare `property color on<Upper>*` (found {bad_props})",
        )

    def test_qml_headless_instantiation_and_navigation(self) -> None:
        app = get_qt_app()
        qml_file = STORE_ROOT / "qml" / "Main.qml"
        self.assertTrue(qml_file.is_file(), f"Main.qml not found at: {qml_file}")

        theme = ThemeService(parent=app)
        store = StoreController(parent=app, mock_mode=True)

        engine = QQmlApplicationEngine()
        engine.addImageProvider("xdgicon", XdgIconImageProvider())
        qml_dir = str(STORE_ROOT / "qml")
        engine.addImportPath(qml_dir)
        engine.addImportPath(os.path.join(qml_dir, "theme"))
        engine.addImportPath(os.path.join(qml_dir, "components"))
        engine.addImportPath(os.path.join(qml_dir, "pages"))

        ctx = engine.rootContext()
        ctx.setContextProperty("ThemeBridge", theme)
        ctx.setContextProperty("StoreBridge", store)
        ctx.setContextProperty("InitialPage", "home")

        engine.load(QUrl.fromLocalFile(str(qml_file)))
        app.processEvents()

        root_objects = engine.rootObjects()
        self.assertEqual(len(root_objects), 1, "Expected exactly 1 root ApplicationWindow")
        root_window = root_objects[0]
        self.assertEqual(root_window.property("title"), "Redshift Store")

        # Programmatic page navigation
        for page in ["catalog", "installed", "updates", "home"]:
            root_window.navigateToPage(page)
            app.processEvents()
            self.assertEqual(root_window.property("currentPage"), page)

        # Open Detail Modal
        root_window.openDetail("firefox", "official")
        app.processEvents()
        self.assertEqual(store.selectedPackage.get("name"), "firefox")

        # Verify OperationsLogDrawer AUR menu prompt detection (H-UI1)
        from PyQt6.QtCore import QObject
        log_drawer = root_window.findChild(QObject, "logDrawer")
        self.assertIsNotNone(log_drawer)
        store._tx_service.simulate_prompt_for_test("==> Diffs to show? ==> [N]one [A]ll [Ab]ort")
        app.processEvents()
        self.assertTrue(log_drawer.property("waitingForInput"))
        self.assertTrue(log_drawer.property("isAurMenuPrompt"))

        store._tx_service.simulate_prompt_for_test(":: Proceed with installation? [Y/n]")
        app.processEvents()
        self.assertTrue(log_drawer.property("waitingForInput"))
        self.assertFalse(log_drawer.property("isAurMenuPrompt"))

        # Theme preview toggle
        theme.togglePreviewMode()
        app.processEvents()

        del engine
        app.processEvents()


# =============================================================================
# 7. Testes de Regressão, Descoberta Real e Cenários A a G (Seções 9.3 e 12)
# =============================================================================
class TestRedshiftStoreScenariosAtoG(unittest.TestCase):
    """Validates real package discovery, update regressions, and mandatory Scenarios A to G."""

    @classmethod
    def setUpClass(cls) -> None:
        get_qt_app()

    def test_scenario_a_fresh_install_shows_wide_variety_of_uninstalled_apps(self) -> None:
        """Scenario A: Fresh install with minimal pacman local database still shows rich variety of uninstalled apps."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp = Path(tmp_dir)
            local_dir = tmp / "local"
            local_dir.mkdir(parents=True, exist_ok=True)

            # Minimal local pacman DB with only 3 core packages
            for pkg_name, pkg_ver in [("base", "3-1"), ("linux", "6.12.1-arch1"), ("pacman", "6.1.0-3")]:
                pkg_dir = local_dir / f"{pkg_name}-{pkg_ver}"
                pkg_dir.mkdir(parents=True, exist_ok=True)
                (pkg_dir / "desc").write_text(
                    f"%NAME%\n{pkg_name}\n\n%VERSION%\n{pkg_ver}\n\n%DESC%\nCore system package\n",
                    encoding="utf-8",
                )

            with patch.dict(os.environ, {"REDSHIFT_PACMAN_LOCAL_DIR": str(local_dir)}):
                cat = CatalogService(mock_mode=False)
                ctrl = StoreController(catalog_service=cat, mock_mode=False)

                # Installed packages should only reflect the 3 core packages
                installed = ctrl._catalog_service.get_installed_packages()
                installed_names = {p.name for p in installed}
                self.assertIn("base", installed_names)
                self.assertIn("linux", installed_names)
                self.assertIn("pacman", installed_names)
                self.assertLessEqual(len(installed), 5)

                # General catalog search must show dozens of available uninstalled applications
                res = ctrl._catalog_service.search_catalog(query="", source_filter="all", installed_filter="all")
                items = res.get("items", [])
                self.assertGreaterEqual(len(items), 20, "Catalog must show at least 20 items")
                uninstalled_count = sum(1 for p in items if not p.installed)
                self.assertGreater(uninstalled_count, 15, "Most catalog items must be uninstalled")

                # Home sections must show uninstalled applications
                sections = ctrl._catalog_service.get_home_sections()
                for sec_name in ("getting_started", "games", "development", "popular"):
                    sec_items = sections.get(sec_name, [])
                    self.assertGreater(len(sec_items), 0, f"Home section '{sec_name}' must not be empty")
                    self.assertTrue(
                        any(not p.installed for p in sec_items),
                        f"Home section '{sec_name}' must contain uninstalled apps",
                    )

    def test_scenario_b_search_uninstalled_official_app_returns_version_and_origin(self) -> None:
        """Scenario B: Searching uninstalled official app from sync db returns accurate version, origin, and metadata."""
        with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as tmp_dir:
            tmp = Path(tmp_dir)
            sync_dir = tmp / "sync"
            sync_dir.mkdir(parents=True, exist_ok=True)
            local_dir = tmp / "local"
            local_dir.mkdir(parents=True, exist_ok=True)
            cache_dir = tmp / "cache"
            cache_dir.mkdir(parents=True, exist_ok=True)

            # Create synthetic extra.db tar.gz archive
            extra_db_path = sync_dir / "extra.db"
            sample_pkgs = [
                ("0ad", "0.0.26-1", "A free, open-source real-time strategy game", "7654321", "1234567"),
                ("supertuxkart", "1.4-2", "A 3D open-source arcade racing game", "8765432", "2345678"),
                ("krita", "5.2.3-1", "Digital painting and illustration suite", "9876543", "3456789"),
                ("blender", "4.3.0-1", "A fully integrated 3D graphics creation suite", "12345678", "4567890"),
            ]
            with tarfile.open(extra_db_path, "w:gz") as tar:
                for pkg_name, pkg_ver, pkg_desc, isize, csize in sample_pkgs:
                    desc_body = (
                        f"%NAME%\n{pkg_name}\n\n"
                        f"%VERSION%\n{pkg_ver}\n\n"
                        f"%DESC%\n{pkg_desc}\n\n"
                        f"%CSIZE%\n{csize}\n\n"
                        f"%ISIZE%\n{isize}\n\n"
                        f"%LICENSE%\nGPL\n\n"
                        f"%URL%\nhttps://archlinux.org/packages/extra/x86_64/{pkg_name}\n\n"
                    ).encode("utf-8")
                    tinfo = tarfile.TarInfo(name=f"{pkg_name}-{pkg_ver}/desc")
                    tinfo.size = len(desc_body)
                    tinfo.mtime = int(time.time())
                    tar.addfile(tinfo, io.BytesIO(desc_body))

            with patch.dict(
                os.environ,
                {
                    "REDSHIFT_PACMAN_SYNC_DIR": str(sync_dir),
                    "REDSHIFT_PACMAN_LOCAL_DIR": str(local_dir),
                    "XDG_CACHE_HOME": str(cache_dir),
                },
            ):
                cat = CatalogService(mock_mode=False)
                cat.refresh_official_sync_db(force=True)

                ctrl = StoreController(catalog_service=cat)

                # 1. Search for 0ad
                res_0ad = cat.search_catalog("0ad")
                items_0ad = [p for p in res_0ad["items"] if p.name == "0ad"]
                self.assertEqual(len(items_0ad), 1)
                pkg_0ad = items_0ad[0]
                self.assertFalse(pkg_0ad.installed)
                self.assertEqual(pkg_0ad.source, "official")
                self.assertEqual(pkg_0ad.repository, "extra")
                self.assertEqual(pkg_0ad.version, "0.0.26-1")

                # Verify selectPackage on controller
                ctrl.selectPackage("0ad", "extra")
                sel = ctrl.selectedPackage
                self.assertEqual(sel.get("name"), "0ad")
                self.assertFalse(sel.get("installed"))
                self.assertEqual(sel.get("version"), "0.0.26-1")
                self.assertEqual(sel.get("repository"), "extra")
                self.assertEqual(sel.get("source"), "official")

                # 2. Search for supertuxkart
                ctrl.selectPackage("supertuxkart", "extra")
                sel_stk = ctrl.selectedPackage
                self.assertEqual(sel_stk.get("name"), "supertuxkart")
                self.assertFalse(sel_stk.get("installed"))
                self.assertEqual(sel_stk.get("version"), "1.4-2")
                self.assertEqual(sel_stk.get("repository"), "extra")

                # Ensure background indexing thread finishes before temporary cache cleanup
                cat.wait_for_sync_index(timeout=5.0)

    def test_scenario_c_category_games_without_query_shows_uninstalled_games(self) -> None:
        """Scenario C: Category 'games' without query returns uninstalled games and launchers."""
        ctrl = StoreController(mock_mode=True)
        self.assertEqual(ctrl.searchQuery, "")

        ctrl.setCategory("games")
        self.assertEqual(ctrl.activeCategory, "games")
        self.assertGreater(ctrl.catalogModel.count, 0)

        items = [ctrl.catalogModel.get_at(i) for i in range(ctrl.catalogModel.count)]
        item_names = {p.name for p in items}

        # Check known games in category
        expected_candidates = {"0ad", "supertuxkart", "lutris", "retroarch"}
        matching = item_names.intersection(expected_candidates)
        self.assertGreaterEqual(len(matching), 2, f"Expected games from {expected_candidates}, got {matching}")

        # Ensure terminal emulator kitty is NOT categorized as game
        self.assertNotIn("kitty", item_names, "Kitty terminal must NOT be categorized under games")

        # Ensure uninstalled games are present (not only installed packages)
        uninstalled_games = [p for p in items if not p.installed]
        self.assertGreater(len(uninstalled_games), 0, "Must display uninstalled games")
        self.assertTrue(all(p.category == "games" for p in items))

    def test_scenario_d_aur_discovery_without_query_shows_transparent_sections(self) -> None:
        """Scenario D: Source filter 'aur' without query activates AUR discovery models with transparent labels."""
        ctrl = StoreController(mock_mode=True)
        ctrl.setSourceFilter("aur")
        self.assertEqual(ctrl.activeSourceFilter, "aur")
        self.assertGreater(ctrl.catalogModel.count, 0)

        # 6 AUR discovery models
        aur_models = [
            ctrl.aurPopularModel,
            ctrl.aurCommunityModel,
            ctrl.aurDevModel,
            ctrl.aurGamesModel,
            ctrl.aurProductivityModel,
            ctrl.aurCuratedModel,
        ]

        for model in aur_models:
            self.assertGreater(model.count, 0, f"Model {model} must not be empty")
            for i in range(model.count):
                pkg = model.get_at(i)
                self.assertEqual(pkg.source, "aur")
                self.assertEqual(pkg.popularity_source, "aur_rpc")
                # Ensure 'downloads' is never used for Arch/AUR packages
                self.assertNotIn("download", pkg.popularity_label.lower())
                self.assertTrue(
                    any(term in pkg.popularity_label.lower() for term in ("voto", "popularidade", "pontos")),
                    f"Expected vote/popularity in popularity_label, got: {pkg.popularity_label!r}",
                )
                self.assertTrue(bool(pkg.provenance_label))
                self.assertTrue(pkg.provenance.startswith("aur"))

    def test_scenario_e_offline_network_error_uses_cache_and_reports_status(self) -> None:
        """Scenario E: Network failure falls back to local cache safely and reports network_error for uncached AUR queries."""
        with patch("urllib.request.urlopen", side_effect=urllib.error.URLError("Network unreachable")):
            cat = CatalogService(mock_mode=False)
            ctrl = StoreController(catalog_service=cat)

            # Cached/local operations must continue to work without exceptions
            featured = cat.get_featured_packages()
            self.assertIsInstance(featured, list)

            # Uncached exclusive AUR search must not raise, and must set catalog status to 'network_error'
            res = cat.search_catalog("unknown-uncached-aur-package-xyz", source_filter="aur")
            self.assertEqual(res.get("status"), "network_error")
            self.assertTrue(
                any(
                    term in (res.get("message", "") + res.get("status", "")).lower()
                    for term in ("conectar", "aur", "rede", "network_error")
                )
            )

            # Controller should reflect the catalog status
            ctrl.search("unknown-uncached-aur-package-xyz", source_filter="aur")
            self.assertEqual(ctrl.catalogStatus, "network_error")

    def test_scenario_f_36_official_updates_zero_aur_and_mixed_updates_and_anti_partial_upgrade(self) -> None:
        """Scenario F: 36 official updates, mixed updates, post-verification outcome, and anti-partial upgrade guard."""
        cat = CatalogService(mock_mode=True)
        ctrl = StoreController(catalog_service=cat, mock_mode=True)

        # 1. 36 Official updates & 0 AUR updates
        official_36 = [
            PackageItem(
                name=f"official-pkg-{i}",
                source="official",
                repository="extra",
                version="2.0.0-1",
                installed_version="1.0.0-1",
                update_available=True,
            )
            for i in range(36)
        ]
        cat.check_updates = lambda: list(official_36)
        ctrl.checkUpdates()
        self.assertEqual(ctrl.updatesCount, 36)
        self.assertTrue(all(p.source == "official" for p in ctrl.updatesModel.items))

        # Test updateAll() triggers transaction
        with patch.object(ctrl._tx_service, "update_all") as mock_update_all:
            ctrl.updateAll()
            mock_update_all.assert_called_once()
            self.assertEqual(ctrl._pre_tx_updates_count, 36)

        # Post-verification: Complete update (0 remaining)
        cat.check_updates = lambda: []
        ctrl._on_tx_finished(True, "update_all", "Update complete")
        self.assertEqual(ctrl.lastUpdateOutcome, "complete")
        self.assertEqual(ctrl.updatesCount, 0)

        # Post-verification: Partial update (5 remaining)
        ctrl._pre_tx_updates_count = 36
        cat.check_updates = lambda: list(official_36[:5])
        ctrl._on_tx_finished(True, "update_all", "Partial")
        self.assertEqual(ctrl.lastUpdateOutcome, "partial")
        self.assertEqual(ctrl.updatesCount, 5)

        # 2. Mixed updates scenario (30 official + 6 AUR)
        mixed = list(official_36[:30]) + [
            PackageItem(
                name=f"aur-pkg-{i}",
                source="aur",
                repository="aur",
                version="3.0.0-1",
                installed_version="2.0.0-1",
                update_available=True,
            )
            for i in range(6)
        ]
        cat.check_updates = lambda: list(mixed)
        ctrl.checkUpdates()
        self.assertEqual(ctrl.updatesCount, 36)
        official_cnt = sum(1 for p in ctrl.updatesModel.items if p.source == "official")
        aur_cnt = sum(1 for p in ctrl.updatesModel.items if p.source == "aur")
        self.assertEqual(official_cnt, 30)
        self.assertEqual(aur_cnt, 6)

        # 3. Anti-partial upgrade guard for individual official package vs AUR package
        toasts: list[tuple[str, str]] = []
        ctrl.toastMessage.connect(lambda level, msg: toasts.append((level, msg)))

        with patch.object(ctrl, "updateAll") as mock_ctrl_update_all, patch.object(
            ctrl._tx_service, "update_package"
        ) as mock_tx_update_pkg:
            # Official package must redirect to updateAll with safety notification
            ctrl.updatePackage("firefox", "extra")
            mock_ctrl_update_all.assert_called_once()
            mock_tx_update_pkg.assert_not_called()
            self.assertTrue(
                any("Arch Linux" in t[1] and ("parcial" in t[1].lower() or "completa" in t[1].lower()) for t in toasts)
            )

            # AUR package updates safely via update_package
            mock_ctrl_update_all.reset_mock()
            ctrl.updatePackage("visual-studio-code-bin", "aur")
            mock_ctrl_update_all.assert_not_called()
            mock_tx_update_pkg.assert_called_once_with("visual-studio-code-bin", "aur")

    def test_scenario_g_live_wallpaper_material_you_palette_update(self) -> None:
        """Scenario G: Live wallpaper change and Matugen palette generation updates M3 tokens reactively without restart."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp = Path(tmp_dir)
            colors_path = tmp / "colors.json"
            wall_path = tmp / "wallpaper.txt"

            initial_colors = {
                "background": "#141318",
                "surface": "#141318",
                "surface_container_low": "#1c1b20",
                "surface_container": "#201f25",
                "surface_container_high": "#2b292f",
                "surface_container_highest": "#36343a",
                "primary": "#c9bfff",
            }
            colors_path.write_text(json.dumps(initial_colors), encoding="utf-8")
            wall_path.write_text("/usr/share/backgrounds/initial.png", encoding="utf-8")

            with patch.dict(
                os.environ,
                {
                    "REDSHIFT_COLORS_JSON_PATH": str(colors_path),
                    "REDSHIFT_CAELESTIA_SCHEME_PATH": str(tmp / "scheme.json"),
                    "REDSHIFT_UI_SWITCH_STATE_PATH": str(tmp / "ui-switch"),
                    "REDSHIFT_WALLPAPER_PATH_FILE": str(wall_path),
                    "REDSHIFT_APPLIED_SCHEME_TYPE_PATH": str(tmp / "applied_scheme_type.txt"),
                },
            ):
                theme = ThemeService()
                ctrl = StoreController(mock_mode=True)

                palette_signals: list[int] = []
                theme.paletteChanged.connect(lambda: palette_signals.append(1))

                self.assertTrue(theme.isDark)
                self.assertEqual(theme.colors["primary"].lower(), "#c9bfff")

                # Simulate wallpaper change and matugen new palette generation
                new_wallpaper_palette = {
                    "background": "#0b1510",
                    "surface": "#0b1510",
                    "surface_container_low": "#131d18",
                    "surface_container": "#17211c",
                    "surface_container_high": "#212c26",
                    "surface_container_highest": "#2c3731",
                    "primary": "#8cd7ad",
                }
                wall_path.write_text("/usr/share/backgrounds/nature-forest.jpg", encoding="utf-8")
                colors_path.write_text(json.dumps(new_wallpaper_palette), encoding="utf-8")

                # Force reloadTheme or wait debounce
                theme.reloadTheme()

                self.assertGreater(len(palette_signals), 0, "paletteChanged signal must be emitted")
                self.assertEqual(theme.wallpaperPath, "/usr/share/backgrounds/nature-forest.jpg")
                self.assertEqual(theme.colors["surfaceContainerLow"].lower(), "#131d18")
                self.assertEqual(theme.colors["surfaceContainer"].lower(), "#17211c")
                self.assertEqual(theme.colors["surfaceContainerHigh"].lower(), "#212c26")
                self.assertEqual(theme.colors["surfaceContainerHighest"].lower(), "#2c3731")
                self.assertEqual(theme.colors["primary"].lower(), "#8cd7ad")
                self.assertTrue(theme.isDark)

    def test_privacy_personalization_controls(self) -> None:
        """Verify local browsing signals generate transparent personalized recommendations and user controls respect privacy."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp = Path(tmp_dir)
            with patch.dict(os.environ, {"XDG_STATE_HOME": str(tmp / "state")}):
                ctrl = StoreController(mock_mode=True)
                self.assertTrue(ctrl.personalizationEnabled)

                # 1. Generate local user engagement history
                ctrl.setCategory("games")
                ctrl.search("blender")
                ctrl.selectPackage("blender", "official")
                ctrl.toggleFavorite("krita")

                self.assertTrue(ctrl.hasPersonalizationHistory)
                self.assertGreaterEqual(ctrl.favoritesCount, 1)

                # 2. Check recommendations section
                ctrl.refreshHomeSections()
                rec_items = [ctrl.recommendedModel.get_at(i) for i in range(ctrl.recommendedModel.count)]
                self.assertGreater(len(rec_items), 0, "Personalized recommendations must not be empty")

                # Verify provenance and clear user-facing justification
                has_personalized = any(p.provenance == "personalized" for p in rec_items)
                self.assertTrue(has_personalized, "Must contain items with provenance='personalized'")
                for p in rec_items:
                    if p.provenance == "personalized":
                        self.assertTrue(
                            any(
                                pattern in p.provenance_label
                                for pattern in ("Relacionado", "Baseado", "Semelhante", "pesquisa", "favoritou", "visualizados")
                            ),
                            f"Justification label missing or unclear: {p.provenance_label!r}",
                        )

                # 3. Disable personalization
                ctrl.setPersonalizationEnabled(False)
                self.assertFalse(ctrl.personalizationEnabled)
                ctrl.refreshHomeSections()
                rec_disabled = [ctrl.recommendedModel.get_at(i) for i in range(ctrl.recommendedModel.count)]
                # Under disabled personalization, items revert to editorial/curated provenance
                self.assertTrue(all(p.provenance != "personalized" for p in rec_disabled))

                # 4. Clear personalization history
                ctrl.clearPersonalizationHistory()
                # Verify browsing and search history is wiped
                prefs = ctrl._catalog_service._user_prefs
                self.assertEqual(prefs.get("visited_categories"), {})
                self.assertEqual(prefs.get("search_terms"), [])
                self.assertEqual(prefs.get("viewed_packages"), [])

                # Untoggle favorite to clear user preferences completely
                ctrl.toggleFavorite("krita")
                self.assertFalse(ctrl.hasPersonalizationHistory)


# =============================================================================
# 8. Testes de Diagnóstico de Manutenção e Banner QML (TestRedshiftMaintenanceIntegration)
# =============================================================================
class TestRedshiftMaintenanceIntegration(unittest.TestCase):
    """Validates MaintenanceService health diagnosis, repair routines, and QML integration."""

    @classmethod
    def setUpClass(cls) -> None:
        get_qt_app()

    def test_maintenance_service_diagnosis_and_environmental_overrides(self) -> None:
        """Verify mock diagnostic behavior and environmental override controls."""
        service = MaintenanceService(mock_mode=True)
        service.check_health(async_mode=False)
        self.assertFalse(service.maintenance_required)
        self.assertEqual(service.maintenance_title, "")

        # Forced maintenance via environment variables
        with patch.dict(
            os.environ,
            {
                "REDSHIFT_MAINTENANCE_REQUIRED": "1",
                "REDSHIFT_MAINTENANCE_TITLE": "Falha Caelestia Teste",
                "REDSHIFT_MAINTENANCE_MESSAGE": "Mensagem de reparo teste.",
                "REDSHIFT_MAINTENANCE_CAUSE": "Causa apurada no teste unitário.",
            },
        ):
            service.check_health(async_mode=False)
            self.assertTrue(service.maintenance_required)
            self.assertEqual(service.maintenance_title, "Falha Caelestia Teste")
            self.assertEqual(service.maintenance_message, "Mensagem de reparo teste.")
            self.assertEqual(service.maintenance_cause, "Causa apurada no teste unitário.")

    def test_maintenance_service_native_checks(self) -> None:
        """Verify native Level 1 (missing plugin) and Level 2 (linker failure) detection."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp = Path(tmp_dir)
            fake_home = tmp / "home"
            fake_home.mkdir()
            cael_cfg = fake_home / ".config" / "quickshell" / "caelestia-hybrid"
            cael_cfg.mkdir(parents=True)

            with patch("pathlib.Path.home", return_value=fake_home), patch.dict(
                os.environ, {"CAELESTIA_QML_PATH": str(tmp / "empty_qml")}, clear=False
            ):
                # 1. Level 1: Caelestia plugin missing
                service = MaintenanceService(mock_mode=False)
                service.check_health(async_mode=False)
                self.assertTrue(service.maintenance_required)
                self.assertIn("Instalação incompleta ou ausente: plugin nativo Caelestia não encontrado", service.maintenance_cause)
                self.assertIn("redshift-doctor --check caelestia", service.maintenance_cause)

                # 2. Level 2: Plugin exists but ldd detects unresolved symbol
                qml_dir = tmp / "fake_qml"
                cael_dir = qml_dir / "Caelestia"
                cael_dir.mkdir(parents=True)
                (cael_dir / "qmldir").write_text("module Caelestia\n", encoding="utf-8")
                so_file = cael_dir / "libcaelestia-coreplugin.so"
                so_file.write_text("dummy binary", encoding="utf-8")

                with patch.dict(os.environ, {"CAELESTIA_QML_PATH": str(qml_dir)}):
                    def fake_which(cmd: str):
                        return "/usr/bin/ldd" if cmd == "ldd" else None

                    with patch("shutil.which", side_effect=fake_which), patch(
                        "subprocess.run"
                    ) as mock_subproc:
                        mock_subproc.return_value.returncode = 0
                        mock_subproc.return_value.stdout = "undefined symbol: _ZN10QByteArray..."
                        mock_subproc.return_value.stderr = ""

                        service.check_health(async_mode=False)
                        self.assertTrue(service.maintenance_required)
                        self.assertIn("Incompatibilidade detectada entre Caelestia e Qt6/Quickshell", service.maintenance_cause)
                        self.assertIn("redshift-doctor --repair caelestia", service.maintenance_cause)

    def test_store_controller_maintenance_properties_and_actions(self) -> None:
        """Verify StoreController facade exposes maintenance signals, properties, and repair slots."""
        app = get_qt_app()
        with patch.dict(
            os.environ,
            {
                "REDSHIFT_MAINTENANCE_REQUIRED": "1",
                "REDSHIFT_MAINTENANCE_TITLE": "Reparo Necessário",
                "REDSHIFT_MAINTENANCE_MESSAGE": "Frontend indisponível.",
                "REDSHIFT_MAINTENANCE_CAUSE": "Causa detectada.",
            },
        ):
            ctrl = StoreController(mock_mode=True)
            self.assertTrue(ctrl.maintenanceRequired)
            self.assertEqual(ctrl.maintenanceTitle, "Reparo Necessário")
            self.assertEqual(ctrl.maintenanceMessage, "Frontend indisponível.")
            self.assertEqual(ctrl.maintenanceCause, "Causa detectada.")
            self.assertFalse(ctrl.isRepairing)

            # Test repairComponent slot
            with patch.dict(os.environ, {"REDSHIFT_MAINTENANCE_REQUIRED": "0"}):
                ctrl.repairComponent("caelestia")
                t0 = time.time()
                while ctrl.isRepairing and (time.time() - t0) < 3.0:
                    app.processEvents()
                    time.sleep(0.01)

                self.assertFalse(ctrl.isRepairing)

    def test_qml_maintenance_banner_and_dialog_interaction(self) -> None:
        """Verify headless instantiation of MaintenanceBanner and MaintenanceDetailDialog in Main.qml."""
        app = get_qt_app()
        qml_file = STORE_ROOT / "qml" / "Main.qml"

        with patch.dict(
            os.environ,
            {
                "REDSHIFT_MAINTENANCE_REQUIRED": "1",
                "REDSHIFT_MAINTENANCE_TITLE": "Caelestia Indisponível",
                "REDSHIFT_MAINTENANCE_MESSAGE": "Um componente do Redshift OS precisa de reparo após a atualização. O frontend Caelestia está temporariamente indisponível.",
                "REDSHIFT_MAINTENANCE_CAUSE": "Incompatibilidade detectada entre Caelestia e Qt6/Quickshell. Execute 'redshift-doctor --repair caelestia'.",
            },
        ):
            theme = ThemeService(parent=app)
            store = StoreController(parent=app, mock_mode=True)

            engine = QQmlApplicationEngine()
            engine.addImageProvider("xdgicon", XdgIconImageProvider())
            qml_dir = str(STORE_ROOT / "qml")
            engine.addImportPath(qml_dir)
            engine.addImportPath(os.path.join(qml_dir, "theme"))
            engine.addImportPath(os.path.join(qml_dir, "components"))
            engine.addImportPath(os.path.join(qml_dir, "pages"))

            ctx = engine.rootContext()
            ctx.setContextProperty("ThemeBridge", theme)
            ctx.setContextProperty("StoreBridge", store)
            ctx.setContextProperty("InitialPage", "home")

            engine.load(QUrl.fromLocalFile(str(qml_file)))
            app.processEvents()

            root_objects = engine.rootObjects()
            self.assertEqual(len(root_objects), 1)
            root_window = root_objects[0]

            from PyQt6.QtCore import QObject
            banner = root_window.findChild(QObject, "maintenanceBanner")
            self.assertIsNotNone(banner, "MaintenanceBanner must be present in Main.qml")
            self.assertTrue(banner.property("visible"))
            self.assertEqual(banner.property("bannerTitle"), "Caelestia Indisponível")
            self.assertIn("frontend Caelestia está temporariamente indisponível", banner.property("bannerMessage"))

            dialog = root_window.findChild(QObject, "maintenanceDialog")
            self.assertIsNotNone(dialog, "MaintenanceDetailDialog must be present in Main.qml")
            self.assertFalse(dialog.property("isOpen"))

            # Trigger "Ver detalhes" click from banner
            banner.viewDetailsClicked.emit()
            app.processEvents()
            self.assertTrue(dialog.property("isOpen"))
            self.assertEqual(dialog.property("causeText"), store.maintenanceCause)
            self.assertIn("redshift-doctor --repair caelestia", dialog.property("causeText"))

            del engine
            app.processEvents()


if __name__ == "__main__":
    unittest.main()
