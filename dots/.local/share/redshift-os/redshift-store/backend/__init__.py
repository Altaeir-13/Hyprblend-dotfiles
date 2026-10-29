"""Redshift Store Backend Package.

Provides data models, reactive QAbstractListModel instances, security validations,
package discovery, updates, asynchronous transaction management, and the
StoreController bridge for Redshift OS.
"""

from __future__ import annotations

from .catalog_service import (
    CANONICAL_CATEGORIES,
    FEATURED_PACKAGES_METADATA,
    CatalogService,
    format_size,
    infer_category_and_icon,
    is_mock_mode,
    normalize_category,
)
from .models import (
    PackageItem,
    PackageListModel,
    PackageRoles,
)
from .security import (
    DEFAULT_PACMAN_LOCK_PATH,
    PACKAGE_NAME_PATTERN,
    PACKAGE_NAME_RE,
    PROTECTED_PACKAGES,
    SecurityViolationError,
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
from .maintenance_service import MaintenanceService
from .store_controller import StoreController
from .theme_service import ThemeService
from .transaction_service import TransactionService

__all__ = [
    "CANONICAL_CATEGORIES",
    "CatalogService",
    "DEFAULT_PACMAN_LOCK_PATH",
    "FEATURED_PACKAGES_METADATA",
    "MaintenanceService",
    "PACKAGE_NAME_PATTERN",
    "PACKAGE_NAME_RE",
    "PROTECTED_PACKAGES",
    "PackageItem",
    "PackageListModel",
    "PackageRoles",
    "SecurityViolationError",
    "StoreController",
    "ThemeService",
    "TransactionService",
    "build_safe_pacman_install_cmd",
    "build_safe_pacman_remove_cmd",
    "build_safe_pacman_sysupgrade_cmd",
    "build_safe_yay_install_cmd",
    "build_safe_yay_sysupgrade_cmd",
    "ensure_non_root_for_aur",
    "ensure_not_protected",
    "ensure_polkit_agent",
    "ensure_valid_package_name",
    "format_size",
    "get_protected_reverse_dependencies",
    "infer_category_and_icon",
    "is_mock_mode",
    "is_pacman_locked",
    "is_polkit_agent_running",
    "is_protected_package",
    "normalize_category",
    "validate_package_name",
]
