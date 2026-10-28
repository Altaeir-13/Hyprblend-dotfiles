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

import json
import os
import sys
import tempfile
import time
import unittest
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

            # 5. Yay sysupgrade (H-BACK1: --cleanmenu and --diffmenu preserved)
            cmd_yay_sys = build_safe_yay_sysupgrade_cmd()
            self.assertEqual(cmd_yay_sys[0], "/usr/bin/yay")
            self.assertIn("-Sua", cmd_yay_sys)
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

        # Validate 24 role names mapping
        roles = model.roleNames()
        self.assertEqual(len(roles), 24)
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


if __name__ == "__main__":
    unittest.main()
