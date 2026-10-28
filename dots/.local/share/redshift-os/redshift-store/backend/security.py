"""Security module for Redshift Store backend.

Provides strict package name sanitization, critical package protection,
reverse dependency checking, pacman lock file verification, non-root enforcement
for AUR, graphical Polkit agent verification, and safe command builders.
"""

from __future__ import annotations

import logging
import os
import re
import subprocess
import time
from typing import Sequence

logger = logging.getLogger("redshift_store.security")


class SecurityViolationError(ValueError, PermissionError):
    """Raised when a security guardrail blocks an unsafe package operation."""


# Pacman package naming pattern: alphanumeric leading char, allowed punctuation: @._+-
# Strictly forbids leading hyphens (flags injection) and shell metacharacters.
PACKAGE_NAME_PATTERN = r"^[a-zA-Z0-9][a-zA-Z0-9@._+-]{0,127}$"
PACKAGE_NAME_RE: re.Pattern[str] = re.compile(PACKAGE_NAME_PATTERN)

# Critical system packages that MUST NEVER be removed via Redshift Store.
PROTECTED_PACKAGES: frozenset[str] = frozenset({
    "base",
    "linux",
    "linux-lts",
    "linux-zen",
    "systemd",
    "glibc",
    "pacman",
    "yay",
    "sudo",
    "polkit",
    "hyprland",
    "quickshell",
    "quickshell-git",
    "illogical-impulse-quickshell-git",
    "illogical-impulse-redshift-store",
    "python",
    "python-pyqt6",
    "qt6-base",
    "qt6-declarative",
    "filesystem",
    "bash",
    "coreutils",
    # Extended core packages & desktop requirements (F-BACK1)
    "polkit-kde-agent",
    "qt6-svg",
    "qt6-5compat",
    "python-gobject",
    "appstream",
    "archlinux-appstream-data",
    "pacman-contrib",
    "illogical-impulse-hyprland",
    "illogical-impulse-basic",
    "illogical-impulse-toolkit",
    "illogical-impulse-widgets",
    "illogical-impulse-python",
    "illogical-impulse-kde",
    "illogical-impulse-portal",
    "illogical-impulse-audio",
})

DEFAULT_PACMAN_LOCK_PATH = "/var/lib/pacman/db.lck"

KNOWN_POLKIT_AGENTS = (
    "/usr/lib/polkit-kde-authentication-agent-1",
    "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1",
    "/usr/lib/hyprpolkitagent",
    "/usr/bin/lxqt-policykit-agent",
    "/usr/lib/mate-polkit/polkit-mate-authentication-agent-1",
)

POLKIT_AGENT_BINARIES = frozenset({
    "polkit-kde-authentication-agent-1",
    "hyprpolkitagent",
    "polkit-gnome-authentication-agent-1",
    "lxqt-policykit-agent",
    "mate-polkit",
    "polkit-mate-authentication-agent-1",
})


def validate_package_name(name: str) -> bool:
    """Check if a package name is structurally valid and safe.

    Returns:
        True if valid, False otherwise.
    """
    if not isinstance(name, str):
        return False
    name = name.strip()
    if not name or name.startswith("-"):
        return False
    return bool(PACKAGE_NAME_RE.fullmatch(name))


def ensure_valid_package_name(name: str) -> str:
    """Validate a package name, returning the clean string or raising SecurityViolationError.

    Raises:
        SecurityViolationError: If name is empty, starts with a dash, contains invalid characters,
                    or exceeds maximum allowed length.
    """
    if not isinstance(name, str):
        raise SecurityViolationError(f"Package name must be a string, got {type(name).__name__}")
    clean_name = name.strip()
    if not clean_name:
        raise SecurityViolationError("Package name cannot be empty")
    if clean_name.startswith("-"):
        raise SecurityViolationError(f"Package name cannot start with a hyphen (flag injection risk): {clean_name!r}")
    if not PACKAGE_NAME_RE.fullmatch(clean_name):
        raise SecurityViolationError(
            f"Invalid package name contains forbidden characters or invalid length: {clean_name!r}"
        )
    return clean_name


def is_protected_package(name: str) -> bool:
    """Check if the given package name belongs to critical system packages.

    Args:
        name: The package name to test.

    Returns:
        True if the package is protected against deletion, False otherwise.
    """
    if not isinstance(name, str):
        return False
    return name.strip().lower() in PROTECTED_PACKAGES


def get_protected_reverse_dependencies(pkg_name: str) -> list[str]:
    """Query pacman to determine if any protected critical package depends on pkg_name.

    Uses pacman -Qi in read-only mode with a short timeout.
    """
    clean_name = ensure_valid_package_name(pkg_name)
    is_mock = os.environ.get("REDSHIFT_STORE_MOCK", "").strip().lower() in ("1", "true", "yes")
    if is_mock:
        # In mock mode, if testing core libs like glibc/qt6-base return protected dependents
        if clean_name in ("glibc", "systemd", "qt6-base", "python"):
            return ["quickshell", "hyprland"]
        return []

    try:
        res = subprocess.run(
            ["/usr/bin/pacman", "-Qi", "--", clean_name],
            capture_output=True,
            text=True,
            timeout=2,
            check=False,
        )
        if res.returncode != 0 or not res.stdout:
            return []

        m = re.search(r"^(?:Required By|Exigido por)\s*:\s*(.*)$", res.stdout, re.MULTILINE)
        if not m:
            return []

        raw_pkgs = m.group(1).split()
        protected_revs = [p for p in raw_pkgs if p.lower() not in ("none", "nenhum") and is_protected_package(p)]
        return sorted(list(set(protected_revs)))
    except Exception as e:
        logger.debug("Failed to query reverse dependencies for %s: %s", clean_name, e)
        return []


def ensure_not_protected(name: str, check_reverse_deps: bool = False) -> str:
    """Ensure the package name is valid and not in the protected system packages list.

    Args:
        name: Package name to check.
        check_reverse_deps: When True, also checks if any protected system package depends on it.

    Raises:
        SecurityViolationError: If the package is invalid, protected, or required by a protected package.
    """
    clean = ensure_valid_package_name(name)
    if is_protected_package(clean):
        raise SecurityViolationError(
            f"Cannot remove protected system package '{clean}'. "
            "Removal is blocked by Redshift Store to prevent system breakage."
        )

    if check_reverse_deps:
        rev_deps = get_protected_reverse_dependencies(clean)
        if rev_deps:
            raise SecurityViolationError(
                f"Cannot remove package '{clean}': critical system package(s) {', '.join(rev_deps)} depend on it."
            )

    return clean


def is_pacman_locked(lock_path: str = DEFAULT_PACMAN_LOCK_PATH) -> bool:
    """Check if pacman database lock file exists.

    Supports path override via the REDSHIFT_PACMAN_LOCK_PATH environment variable.

    Args:
        lock_path: Default lock path to check if env var is unset.

    Returns:
        True if lock file exists, False otherwise.
    """
    effective_path = os.environ.get("REDSHIFT_PACMAN_LOCK_PATH", lock_path)
    return os.path.exists(effective_path)


def ensure_non_root_for_aur(euid: int | None = None) -> None:
    """Ensure current effective UID is not root (EUID 0) for AUR operations.

    makepkg and yay must never be executed as root for security and permission reasons.

    Raises:
        SecurityViolationError: If EUID is 0.
    """
    current_euid = os.geteuid() if euid is None else euid
    if current_euid == 0:
        raise SecurityViolationError("Running yay or makepkg as root is strictly forbidden for security reasons.")


def is_polkit_agent_running() -> bool:
    """Check if an active graphical Polkit authentication agent is running for the user session."""
    current_pid = os.getpid()
    try:
        with os.scandir("/proc") as it:
            for entry in it:
                if entry.is_dir() and entry.name.isdigit():
                    if int(entry.name) == current_pid:
                        continue
                    try:
                        with open(os.path.join(entry.path, "comm"), "r", encoding="utf-8", errors="ignore") as f:
                            comm = f.read().strip()
                        if comm in POLKIT_AGENT_BINARIES:
                            return True

                        with open(os.path.join(entry.path, "cmdline"), "rb") as f:
                            raw = f.read()
                        parts = [p.decode("utf-8", errors="ignore") for p in raw.split(b"\x00") if p]
                        if not parts:
                            continue
                        bin_name = os.path.basename(parts[0])
                        if bin_name in POLKIT_AGENT_BINARIES:
                            return True
                        # Check for quickshell running with ii or PolkitService active
                        if bin_name == "quickshell" and any(arg in parts for arg in ("ii", "IllogicalImpulseFamily")):
                            return True
                    except OSError:
                        continue
    except Exception as e:
        logger.debug("Error checking Polkit agent in /proc: %s", e)

    return False


def ensure_polkit_agent() -> bool:
    """Ensure a graphical Polkit agent is running, launching one if missing (e.g. in Caelestia Shell).

    Returns:
        True if an agent is running or was successfully started, False otherwise.
    """
    if is_polkit_agent_running():
        return True

    for agent_path in KNOWN_POLKIT_AGENTS:
        if os.path.isfile(agent_path) and os.access(agent_path, os.X_OK):
            try:
                logger.info("Starting Polkit agent: %s", agent_path)
                subprocess.Popen(
                    [agent_path],
                    start_new_session=True,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
                time.sleep(0.25)
                return True
            except OSError as e:
                logger.warning("Failed to launch Polkit agent %s: %s", agent_path, e)

    logger.warning("No graphical Polkit authentication agent could be found or launched.")
    return False


def build_safe_pacman_install_cmd(pkg_names: Sequence[str]) -> list[str]:
    """Build a safe command argv list for installing official packages via pacman.

    Validates package names, prevents flag injection, and uses pkexec without --noconfirm.

    Args:
        pkg_names: Sequence of package names to install.

    Returns:
        List of command arguments ready for QProcess/subprocess.

    Raises:
        SecurityViolationError: If package list is empty or contains invalid package names.
    """
    if not pkg_names:
        raise SecurityViolationError("Package list cannot be empty for installation")
    validated = [ensure_valid_package_name(pkg) for pkg in pkg_names]
    return ["/usr/bin/pkexec", "/usr/bin/pacman", "-S", "--needed", "--", *validated]


def build_safe_pacman_remove_cmd(pkg_names: Sequence[str], check_reverse_deps: bool = True) -> list[str]:
    """Build a safe command argv list for removing packages via pacman.

    Enforces validation, blocks deletion of protected system packages, and uses pkexec.

    Args:
        pkg_names: Sequence of package names to remove.
        check_reverse_deps: Check if any protected system package depends on them.

    Returns:
        List of command arguments ready for QProcess/subprocess.

    Raises:
        SecurityViolationError: If package list is empty, contains invalid names, or contains protected packages.
    """
    if not pkg_names:
        raise SecurityViolationError("Package list cannot be empty for removal")

    validated = [ensure_not_protected(pkg, check_reverse_deps=check_reverse_deps) for pkg in pkg_names]
    return ["/usr/bin/pkexec", "/usr/bin/pacman", "-R", "--", *validated]


def build_safe_pacman_sysupgrade_cmd() -> list[str]:
    """Build safe command argv list for full system upgrade via pacman.

    Returns:
        List of command arguments ready for QProcess/subprocess.
    """
    return ["/usr/bin/pkexec", "/usr/bin/pacman", "-Syu"]


def build_safe_yay_install_cmd(pkg_names: Sequence[str], euid: int | None = None) -> list[str]:
    """Build a safe command argv list for installing AUR packages via yay.

    Guarantees non-root execution, validates package names, delegates final privilege
    elevation to pkexec without interactive TTY sudo dependency, and appends '--'.

    Args:
        pkg_names: Sequence of package names to install.
        euid: Optional EUID override for test isolation.

    Returns:
        List of command arguments ready for QProcess/subprocess.

    Raises:
        SecurityViolationError: If running as root (EUID 0), or if package list is empty/invalid.
    """
    ensure_non_root_for_aur(euid)
    if not pkg_names:
        raise SecurityViolationError("Package list cannot be empty for AUR installation")
    validated = [ensure_valid_package_name(pkg) for pkg in pkg_names]
    return [
        "/usr/bin/yay",
        "-S",
        "--needed",
        "--sudo",
        "/usr/bin/pkexec",
        "--answerclean",
        "None",
        "--answerdiff",
        "None",
        "--",
        *validated,
    ]


def build_safe_yay_sysupgrade_cmd(euid: int | None = None) -> list[str]:
    """Build safe command argv list for full system upgrade of AUR packages via yay.

    Delegates final elevation to pkexec without interactive TTY sudo dependency.

    Args:
        euid: Optional EUID override for test isolation.

    Returns:
        List of command arguments ready for QProcess/subprocess.
    """
    ensure_non_root_for_aur(euid)
    return [
        "/usr/bin/yay",
        "-Sua",
        "--sudo",
        "/usr/bin/pkexec",
        "--answerclean",
        "None",
        "--answerdiff",
        "None",
    ]
