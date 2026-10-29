"""StoreController QObject facade exposing StoreBridge to QML.

Complies 100% with REDSHIFT_STORE_ARCHITECTURE.md Section 3.2 schema and TASK-B2.
Bridges reactive PackageListModel instances, rich catalog discovery, Home sections,
AUR discovery models, pagination, privacy-respecting personalization, async
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
    "applications-graphics",
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
    "krita": ("org.kde.krita",),
    "blender": ("blender",),
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
    # Signals (Section 3.2 & TASK-B2)
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
    personalizationChanged = pyqtSignal()
    toastMessage = pyqtSignal(str, str)  # (level: "info"|"success"|"warning"|"error", message: str)
    _updatesLoaded = pyqtSignal(list)
    _indexReady = pyqtSignal()

    def __init__(
        self,
        parent: QObject | None = None,
        catalog_service: CatalogService | None = None,
        transaction_service: TransactionService | None = None,
        mock_mode: bool | None = None,
    ) -> None:
        super().__init__(parent)

        # Service instances
        self._catalog_service = catalog_service or CatalogService(
            mock_mode=mock_mode,
            on_index_ready=lambda: self._indexReady.emit(),
        )
        self._tx_service = transaction_service or TransactionService(parent=self, mock_mode=mock_mode)

        # Core Reactive List Models for QML
        self._catalog_model = PackageListModel(self)
        self._featured_model = PackageListModel(self)
        self._installed_model = PackageListModel(self)
        self._updates_model = PackageListModel(self)

        # Home Page Section Models (TASK-B2)
        self._recommended_model = PackageListModel(self)
        self._popular_community_model = PackageListModel(self)
        self._getting_started_model = PackageListModel(self)
        self._development_section_model = PackageListModel(self)
        self._games_section_model = PackageListModel(self)
        self._design_section_model = PackageListModel(self)
        self._communication_section_model = PackageListModel(self)

        # AUR Discovery Models (TASK-B2)
        self._aur_popular_model = PackageListModel(self)
        self._aur_community_model = PackageListModel(self)
        self._aur_dev_model = PackageListModel(self)
        self._aur_games_model = PackageListModel(self)
        self._aur_productivity_model = PackageListModel(self)
        self._aur_curated_model = PackageListModel(self)

        # Internal State & Filters
        self._selected_package: dict[str, Any] = PackageItem().to_dict()
        self._search_query: str = ""
        self._active_category: str = "all"
        self._active_source_filter: str = "all"
        self._active_installed_filter: str = "all"  # "all" | "installed" | "not_installed"
        self._active_sort_by: str = "relevance"  # "relevance" | "popularity" | "name" | "recent"
        self._include_system_packages: bool = False

        # Pagination & Catalog Status
        self._catalog_offset: int = 0
        self._catalog_page_size: int = 40
        self._catalog_total_count: int = 0
        self._can_load_more_catalog: bool = False
        self._catalog_status: str = "ready"
        self._catalog_status_message: str = ""

        # Update Outcomes
        self._last_update_outcome: str = ""  # "" | "complete" | "partial" | "cancelled" | "failed"
        self._last_update_summary: str = ""
        self._pre_tx_updates_count: int = 0

        self._log_text: str = ""
        self._pkgbuild_preview: str = ""
        self._checking_updates: bool = False

        # Connect internal update signals
        self._updatesLoaded.connect(self._on_updates_loaded)
        self._indexReady.connect(self._on_index_ready)

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
        """Populate initial models with featured, discovery, home sections and installed packages."""
        self.refreshCatalog()
        self.refreshInstalled()
        self.checkUpdates()

    # -------------------------------------------------------------------------
    # Core Models Properties
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

    # -------------------------------------------------------------------------
    # Home Page & Discovery Models Properties (TASK-B2)
    # -------------------------------------------------------------------------

    @pyqtProperty(QObject, constant=True)
    def recommendedModel(self) -> PackageListModel:
        return self._recommended_model

    @pyqtProperty(QObject, constant=True)
    def popularCommunityModel(self) -> PackageListModel:
        return self._popular_community_model

    @pyqtProperty(QObject, constant=True)
    def gettingStartedModel(self) -> PackageListModel:
        return self._getting_started_model

    @pyqtProperty(QObject, constant=True)
    def developmentSectionModel(self) -> PackageListModel:
        return self._development_section_model

    @pyqtProperty(QObject, constant=True)
    def gamesSectionModel(self) -> PackageListModel:
        return self._games_section_model

    @pyqtProperty(QObject, constant=True)
    def designSectionModel(self) -> PackageListModel:
        return self._design_section_model

    @pyqtProperty(QObject, constant=True)
    def communicationSectionModel(self) -> PackageListModel:
        return self._communication_section_model

    @pyqtProperty(QObject, constant=True)
    def aurPopularModel(self) -> PackageListModel:
        return self._aur_popular_model

    @pyqtProperty(QObject, constant=True)
    def aurCommunityModel(self) -> PackageListModel:
        return self._aur_community_model

    @pyqtProperty(QObject, constant=True)
    def aurDevModel(self) -> PackageListModel:
        return self._aur_dev_model

    @pyqtProperty(QObject, constant=True)
    def aurGamesModel(self) -> PackageListModel:
        return self._aur_games_model

    @pyqtProperty(QObject, constant=True)
    def aurProductivityModel(self) -> PackageListModel:
        return self._aur_productivity_model

    @pyqtProperty(QObject, constant=True)
    def aurCuratedModel(self) -> PackageListModel:
        return self._aur_curated_model

    # -------------------------------------------------------------------------
    # Reactive State Properties
    # -------------------------------------------------------------------------

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
    def activeInstalledFilter(self) -> str:
        """Currently active installed filter ('all'|'installed'|'not_installed')."""
        return self._active_installed_filter

    @pyqtProperty(str, notify=filterChanged)
    def activeSortBy(self) -> str:
        """Currently active sorting method ('relevance'|'popularity'|'name'|'recent')."""
        return self._active_sort_by

    @pyqtProperty(bool, notify=filterChanged)
    def includeSystemPackages(self) -> bool:
        """True if system libraries/dependencies should be shown alongside applications."""
        return self._include_system_packages

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

    @pyqtProperty(int, notify=catalogChanged)
    def catalogTotalCount(self) -> int:
        """Total matching packages count in current search/filter."""
        return self._catalog_total_count

    @pyqtProperty(bool, notify=catalogChanged)
    def canLoadMoreCatalog(self) -> bool:
        """True if additional pages are available to load."""
        return self._can_load_more_catalog

    @pyqtProperty(str, notify=catalogChanged)
    def catalogStatus(self) -> str:
        """Catalog state: 'ready'|'loading'|'no_results'|'network_error'|'source_unavailable'|'unsynced_repos'|'empty_category'."""
        return self._catalog_status

    @pyqtProperty(str, notify=catalogChanged)
    def catalogStatusMessage(self) -> str:
        """Human-readable catalog status message."""
        return self._catalog_status_message

    @pyqtProperty(bool, notify=catalogChanged)
    def isIndexingCatalog(self) -> bool:
        """True while background sync database indexing is in progress."""
        return self._catalog_service._is_indexing

    @pyqtProperty(int, notify=catalogChanged)
    def officialSyncCount(self) -> int:
        """Total packages indexed from official pacman sync databases."""
        return len(self._catalog_service._official_repo_cache)

    @pyqtProperty(bool, notify=personalizationChanged)
    def personalizationEnabled(self) -> bool:
        """True if recommendations personalization is active."""
        return self._catalog_service.is_personalization_enabled()

    @pyqtProperty(bool, notify=personalizationChanged)
    def hasPersonalizationHistory(self) -> bool:
        """True if local history is present."""
        return self._catalog_service.has_personalization_history()

    @pyqtProperty(int, notify=personalizationChanged)
    def favoritesCount(self) -> int:
        """Total favorited packages count."""
        return self._catalog_service.get_favorites_count()

    @pyqtProperty(str, notify=updatesChanged)
    def lastUpdateOutcome(self) -> str:
        """Outcome of last system update: ''|'complete'|'partial'|'cancelled'|'failed'."""
        return self._last_update_outcome

    @pyqtProperty(str, notify=updatesChanged)
    def lastUpdateSummary(self) -> str:
        """Summary description of last system update."""
        return self._last_update_summary

    # -------------------------------------------------------------------------
    # Public Slots: Filter & Search Controls (TASK-B2)
    # -------------------------------------------------------------------------

    @pyqtSlot(str, str, str)
    def search(self, query: str, source_filter: str = "all", category_filter: str = "all") -> None:
        """Execute debounced search query across catalog with source and category filters."""
        self._search_query = query.strip()
        self._active_source_filter = source_filter or "all"
        self._active_category = category_filter or "all"
        self._catalog_offset = 0
        self.filterChanged.emit()

        if self._search_query:
            self._catalog_service.record_search_query(self._search_query)

        self._execute_catalog_search()

    @pyqtSlot(str)
    def setInstalledFilter(self, installed_filter: str) -> None:
        """Filter catalog by installed status ('all'|'installed'|'not_installed')."""
        filt = installed_filter or "all"
        if self._active_installed_filter != filt:
            self._active_installed_filter = filt
            self._catalog_offset = 0
            self.filterChanged.emit()
            self._execute_catalog_search()

    @pyqtSlot(str)
    def setSortBy(self, sort_by: str) -> None:
        """Set sorting order ('relevance'|'popularity'|'name'|'recent')."""
        sb = sort_by or "relevance"
        if self._active_sort_by != sb:
            self._active_sort_by = sb
            self._catalog_offset = 0
            self.filterChanged.emit()
            self._execute_catalog_search()

    @pyqtSlot(bool)
    def setIncludeSystemPackages(self, include_sys: bool) -> None:
        """Toggle whether to include low-level libraries and system packages."""
        if self._include_system_packages != include_sys:
            self._include_system_packages = bool(include_sys)
            self._catalog_offset = 0
            self.filterChanged.emit()
            self._execute_catalog_search()

    @pyqtSlot(str)
    def setCategory(self, category: str) -> None:
        """Filter catalog by canonical category name."""
        cat = category or "all"
        if self._active_category != cat:
            self._active_category = cat
            self._catalog_offset = 0
            self.filterChanged.emit()
            self._catalog_service.record_category_visit(cat)
            self._execute_catalog_search()

    @pyqtSlot(str)
    def setSourceFilter(self, source_filter: str) -> None:
        """Filter catalog by package origin ('all'|'official'|'aur')."""
        src = source_filter or "all"
        if self._active_source_filter != src:
            self._active_source_filter = src
            self._catalog_offset = 0
            self.filterChanged.emit()
            self._execute_catalog_search()

    @pyqtSlot()
    def loadMoreCatalog(self) -> None:
        """Load next page of catalog results and append to catalogModel."""
        if not self._can_load_more_catalog:
            return

        self._catalog_offset += self._catalog_page_size
        res = self._catalog_service.search_catalog(
            query=self._search_query,
            source_filter=self._active_source_filter,
            category_filter=self._active_category,
            installed_filter=self._active_installed_filter,
            apps_only=not self._include_system_packages,
            sort_by=self._active_sort_by,
            offset=self._catalog_offset,
            limit=self._catalog_page_size,
        )

        self._can_load_more_catalog = res.get("has_more", False)
        items = res.get("items", [])
        if items:
            self._catalog_model.append_items(items)
            self.catalogChanged.emit()

    @pyqtSlot(str)
    def exploreSection(self, section_id: str) -> None:
        """Configure category/source/sort filter corresponding to Home section and explore."""
        clean_sec = section_id.strip().lower()
        if clean_sec == "development":
            self._active_category = "development"
            self._active_source_filter = "all"
            self._active_sort_by = "relevance"
        elif clean_sec == "games":
            self._active_category = "games"
            self._active_source_filter = "all"
            self._active_sort_by = "relevance"
        elif clean_sec == "design":
            self._active_category = "design"
            self._active_source_filter = "all"
            self._active_sort_by = "relevance"
        elif clean_sec == "communication":
            self._active_category = "internet"
            self._active_source_filter = "all"
            self._active_sort_by = "relevance"
        elif clean_sec == "getting_started":
            self._active_category = "all"
            self._active_source_filter = "official"
            self._active_sort_by = "popularity"
        elif clean_sec == "popular":
            self._active_category = "all"
            self._active_source_filter = "all"
            self._active_sort_by = "popularity"
        elif clean_sec.startswith("aur_"):
            self._active_category = "all"
            self._active_source_filter = "aur"
            self._active_sort_by = "popularity"
        else:
            self._active_category = "all"
            self._active_source_filter = "all"
            self._active_sort_by = "relevance"

        self._search_query = ""
        self._catalog_offset = 0
        self.filterChanged.emit()
        self._execute_catalog_search()

    def _execute_catalog_search(self) -> None:
        """Internal helper to execute catalog search with active pagination and filters."""
        res = self._catalog_service.search_catalog(
            query=self._search_query,
            source_filter=self._active_source_filter,
            category_filter=self._active_category,
            installed_filter=self._active_installed_filter,
            apps_only=not self._include_system_packages,
            sort_by=self._active_sort_by,
            offset=self._catalog_offset,
            limit=self._catalog_page_size,
        )

        items = res.get("items", [])
        self._catalog_model.set_items(items)
        self._catalog_total_count = res.get("total", 0)
        self._can_load_more_catalog = res.get("has_more", False)
        self._catalog_status = res.get("status", "ready")
        self._catalog_status_message = res.get("message", "")
        self.catalogChanged.emit()

    # -------------------------------------------------------------------------
    # Personalization Slots (TASK-B2)
    # -------------------------------------------------------------------------

    @pyqtSlot(str)
    def toggleFavorite(self, pkg_name: str) -> None:
        """Toggle favorite status of a package and refresh affected models."""
        clean = pkg_name.strip()
        if not clean:
            return
        is_fav = self._catalog_service.toggle_favorite(clean)
        self.personalizationChanged.emit()

        # Update selected package if matching
        if self._selected_package.get("name") == clean:
            self._selected_package["is_favorite"] = is_fav
            self._selected_package["isFavorite"] = is_fav
            self.selectedPackageChanged.emit()

        # Refresh home recommendations
        self.refreshHomeSections()

    @pyqtSlot(bool)
    def setPersonalizationEnabled(self, enabled: bool) -> None:
        """Enable or disable recommendations personalization."""
        self._catalog_service.set_personalization_enabled(enabled)
        self.personalizationChanged.emit()
        self.refreshHomeSections()

    @pyqtSlot()
    def clearPersonalizationHistory(self) -> None:
        """Clear all local browsing and search history."""
        self._catalog_service.clear_personalization_history()
        self.personalizationChanged.emit()
        self.refreshHomeSections()
        self.toastMessage.emit("info", "Histórico de recomendações locais limpo com sucesso.")

    # -------------------------------------------------------------------------
    # Package Detail & Preview Slots
    # -------------------------------------------------------------------------

    @pyqtSlot(str, str)
    def selectPackage(self, pkg_name: str, repository: str = "") -> None:
        """Select a package to populate the PackageDetailModal view."""
        if not pkg_name:
            self._selected_package = {}
            self.selectedPackageChanged.emit()
            return

        clean = pkg_name.strip()
        self._catalog_service.record_package_view(clean)

        item = self._catalog_service.get_package(clean, repository)
        if item:
            self._selected_package = item.to_dict()
        else:
            self._selected_package = {
                "name": clean,
                "displayName": clean,
                "repository": repository or "official",
                "source": "aur" if repository == "aur" else "official",
                "installed": False,
                "updateAvailable": False,
                "isProtected": False,
                "isApplication": True,
            }
        self.selectedPackageChanged.emit()

        if self._selected_package.get("source") == "aur":
            self.fetchPkgbuildPreview(clean)
        else:
            self._pkgbuild_preview = ""
            self.pkgbuildPreviewChanged.emit()

    @pyqtSlot()
    def refreshCatalog(self) -> None:
        """Reload featured home packages, discovery sections, and explore catalog."""
        featured = self._catalog_service.get_featured_packages()
        self._featured_model.set_items(featured)
        self.refreshHomeSections()
        self.refreshAurDiscovery()
        self._execute_catalog_search()

    @pyqtSlot()
    def refreshHomeSections(self) -> None:
        """Populate the 8 Home page sections."""
        sections = self._catalog_service.get_home_sections()
        if "featured" in sections:
            self._featured_model.set_items(sections["featured"])
        if "recommended" in sections:
            self._recommended_model.set_items(sections["recommended"])
        if "popular" in sections:
            self._popular_community_model.set_items(sections["popular"])
        if "getting_started" in sections:
            self._getting_started_model.set_items(sections["getting_started"])
        if "development" in sections:
            self._development_section_model.set_items(sections["development"])
        if "games" in sections:
            self._games_section_model.set_items(sections["games"])
        if "design" in sections:
            self._design_section_model.set_items(sections["design"])
        if "communication" in sections:
            self._communication_section_model.set_items(sections["communication"])

    @pyqtSlot()
    def refreshAurDiscovery(self) -> None:
        """Populate the 6 AUR discovery sections."""
        aur_sections = self._catalog_service.get_aur_discovery_sections()
        if "aur_popular" in aur_sections:
            self._aur_popular_model.set_items(aur_sections["aur_popular"])
        if "aur_community" in aur_sections:
            self._aur_community_model.set_items(aur_sections["aur_community"])
        if "aur_development" in aur_sections:
            self._aur_dev_model.set_items(aur_sections["aur_development"])
        if "aur_games" in aur_sections:
            self._aur_games_model.set_items(aur_sections["aur_games"])
        if "aur_productivity" in aur_sections:
            self._aur_productivity_model.set_items(aur_sections["aur_productivity"])
        if "aur_curated" in aur_sections:
            self._aur_curated_model.set_items(aur_sections["aur_curated"])

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

    # -------------------------------------------------------------------------
    # Transaction Management & Safe Arch Linux Updates (TASK-B2)
    # -------------------------------------------------------------------------

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
        """Initiate package update with safety check against partial updates."""
        clean_name = pkg_name.strip()
        if not clean_name:
            self.toastMessage.emit("error", "Nome de pacote inválido.")
            return

        # Safe update behavior for Arch Linux: prevent partial upgrades on official packages
        if repository.lower() not in ("aur", "local-aur"):
            self.toastMessage.emit(
                "info",
                f"No Arch Linux, atualizações de pacotes oficiais ({clean_name}) requerem atualização completa do sistema para evitar inconsistências de bibliotecas. Iniciando atualização completa...",
            )
            self.updateAll()
            return

        self._tx_service.update_package(clean_name, repository)

    @pyqtSlot()
    def updateAll(self) -> None:
        """Initiate full system upgrade with tracking."""
        self._pre_tx_updates_count = self._updates_model.count
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

    def _on_index_ready(self) -> None:
        """Handle background sync index completion."""
        self.catalogChanged.emit()
        self._execute_catalog_search()

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
        """Handle transaction completion: post-verify updates, notify user, and refresh models."""
        toast_level = "success" if success else "error"
        toast_message = message

        # Post-verification and outcome computation for update operations
        if action in ("update_all", "update"):
            remaining_updates = self._catalog_service.check_updates()
            self._updates_model.set_items(remaining_updates)

            if not success:
                if self._tx_service.state == "cancelled":
                    self._last_update_outcome = "cancelled"
                    self._last_update_summary = message or "Atualização cancelada pelo usuário."
                    toast_level = "warning"
                else:
                    self._last_update_outcome = "failed"
                    self._last_update_summary = message or "Falha durante o processo de atualização."
                    toast_level = "error"
            else:
                rem_len = len(remaining_updates)
                if rem_len == 0:
                    self._last_update_outcome = "complete"
                    self._last_update_summary = "Sistema atualizado: todas as atualizações pendentes foram aplicadas com sucesso."
                    toast_level = "success"
                elif 0 < rem_len < self._pre_tx_updates_count:
                    self._last_update_outcome = "partial"
                    self._last_update_summary = f"Atualização parcial: restam {rem_len} pacote(s) pendentes."
                    toast_level = "warning"
                elif rem_len >= self._pre_tx_updates_count > 0:
                    self._last_update_outcome = "partial"
                    self._last_update_summary = f"Transação concluída, mas {rem_len} atualização(ões) ainda constam pendentes."
                    toast_level = "warning"
                else:
                    self._last_update_outcome = "complete"
                    self._last_update_summary = "Sistema atualizado com sucesso."
                    toast_level = "success"

            toast_message = self._last_update_summary or message

            if hasattr(self._tx_service, "set_post_verification_outcome"):
                self._tx_service.set_post_verification_outcome(self._last_update_outcome, self._last_update_summary)

            self.updatesChanged.emit()
        else:
            self.checkUpdates()

        # Emit user toast notification with verified level and summary
        self.toastMessage.emit(toast_level, toast_message)

        # Refresh local models automatically
        self.refreshInstalled()
        self.refreshCatalog()

        # Refresh selected package details if one was open
        selected_name = self._selected_package.get("name")
        if selected_name:
            repo = self._selected_package.get("repository", "")
            self.selectPackage(selected_name, repo)
