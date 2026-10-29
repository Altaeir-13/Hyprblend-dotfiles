"""StoreController QObject facade exposing StoreBridge to QML.

Complies 100% with REDSHIFT_STORE_ARCHITECTURE.md Section 3.2 schema.
Bridges reactive PackageListModel instances, catalog discovery, async
transaction execution, log streaming, and system pacman state.
"""

from __future__ import annotations

import logging
import os
import threading
from typing import Any

from PyQt6.QtCore import QObject, pyqtProperty, pyqtSignal, pyqtSlot
from PyQt6.QtGui import QIcon

from .catalog_service import CatalogService
from .models import PackageItem, PackageListModel
from .transaction_service import TransactionService

logger = logging.getLogger("redshift_store.controller")

_GENERIC_ICON_TOKENS = frozenset({
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
    "utilities-terminal",
    "utilities-system-monitor",
})

_COMMON_ICON_ALIASES: dict[str, tuple[str, ...]] = {
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

_ICON_SEARCH_DIRS = (
    "/usr/share/icons/hicolor/scalable/apps",
    "/usr/share/icons/hicolor/256x256/apps",
    "/usr/share/icons/hicolor/128x128/apps",
    "/usr/share/icons/hicolor/64x64/apps",
    "/usr/share/icons/hicolor/48x48/apps",
    "/usr/share/pixmaps",
)


class StoreController(QObject):
    """Facade QObject registered in QML context as 'StoreBridge'."""

    # -------------------------------------------------------------------------
    # Signals (Section 3.2)
    # -------------------------------------------------------------------------
    catalogChanged = pyqtSignal()
    installedChanged = pyqtSignal()
    updatesChanged = pyqtSignal()
    selectedPackageChanged = pyqtSignal()
    operationStateChanged = pyqtSignal()
    operationProgressChanged = pyqtSignal()
    logsChanged = pyqtSignal()
    logLineReceived = pyqtSignal(str)
    lockStatusChanged = pyqtSignal()
    filterChanged = pyqtSignal()
    pkgbuildPreviewChanged = pyqtSignal()
    promptChanged = pyqtSignal()
    toastMessage = pyqtSignal(str, str)  # (level: "info"|"success"|"warning"|"error", message: str)
    _updatesLoaded = pyqtSignal(list)

    def __init__(
        self,
        parent: QObject | None = None,
        catalog_service: CatalogService | None = None,
        transaction_service: TransactionService | None = None,
        mock_mode: bool | None = None,
    ) -> None:
        super().__init__(parent)

        self._catalog_service = catalog_service or CatalogService(mock_mode=mock_mode)
        self._tx_service = transaction_service or TransactionService(parent=self, mock_mode=mock_mode)

        # Reactive List Models for QML views
        self._catalog_model = PackageListModel(self)
        self._featured_model = PackageListModel(self)
        self._installed_model = PackageListModel(self)
        self._updates_model = PackageListModel(self)

        # Internal State
        self._selected_package: dict[str, Any] = PackageItem().to_dict()
        self._search_query: str = ""
        self._active_category: str = "all"
        self._active_source_filter: str = "all"
        self._log_text: str = ""
        self._pkgbuild_preview: str = ""
        self._checking_updates: bool = False

        # Connect internal update signals
        self._updatesLoaded.connect(self._on_updates_loaded)

        # Connect TransactionService signals
        self._tx_service.stateChanged.connect(self._on_tx_state_changed)
        self._tx_service.progressChanged.connect(self._on_tx_progress_changed)
        self._tx_service.logLineReceived.connect(self._on_tx_log_line)
        self._tx_service.lockStatusChanged.connect(self._on_lock_changed)
        self._tx_service.stageChanged.connect(self.operationStateChanged)
        self._tx_service.promptChanged.connect(self.promptChanged)
        self._tx_service.cancellationBlocked.connect(lambda msg: self.toastMessage.emit("warning", msg))
        self._tx_service.transactionFinished.connect(self._on_tx_finished)

        # Initial data population
        self._init_data()

    def _init_data(self) -> None:
        """Populate initial models with featured and installed packages."""
        self.refreshCatalog()
        self.refreshInstalled()
        self.checkUpdates()

    # -------------------------------------------------------------------------
    # Properties (Section 3.2)
    # -------------------------------------------------------------------------

    @pyqtProperty(QObject, constant=True)
    def catalogModel(self) -> PackageListModel:
        """Model for search and catalog exploration."""
        return self._catalog_model

    @pyqtProperty(QObject, constant=True)
    def featuredModel(self) -> PackageListModel:
        """Model for home page featured packages."""
        return self._featured_model

    @pyqtProperty(QObject, constant=True)
    def installedModel(self) -> PackageListModel:
        """Model for installed application library."""
        return self._installed_model

    @pyqtProperty(QObject, constant=True)
    def updatesModel(self) -> PackageListModel:
        """Model for pending updates."""
        return self._updates_model

    @pyqtProperty("QVariantMap", notify=selectedPackageChanged)
    def selectedPackage(self) -> dict[str, Any]:
        """Dictionary representation of currently inspected package."""
        return dict(self._selected_package)

    @pyqtProperty(str, notify=operationStateChanged)
    def operationState(self) -> str:
        """Current package manager operation state."""
        return self._tx_service.state

    @pyqtProperty(str, notify=operationStateChanged)
    def operationStatusText(self) -> str:
        """Human-readable description of active operation."""
        return self._tx_service.status_text

    @pyqtProperty(int, notify=operationProgressChanged)
    def operationProgress(self) -> int:
        """Current operation progress percentage (0..100 or -1)."""
        return self._tx_service.progress

    @pyqtProperty(bool, notify=operationStateChanged)
    def isBusy(self) -> bool:
        """True if an operation is currently in progress."""
        return self._tx_service.is_busy

    @pyqtProperty(bool, notify=lockStatusChanged)
    def isDbLocked(self) -> bool:
        """True if pacman database lock file exists."""
        return self._tx_service.is_locked

    @pyqtProperty(int, notify=installedChanged)
    def installedCount(self) -> int:
        """Total number of installed packages."""
        return self._installed_model.count

    @pyqtProperty(int, notify=updatesChanged)
    def updatesCount(self) -> int:
        """Total number of pending updates."""
        return self._updates_model.count

    @pyqtProperty(str, notify=logsChanged)
    def logText(self) -> str:
        """Consolidated output log text buffer."""
        return self._log_text

    @pyqtProperty(str, notify=filterChanged)
    def activeCategory(self) -> str:
        """Currently active category filter."""
        return self._active_category

    @pyqtProperty(str, notify=filterChanged)
    def activeSourceFilter(self) -> str:
        """Currently active source filter ('all'|'official'|'aur')."""
        return self._active_source_filter

    @pyqtProperty(str, notify=filterChanged)
    def searchQuery(self) -> str:
        """Current search query string."""
        return self._search_query

    @pyqtProperty(str, notify=pkgbuildPreviewChanged)
    def pkgbuildPreview(self) -> str:
        """Preview content of fetched AUR PKGBUILD script."""
        return self._pkgbuild_preview

    @pyqtProperty(bool, notify=operationStateChanged)
    def canCancel(self) -> bool:
        """True if the active transaction can be cancelled without database corruption."""
        return self._tx_service.can_cancel

    @pyqtProperty(str, notify=operationStateChanged)
    def transactionStage(self) -> str:
        """Fine-grained operation stage ('downloading', 'compiling', 'committing', etc.)."""
        return self._tx_service.stage

    @pyqtProperty(bool, notify=promptChanged)
    def waitingForInput(self) -> bool:
        """True if the transaction is paused awaiting user confirmation."""
        return self._tx_service.waiting_for_input

    @pyqtProperty(str, notify=promptChanged)
    def currentPromptText(self) -> str:
        """Interactive prompt question text from pacman/yay."""
        return self._tx_service.current_prompt_text

    # -------------------------------------------------------------------------
    # Public Slots (Section 3.2)
    # -------------------------------------------------------------------------

    @pyqtSlot(str, str, str)
    def search(self, query: str, source_filter: str = "all", category_filter: str = "all") -> None:
        """Execute debounced search query across catalog with source and category filters."""
        self._search_query = query.strip()
        self._active_source_filter = source_filter or "all"
        self._active_category = category_filter or "all"
        self.filterChanged.emit()

        results = self._catalog_service.search(
            query=self._search_query,
            source_filter=self._active_source_filter,
            category_filter=self._active_category,
        )
        self._catalog_model.set_items(results)
        self.catalogChanged.emit()

    @pyqtSlot(str)
    def setCategory(self, category: str) -> None:
        """Filter catalog by canonical category name."""
        cat = category or "all"
        if self._active_category != cat:
            self._active_category = cat
            self.filterChanged.emit()
            self.search(self._search_query, self._active_source_filter, self._active_category)

    @pyqtSlot(str)
    def setSourceFilter(self, source_filter: str) -> None:
        """Filter catalog by package origin ('all'|'official'|'aur')."""
        src = source_filter or "all"
        if self._active_source_filter != src:
            self._active_source_filter = src
            self.filterChanged.emit()
            self.search(self._search_query, self._active_source_filter, self._active_category)

    @pyqtSlot(str, str)
    def selectPackage(self, pkg_name: str, repository: str = "") -> None:
        """Select a package to populate the PackageDetailModal view."""
        if not pkg_name:
            self._selected_package = {}
            self.selectedPackageChanged.emit()
            return

        item = self._catalog_service.get_package(pkg_name, repository)
        if item:
            self._selected_package = item.to_dict()
        else:
            # Fallback dictionary if not in cache
            self._selected_package = {
                "name": pkg_name,
                "displayName": pkg_name,
                "repository": repository or "official",
                "source": "aur" if repository == "aur" else "official",
                "installed": False,
                "updateAvailable": False,
                "isProtected": False,
            }
        self.selectedPackageChanged.emit()

        # If it's an AUR package, automatically fetch PKGBUILD preview
        if self._selected_package.get("source") == "aur":
            self.fetchPkgbuildPreview(pkg_name)
        else:
            self._pkgbuild_preview = ""
            self.pkgbuildPreviewChanged.emit()

    @pyqtSlot()
    def refreshCatalog(self) -> None:
        """Reload featured home packages and default catalog."""
        featured = self._catalog_service.get_featured_packages()
        self._featured_model.set_items(featured)
        if not self._search_query:
            self._catalog_model.set_items(featured)
            self.catalogChanged.emit()

    @pyqtSlot()
    @pyqtSlot(bool)
    def refreshInstalled(self, explicit_only: bool = False) -> None:
        """Reload installed packages list from pacman database."""
        self._catalog_service.refresh_installed()
        installed_list = self._catalog_service.get_installed_packages(explicit_only=explicit_only)
        self._installed_model.set_items(installed_list)
        self.installedChanged.emit()

    @pyqtSlot()
    def checkUpdates(self) -> None:
        """Scan for system updates via checkupdates and yay asynchronously."""
        if self._catalog_service.mock_mode:
            updates = self._catalog_service.check_updates()
            self._on_updates_loaded(updates)
            return

        if self._checking_updates:
            return

        self._checking_updates = True

        def _worker() -> None:
            try:
                res = self._catalog_service.check_updates()
            except Exception as e:
                logger.warning("Error checking updates in background thread: %s", e)
                res = []
            self._updatesLoaded.emit(res)

        t = threading.Thread(target=_worker, daemon=True)
        t.start()

    @pyqtSlot(str, str)
    def installPackage(self, pkg_name: str, repository: str = "official") -> None:
        """Initiate asynchronous package installation."""
        clean_name = pkg_name.strip()
        if not clean_name:
            self.toastMessage.emit("error", "Nome de pacote inválido.")
            return
        self._tx_service.install_package(clean_name, repository)

    @pyqtSlot(str)
    def removePackage(self, pkg_name: str) -> None:
        """Initiate asynchronous package removal."""
        clean_name = pkg_name.strip()
        if not clean_name:
            self.toastMessage.emit("error", "Nome de pacote inválido.")
            return
        self._tx_service.remove_package(clean_name)

    @pyqtSlot(str, str)
    def updatePackage(self, pkg_name: str, repository: str = "official") -> None:
        """Initiate single package update."""
        clean_name = pkg_name.strip()
        if not clean_name:
            self.toastMessage.emit("error", "Nome de pacote inválido.")
            return
        self._tx_service.update_package(clean_name, repository)

    @pyqtSlot()
    def updateAll(self) -> None:
        """Initiate full system upgrade."""
        self._tx_service.update_all()

    @pyqtSlot()
    def cancelCurrentOperation(self) -> None:
        """Cancel ongoing package manager operation."""
        self._tx_service.cancel()

    @pyqtSlot(bool, result=bool)
    def respondToPrompt(self, accept: bool) -> bool:
        """Respond to interactive package manager confirmation prompt with y/n."""
        return self._tx_service.respond_to_prompt(accept)

    @pyqtSlot(str, result=bool)
    def sendTransactionInput(self, text: str) -> bool:
        """Send arbitrary text input to ongoing transaction process."""
        return self._tx_service.send_input(text)

    @pyqtSlot(str, result=bool)
    def sendInput(self, text: str) -> bool:
        """Alias for sendTransactionInput for direct QML compatibility."""
        return self.sendTransactionInput(text)

    @pyqtSlot()
    def clearLogs(self) -> None:
        """Clear output log buffer."""
        self._log_text = ""
        self.logsChanged.emit()

    @pyqtSlot(str)
    def fetchPkgbuildPreview(self, pkg_name: str) -> None:
        """Fetch PKGBUILD content for AUR package inspection."""
        clean_name = pkg_name.strip()
        if not clean_name:
            return
        preview = self._catalog_service.fetch_aur_pkgbuild(clean_name)
        self._pkgbuild_preview = preview
        self.pkgbuildPreviewChanged.emit()

    @pyqtSlot(str, result=bool)
    def hasDesktopIcon(self, icon_name: str) -> bool:
        """Return True only if icon_name resolves to a real desktop icon on disk or in theme."""
        clean = (icon_name or "").split("?")[0].strip()
        if not clean or clean in _GENERIC_ICON_TOKENS or clean.startswith("applications-") or clean.startswith("utilities-"):
            return False
        if not hasattr(self, "_icon_availability_cache"):
            self._icon_availability_cache: dict[str, bool] = {}
        if clean in self._icon_availability_cache:
            return self._icon_availability_cache[clean]

        if clean.startswith("/") and os.path.isfile(clean):
            self._icon_availability_cache[clean] = True
            return True

        candidates = [clean]
        if clean in _COMMON_ICON_ALIASES:
            candidates.extend(_COMMON_ICON_ALIASES[clean])

        found = False
        for cand in candidates:
            if QIcon.hasThemeIcon(cand):
                found = True
                break
            for sdir in _ICON_SEARCH_DIRS:
                if any(os.path.isfile(os.path.join(sdir, f"{cand}{ext}")) for ext in (".svg", ".png", ".xpm")):
                    found = True
                    break
            if found:
                break

        self._icon_availability_cache[clean] = found
        return found

    # -------------------------------------------------------------------------
    # Internal Signal Handlers
    # -------------------------------------------------------------------------

    def _on_updates_loaded(self, updates: list) -> None:
        """Apply updates list on the main Qt thread."""
        self._checking_updates = False
        self._updates_model.set_items(updates)
        self.updatesChanged.emit()

    def _on_tx_state_changed(self, state: str, status_text: str) -> None:
        """Relay transaction state changes to QML."""
        self.operationStateChanged.emit()

    def _on_tx_progress_changed(self, progress: int) -> None:
        """Relay transaction progress changes to QML."""
        self.operationProgressChanged.emit()

    def _on_tx_log_line(self, line: str) -> None:
        """Append log line to buffer and relay signal."""
        self._log_text += line + "\n"
        self.logsChanged.emit()
        self.logLineReceived.emit(line)

    def _on_lock_changed(self, is_locked: bool) -> None:
        """Relay lock status changes to QML."""
        self.lockStatusChanged.emit()

    def _on_tx_finished(self, success: bool, action: str, message: str) -> None:
        """Handle transaction completion: notify user and refresh models."""
        level = "success" if success else "error"
        self.toastMessage.emit(level, message)

        if success:
            # Refresh local models automatically
            self.refreshInstalled()
            self.refreshCatalog()
            self.checkUpdates()

            # Refresh selected package details if one was open
            selected_name = self._selected_package.get("name")
            if selected_name:
                repo = self._selected_package.get("repository", "")
                self.selectPackage(selected_name, repo)
