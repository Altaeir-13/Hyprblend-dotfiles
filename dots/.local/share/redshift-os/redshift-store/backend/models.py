"""Data models and QAbstractListModel for Redshift Store.

Defines PackageItem dataclass conforming to REDSHIFT_STORE_ARCHITECTURE Section 3.1
and PackageListModel providing reactive Qt6/QML list binding with pagination and discovery roles.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Sequence

from PyQt6.QtCore import (
    QAbstractListModel,
    QByteArray,
    QModelIndex,
    Qt,
    pyqtProperty,
    pyqtSignal,
    pyqtSlot,
)


@dataclass
class PackageItem:
    """Represents a software package in Redshift Store.

    Conforms to REDSHIFT_STORE_ARCHITECTURE.md Section 3.1 schema, enriched with
    discovery, AppStream screenshots, pkgstats popularity, provenance, and curation flags.
    """

    # Core 23 fields from TASK-B1
    name: str = ""
    display_name: str = ""
    summary: str = ""
    description: str = ""
    version: str = ""
    installed_version: str = ""
    repository: str = ""
    source: str = "official"  # "official" | "aur"
    installed: bool = False
    explicit: bool = False
    update_available: bool = False
    category: str = "utilities"
    icon_name: str = ""
    installed_size: str = ""
    download_size: str = ""
    license: str = ""
    url: str = ""
    depends: list[str] = field(default_factory=list)
    optdepends: list[str] = field(default_factory=list)
    votes: int = 0
    popularity: float = 0.0
    maintainer: str = ""
    is_protected: bool = False

    # 10 New Discovery & Rich Metadata fields for TASK-B2
    is_application: bool = True
    app_id: str = ""
    screenshots: list[str] = field(default_factory=list)
    popularity_source: str = ""  # "pkgstats" | "aur_rpc" | "curated" | ""
    popularity_label: str = ""  # e.g., "69.1% pkgstats" or "1.711 votos · pop 13.0"
    provenance: str = "repo"  # "editorial" | "pkgstats" | "aur_popular" | "personalized" | "appstream" | "pacman_sync"
    provenance_label: str = ""  # e.g., "Selecionado pela curadoria Redshift OS"
    is_favorite: bool = False
    build_date: int = 0
    groups: list[str] = field(default_factory=list)

    def to_dict(self) -> dict[str, Any]:
        """Convert to dictionary with both snake_case and camelCase keys for QML."""
        name_val = self.name
        display_val = self.display_name or self.name

        return {
            # snake_case canonical keys
            "name": name_val,
            "display_name": display_val,
            "summary": self.summary,
            "description": self.description,
            "version": self.version,
            "installed_version": self.installed_version,
            "repository": self.repository,
            "source": self.source,
            "installed": bool(self.installed),
            "explicit": bool(self.explicit),
            "update_available": bool(self.update_available),
            "category": self.category,
            "icon_name": self.icon_name,
            "installed_size": self.installed_size,
            "download_size": self.download_size,
            "license": self.license,
            "url": self.url,
            "depends": list(self.depends),
            "optdepends": list(self.optdepends),
            "votes": int(self.votes),
            "popularity": float(self.popularity),
            "maintainer": self.maintainer,
            "is_protected": bool(self.is_protected),
            "is_application": bool(self.is_application),
            "app_id": self.app_id,
            "screenshots": list(self.screenshots),
            "popularity_source": self.popularity_source,
            "popularity_label": self.popularity_label,
            "provenance": self.provenance,
            "provenance_label": self.provenance_label,
            "is_favorite": bool(self.is_favorite),
            "build_date": int(self.build_date),
            "groups": list(self.groups),
            # camelCase aliases for direct QML property access
            "displayName": display_val,
            "installedVersion": self.installed_version,
            "updateAvailable": bool(self.update_available),
            "iconName": self.icon_name,
            "installedSize": self.installed_size,
            "downloadSize": self.download_size,
            "isProtected": bool(self.is_protected),
            "isApplication": bool(self.is_application),
            "appId": self.app_id,
            "popularitySource": self.popularity_source,
            "popularityLabel": self.popularity_label,
            "provenanceLabel": self.provenance_label,
            "isFavorite": bool(self.is_favorite),
            "buildDate": int(self.build_date),
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> PackageItem:
        """Create a PackageItem instance from a dictionary."""
        return cls(
            name=str(data.get("name", "")),
            display_name=str(data.get("displayName", data.get("display_name", ""))),
            summary=str(data.get("summary", "")),
            description=str(data.get("description", "")),
            version=str(data.get("version", "")),
            installed_version=str(data.get("installedVersion", data.get("installed_version", ""))),
            repository=str(data.get("repository", "")),
            source=str(data.get("source", "official")),
            installed=bool(data.get("installed", False)),
            explicit=bool(data.get("explicit", False)),
            update_available=bool(data.get("updateAvailable", data.get("update_available", False))),
            category=str(data.get("category", "utilities")),
            icon_name=str(data.get("iconName", data.get("icon_name", ""))),
            installed_size=str(data.get("installedSize", data.get("installed_size", ""))),
            download_size=str(data.get("downloadSize", data.get("download_size", ""))),
            license=str(data.get("license", "")),
            url=str(data.get("url", "")),
            depends=list(data.get("depends", [])),
            optdepends=list(data.get("optdepends", [])),
            votes=int(data.get("votes", 0)),
            popularity=float(data.get("popularity", 0.0)),
            maintainer=str(data.get("maintainer", "")),
            is_protected=bool(data.get("isProtected", data.get("is_protected", False))),
            is_application=bool(data.get("isApplication", data.get("is_application", True))),
            app_id=str(data.get("appId", data.get("app_id", ""))),
            screenshots=list(data.get("screenshots", [])),
            popularity_source=str(data.get("popularitySource", data.get("popularity_source", ""))),
            popularity_label=str(data.get("popularityLabel", data.get("popularity_label", ""))),
            provenance=str(data.get("provenance", "repo")),
            provenance_label=str(data.get("provenanceLabel", data.get("provenance_label", ""))),
            is_favorite=bool(data.get("isFavorite", data.get("is_favorite", False))),
            build_date=int(data.get("buildDate", data.get("build_date", 0))),
            groups=list(data.get("groups", [])),
        )


class PackageRoles:
    """User roles for PackageListModel QML binding (total of 34 roles)."""

    NameRole = Qt.ItemDataRole.UserRole + 1
    DisplayNameRole = Qt.ItemDataRole.UserRole + 2
    SummaryRole = Qt.ItemDataRole.UserRole + 3
    DescriptionRole = Qt.ItemDataRole.UserRole + 4
    VersionRole = Qt.ItemDataRole.UserRole + 5
    InstalledVersionRole = Qt.ItemDataRole.UserRole + 6
    RepositoryRole = Qt.ItemDataRole.UserRole + 7
    SourceRole = Qt.ItemDataRole.UserRole + 8
    InstalledRole = Qt.ItemDataRole.UserRole + 9
    ExplicitRole = Qt.ItemDataRole.UserRole + 10
    UpdateAvailableRole = Qt.ItemDataRole.UserRole + 11
    CategoryRole = Qt.ItemDataRole.UserRole + 12
    IconNameRole = Qt.ItemDataRole.UserRole + 13
    InstalledSizeRole = Qt.ItemDataRole.UserRole + 14
    DownloadSizeRole = Qt.ItemDataRole.UserRole + 15
    LicenseRole = Qt.ItemDataRole.UserRole + 16
    UrlRole = Qt.ItemDataRole.UserRole + 17
    DependsRole = Qt.ItemDataRole.UserRole + 18
    OptdependsRole = Qt.ItemDataRole.UserRole + 19
    VotesRole = Qt.ItemDataRole.UserRole + 20
    PopularityRole = Qt.ItemDataRole.UserRole + 21
    MaintainerRole = Qt.ItemDataRole.UserRole + 22
    IsProtectedRole = Qt.ItemDataRole.UserRole + 23
    ItemDataRole = Qt.ItemDataRole.UserRole + 24

    # 10 New Discovery roles for TASK-B2
    IsApplicationRole = Qt.ItemDataRole.UserRole + 25
    AppIdRole = Qt.ItemDataRole.UserRole + 26
    ScreenshotsRole = Qt.ItemDataRole.UserRole + 27
    PopularitySourceRole = Qt.ItemDataRole.UserRole + 28
    PopularityLabelRole = Qt.ItemDataRole.UserRole + 29
    ProvenanceRole = Qt.ItemDataRole.UserRole + 30
    ProvenanceLabelRole = Qt.ItemDataRole.UserRole + 31
    IsFavoriteRole = Qt.ItemDataRole.UserRole + 32
    BuildDateRole = Qt.ItemDataRole.UserRole + 33
    GroupsRole = Qt.ItemDataRole.UserRole + 34


class PackageListModel(QAbstractListModel):
    """QAbstractListModel implementation exposing PackageItem objects to QML views."""

    countChanged = pyqtSignal()

    def __init__(self, parent: Any = None) -> None:
        super().__init__(parent)
        self._items: list[PackageItem] = []
        self._name_index: dict[str, int] = {}

    # -------------------------------------------------------------------------
    # QAbstractListModel Required Overrides
    # -------------------------------------------------------------------------

    def rowCount(self, parent: QModelIndex = QModelIndex()) -> int:
        """Return the number of rows under the given parent."""
        if parent.isValid():
            return 0
        return len(self._items)

    def data(self, index: QModelIndex, role: int = Qt.ItemDataRole.DisplayRole) -> Any:
        """Return data for the given index and role."""
        if not index.isValid():
            return None

        row = index.row()
        if row < 0 or row >= len(self._items):
            return None

        item = self._items[row]

        if role in (Qt.ItemDataRole.DisplayRole, PackageRoles.DisplayNameRole):
            return item.display_name or item.name
        if role == PackageRoles.NameRole:
            return item.name
        if role == PackageRoles.SummaryRole:
            return item.summary
        if role == PackageRoles.DescriptionRole:
            return item.description
        if role == PackageRoles.VersionRole:
            return item.version
        if role == PackageRoles.InstalledVersionRole:
            return item.installed_version
        if role == PackageRoles.RepositoryRole:
            return item.repository
        if role == PackageRoles.SourceRole:
            return item.source
        if role == PackageRoles.InstalledRole:
            return item.installed
        if role == PackageRoles.ExplicitRole:
            return item.explicit
        if role == PackageRoles.UpdateAvailableRole:
            return item.update_available
        if role == PackageRoles.CategoryRole:
            return item.category
        if role == PackageRoles.IconNameRole:
            return item.icon_name
        if role == PackageRoles.InstalledSizeRole:
            return item.installed_size
        if role == PackageRoles.DownloadSizeRole:
            return item.download_size
        if role == PackageRoles.LicenseRole:
            return item.license
        if role == PackageRoles.UrlRole:
            return item.url
        if role == PackageRoles.DependsRole:
            return list(item.depends)
        if role == PackageRoles.OptdependsRole:
            return list(item.optdepends)
        if role == PackageRoles.VotesRole:
            return item.votes
        if role == PackageRoles.PopularityRole:
            return item.popularity
        if role == PackageRoles.MaintainerRole:
            return item.maintainer
        if role == PackageRoles.IsProtectedRole:
            return item.is_protected
        if role == PackageRoles.ItemDataRole:
            return item.to_dict()

        # 10 New Discovery roles
        if role == PackageRoles.IsApplicationRole:
            return item.is_application
        if role == PackageRoles.AppIdRole:
            return item.app_id
        if role == PackageRoles.ScreenshotsRole:
            return list(item.screenshots)
        if role == PackageRoles.PopularitySourceRole:
            return item.popularity_source
        if role == PackageRoles.PopularityLabelRole:
            return item.popularity_label
        if role == PackageRoles.ProvenanceRole:
            return item.provenance
        if role == PackageRoles.ProvenanceLabelRole:
            return item.provenance_label
        if role == PackageRoles.IsFavoriteRole:
            return item.is_favorite
        if role == PackageRoles.BuildDateRole:
            return item.build_date
        if role == PackageRoles.GroupsRole:
            return list(item.groups)

        return None

    def roleNames(self) -> dict[int, QByteArray]:
        """Return role names dictionary for QML model consumption (34 roles)."""
        return {
            PackageRoles.NameRole: QByteArray(b"name"),
            PackageRoles.DisplayNameRole: QByteArray(b"displayName"),
            PackageRoles.SummaryRole: QByteArray(b"summary"),
            PackageRoles.DescriptionRole: QByteArray(b"description"),
            PackageRoles.VersionRole: QByteArray(b"version"),
            PackageRoles.InstalledVersionRole: QByteArray(b"installedVersion"),
            PackageRoles.RepositoryRole: QByteArray(b"repository"),
            PackageRoles.SourceRole: QByteArray(b"source"),
            PackageRoles.InstalledRole: QByteArray(b"installed"),
            PackageRoles.ExplicitRole: QByteArray(b"explicit"),
            PackageRoles.UpdateAvailableRole: QByteArray(b"updateAvailable"),
            PackageRoles.CategoryRole: QByteArray(b"category"),
            PackageRoles.IconNameRole: QByteArray(b"iconName"),
            PackageRoles.InstalledSizeRole: QByteArray(b"installedSize"),
            PackageRoles.DownloadSizeRole: QByteArray(b"downloadSize"),
            PackageRoles.LicenseRole: QByteArray(b"license"),
            PackageRoles.UrlRole: QByteArray(b"url"),
            PackageRoles.DependsRole: QByteArray(b"depends"),
            PackageRoles.OptdependsRole: QByteArray(b"optdepends"),
            PackageRoles.VotesRole: QByteArray(b"votes"),
            PackageRoles.PopularityRole: QByteArray(b"popularity"),
            PackageRoles.MaintainerRole: QByteArray(b"maintainer"),
            PackageRoles.IsProtectedRole: QByteArray(b"isProtected"),
            PackageRoles.ItemDataRole: QByteArray(b"itemData"),
            # 10 New roles for TASK-B2
            PackageRoles.IsApplicationRole: QByteArray(b"isApplication"),
            PackageRoles.AppIdRole: QByteArray(b"appId"),
            PackageRoles.ScreenshotsRole: QByteArray(b"screenshots"),
            PackageRoles.PopularitySourceRole: QByteArray(b"popularitySource"),
            PackageRoles.PopularityLabelRole: QByteArray(b"popularityLabel"),
            PackageRoles.ProvenanceRole: QByteArray(b"provenance"),
            PackageRoles.ProvenanceLabelRole: QByteArray(b"provenanceLabel"),
            PackageRoles.IsFavoriteRole: QByteArray(b"isFavorite"),
            PackageRoles.BuildDateRole: QByteArray(b"buildDate"),
            PackageRoles.GroupsRole: QByteArray(b"groups"),
        }

    # -------------------------------------------------------------------------
    # Properties & Public Methods
    # -------------------------------------------------------------------------

    @pyqtProperty(int, notify=countChanged)
    def count(self) -> int:
        """Return the total number of items in the model."""
        return len(self._items)

    @property
    def items(self) -> list[PackageItem]:
        """Return a copy of the underlying items list."""
        return list(self._items)

    def set_items(self, items: Sequence[PackageItem]) -> None:
        """Replace model content with a new list of PackageItem instances."""
        self.beginResetModel()
        self._items = list(items)
        self._name_index = {item.name: i for i, item in enumerate(self._items)}
        self.endResetModel()
        self.countChanged.emit()

    def append_items(self, items: Sequence[PackageItem]) -> None:
        """Append items that are not already present in the model."""
        new_items = [it for it in items if it.name not in self._name_index]
        if not new_items:
            return

        start = len(self._items)
        end = start + len(new_items) - 1

        self.beginInsertRows(QModelIndex(), start, end)
        for item in new_items:
            self._name_index[item.name] = len(self._items)
            self._items.append(item)
        self.endInsertRows()
        self.countChanged.emit()

    def clear(self) -> None:
        """Clear all items in the model."""
        self.set_items([])

    @pyqtSlot(str, result="QVariant")
    def get_by_name(self, name: str) -> PackageItem | None:
        """Find a package item by its exact package name."""
        idx = self._name_index.get(name)
        if idx is not None and 0 <= idx < len(self._items):
            return self._items[idx]
        return None

    @pyqtSlot(int, result="QVariant")
    def get_at(self, row: int) -> PackageItem | None:
        """Return the PackageItem at the given row, or None if out of bounds."""
        if 0 <= row < len(self._items):
            return self._items[row]
        return None

    @pyqtSlot(str, result="QVariantMap")
    def get_dict_by_name(self, name: str) -> dict[str, Any]:
        """Find a package and return its dictionary representation for QML."""
        item = self.get_by_name(name)
        return item.to_dict() if item else {}
