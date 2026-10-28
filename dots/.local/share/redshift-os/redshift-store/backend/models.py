"""Data models and QAbstractListModel for Redshift Store.

Defines PackageItem dataclass conforming to REDSHIFT_STORE_ARCHITECTURE Section 3.1
and PackageListModel providing reactive Qt6/QML list binding.
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

    Conforms to REDSHIFT_STORE_ARCHITECTURE.md Section 3.1 schema.
    """

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
            "installed": self.installed,
            "explicit": self.explicit,
            "update_available": self.update_available,
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
            # camelCase aliases for direct QML property access
            "displayName": display_val,
            "installedVersion": self.installed_version,
            "updateAvailable": bool(self.update_available),
            "iconName": self.icon_name,
            "installedSize": self.installed_size,
            "downloadSize": self.download_size,
            "isProtected": bool(self.is_protected),
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
        )


class PackageRoles:
    """User roles for PackageListModel QML binding."""

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

        return None

    def roleNames(self) -> dict[int, QByteArray]:
        """Return role names dictionary for QML model consumption."""
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
