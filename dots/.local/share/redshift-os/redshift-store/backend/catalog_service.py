"""Catalog and package indexing service for Redshift Store.

Provides indexing of locally installed packages (/var/lib/pacman/local),
official pacman repositories (pacman -Sl), AppStream metadata and desktop entries,
curated featured packages, update checking (checkupdates + yay -Qua),
AUR search with memory caching (TTL 120s), and safe PKGBUILD inspection.
Supports offline/mock execution when REDSHIFT_STORE_MOCK=1 or REDSHIFT_STORE_SANDBOX=1.
"""

from __future__ import annotations

import glob
import json
import logging
import os
import re
import subprocess
import time
import urllib.parse
import urllib.request
from typing import Any, Sequence

from .models import PackageItem
from .security import (
    DEFAULT_PACMAN_LOCK_PATH,
    ensure_valid_package_name,
    is_protected_package,
    validate_package_name,
)

logger = logging.getLogger("redshift_store.catalog")

CANONICAL_CATEGORIES: tuple[str, ...] = (
    "featured",
    "internet",
    "development",
    "games",
    "multimedia",
    "utilities",
    "system",
    "office",
)

DEFAULT_PACMAN_LOCAL_DIR = "/var/lib/pacman/local"
AUR_RPC_SEARCH_URL = "https://aur.archlinux.org/rpc/v5/search/{query}"
AUR_CGIT_PKGBUILD_URL = "https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h={pkg}"


def is_mock_mode() -> bool:
    """Check if sandbox or mock mode is requested via environment."""
    return (
        os.environ.get("REDSHIFT_STORE_MOCK", "").strip().lower() in ("1", "true", "yes")
        or os.environ.get("REDSHIFT_STORE_SANDBOX", "").strip().lower() in ("1", "true", "yes")
    )


def format_size(size_bytes: int | float | str | None) -> str:
    """Format byte size into human readable string (KiB, MiB, GiB)."""
    if size_bytes is None:
        return ""
    try:
        val = float(size_bytes)
    except (ValueError, TypeError):
        return str(size_bytes)
    if val <= 0:
        return ""
    if val < 1024:
        return f"{val:.0f} B"
    if val < 1024 * 1024:
        return f"{val / 1024:.1f} KiB"
    if val < 1024 * 1024 * 1024:
        return f"{val / (1024 * 1024):.1f} MiB"
    return f"{val / (1024 * 1024 * 1024):.2f} GiB"


def normalize_category(category_raw: str, default: str = "utilities") -> str:
    """Map any raw category string into one of the 8 canonical store categories."""
    if not category_raw:
        return default
    cat_lower = category_raw.lower()

    if "game" in cat_lower or "emulator" in cat_lower or "arcade" in cat_lower:
        return "games"
    if any(k in cat_lower for k in ("audio", "video", "multimedia", "music", "player", "graphics", "recorder")):
        return "multimedia"
    if any(k in cat_lower for k in ("develop", "ide", "compiler", "editor", "programming", "git")):
        return "development"
    if any(k in cat_lower for k in ("network", "web", "browser", "chat", "im", "mail", "internet", "messaging")):
        return "internet"
    if any(k in cat_lower for k in ("office", "word", "sheet", "pdf", "document", "calc", "publishing")):
        return "office"
    if any(k in cat_lower for k in ("system", "driver", "kernel", "filesystem", "settings", "monitor", "shell")):
        return "system"
    if "featured" in cat_lower:
        return "featured"
    return "utilities"


def infer_category_and_icon(name: str, desc: str = "", appstream_cat: str = "") -> tuple[str, str]:
    """Infer store category and semantic fallback icon based on package metadata."""
    if appstream_cat:
        cat = normalize_category(appstream_cat)
    else:
        text = f"{name} {desc}".lower()
        cat = normalize_category(text)

    # Category default icons (freedesktop standard glyphs)
    category_icons = {
        "games": "applications-games",
        "multimedia": "applications-multimedia",
        "development": "applications-development",
        "internet": "applications-internet",
        "office": "applications-office",
        "system": "applications-system",
        "utilities": "applications-utilities",
        "featured": "emblem-favorite",
    }
    return cat, category_icons.get(cat, "applications-other")


# Curated featured applications for Redshift OS with rich descriptions
FEATURED_PACKAGES_METADATA: tuple[dict[str, Any], ...] = (
    {
        "name": "firefox",
        "display_name": "Firefox",
        "summary": "Navegador web rápido, privado e seguro",
        "description": "Mozilla Firefox é um navegador livre e de código aberto com foco em privacidade, extensões completas e renderização moderna.",
        "category": "internet",
        "icon_name": "firefox",
        "url": "https://www.mozilla.org/firefox/",
        "license": "MPL-2.0",
        "repository": "extra",
        "source": "official",
    },
    {
        "name": "kitty",
        "display_name": "Kitty",
        "summary": "Emulador de terminal moderno acelerado por GPU",
        "description": "Emulador de terminal rápido com renderização OpenGL, suporte a gráficos, splits de janela e extensibilidade com kittens.",
        "category": "system",
        "icon_name": "kitty",
        "url": "https://sw.kovidgoyal.net/kitty/",
        "license": "GPL-3.0-only",
        "repository": "extra",
        "source": "official",
    },
    {
        "name": "visual-studio-code-bin",
        "display_name": "Visual Studio Code",
        "summary": "Editor de código profissional com suporte a extensões",
        "description": "Editor avançado com suporte a IntelliSense, depuração integrada, controle Git nativo e rico ecossistema de extensões.",
        "category": "development",
        "icon_name": "visual-studio-code",
        "url": "https://code.visualstudio.com/",
        "license": "custom",
        "repository": "aur",
        "source": "aur",
    },
    {
        "name": "obs-studio",
        "display_name": "OBS Studio",
        "summary": "Software profissional de gravação de vídeo e transmissão ao vivo",
        "description": "Ferramenta de ponta para captura, mixagem de vídeo/áudio em tempo real e streaming compatível com Wayland e PipeWire.",
        "category": "multimedia",
        "icon_name": "com.obsproject.Studio",
        "url": "https://obsproject.com/",
        "license": "GPL-2.0-or-later",
        "repository": "extra",
        "source": "official",
    },
    {
        "name": "gimp",
        "display_name": "GIMP",
        "summary": "Editor de imagens e ilustrações avançado",
        "description": "GNU Image Manipulation Program para retoque de fotos, composição de imagens e criação de arte digital.",
        "category": "multimedia",
        "icon_name": "gimp",
        "url": "https://www.gimp.org/",
        "license": "GPL-3.0-or-later",
        "repository": "extra",
        "source": "official",
    },
    {
        "name": "mpv",
        "display_name": "MPV",
        "summary": "Reprodutor de mídia minimalista e de alta performance",
        "description": "Reprodutor de mídia leve com aceleração por hardware, saída de vídeo com alta qualidade de renderização e scripts Lua.",
        "category": "multimedia",
        "icon_name": "mpv",
        "url": "https://mpv.io/",
        "license": "GPL-2.0-or-later",
        "repository": "extra",
        "source": "official",
    },
    {
        "name": "vlc",
        "display_name": "VLC Media Player",
        "summary": "Reprodutor multimídia universal",
        "description": "Reprodutor multimídia capaz de reproduzir a maioria dos codecs e formatos sem a necessidade de pacotes adicionais.",
        "category": "multimedia",
        "icon_name": "vlc",
        "url": "https://www.videolan.org/vlc/",
        "license": "GPL-2.0-or-later",
        "repository": "extra",
        "source": "official",
    },
    {
        "name": "steam",
        "display_name": "Steam",
        "summary": "Plataforma líder para jogos e entretenimento digital",
        "description": "Cliente Steam para gerenciar, baixar e jogar milhares de jogos no Linux com compatibilidade Proton/Vulkan.",
        "category": "games",
        "icon_name": "steam",
        "url": "https://steampowered.com/",
        "license": "custom",
        "repository": "multilib",
        "source": "official",
    },
    {
        "name": "lutris",
        "display_name": "Lutris",
        "summary": "Gerenciador unificado para jogos de PC, emuladores e Wine",
        "description": "Plataforma aberta para organizar e iniciar sua biblioteca de jogos no Linux, incluindo GOG, Epic Games e emuladores.",
        "category": "games",
        "icon_name": "net.lutris.Lutris",
        "url": "https://lutris.net/",
        "license": "GPL-3.0-or-later",
        "repository": "extra",
        "source": "official",
    },
    {
        "name": "telegram-desktop",
        "display_name": "Telegram",
        "summary": "Mensageiro instantâneo seguro, rápido e sincronizado",
        "description": "Aplicativo oficial para desktop do serviço de mensagens em nuvem Telegram, com canais, grupos e compartilhamento veloz.",
        "category": "internet",
        "icon_name": "telegram",
        "url": "https://desktop.telegram.org/",
        "license": "GPL-3.0-only",
        "repository": "extra",
        "source": "official",
    },
    {
        "name": "spotify",
        "display_name": "Spotify",
        "summary": "Streaming de músicas, podcasts e álbuns",
        "description": "Cliente para o serviço de streaming de áudio com playlists personalizadas e milhões de faixas.",
        "category": "multimedia",
        "icon_name": "spotify-client",
        "url": "https://www.spotify.com/",
        "license": "custom",
        "repository": "aur",
        "source": "aur",
    },
    {
        "name": "discord",
        "display_name": "Discord",
        "summary": "Comunicação por voz, vídeo e chat em texto",
        "description": "Plataforma de comunicação para comunidades, jogadores e amigos com canais de voz integrados e compartilhamento de tela.",
        "category": "internet",
        "icon_name": "discord",
        "url": "https://discord.com/",
        "license": "custom",
        "repository": "extra",
        "source": "official",
    },
    {
        "name": "blender",
        "display_name": "Blender",
        "summary": "Suíte profissional para modelagem 3D, animação e renderização",
        "description": "Software completo para artistas 3D com pipelines de animação, escultura, simulação física e renderização Cycles/Eevee.",
        "category": "multimedia",
        "icon_name": "blender",
        "url": "https://www.blender.org/",
        "license": "GPL-3.0-or-later",
        "repository": "extra",
        "source": "official",
    },
    {
        "name": "inkscape",
        "display_name": "Inkscape",
        "summary": "Editor de gráficos vetoriais com padrão SVG",
        "description": "Ferramenta de ilustração vetorial para designers, artistas e desenvolvedores com exportação precisa em múltiplos formatos.",
        "category": "multimedia",
        "icon_name": "org.inkscape.Inkscape",
        "url": "https://inkscape.org/",
        "license": "GPL-3.0-or-later",
        "repository": "extra",
        "source": "official",
    },
    {
        "name": "neovim",
        "display_name": "Neovim",
        "summary": "Editor de texto moderno hiper-extensível baseado em Vim",
        "description": "Evolução do Vim com suporte nativo a Lua, Language Server Protocol (LSP), Treesitter e arquitetura moderna.",
        "category": "development",
        "icon_name": "nvim",
        "url": "https://neovim.io/",
        "license": "Apache-2.0",
        "repository": "extra",
        "source": "official",
    },
    {
        "name": "btop",
        "display_name": "Btop",
        "summary": "Monitor de recursos e processos moderno em terminal",
        "description": "Monitor de CPU, memória, discos e rede com interface rica em cores, gráficos reativos e suporte a controle por mouse.",
        "category": "system",
        "icon_name": "utilities-system-monitor",
        "url": "https://github.com/aristocratos/btop",
        "license": "Apache-2.0",
        "repository": "extra",
        "source": "official",
    },
    {
        "name": "fastfetch",
        "display_name": "Fastfetch",
        "summary": "Utilitário ultrarrápido para exibição de informações do sistema",
        "description": "Ferramenta em C que imprime detalhes do hardware, ambiente Hyprland e sistema operacional com logos ASCII e imagens.",
        "category": "system",
        "icon_name": "utilities-terminal",
        "url": "https://github.com/fastfetch-cli/fastfetch",
        "license": "MIT",
        "repository": "extra",
        "source": "official",
    },
    {
        "name": "libreoffice-fresh",
        "display_name": "LibreOffice",
        "summary": "Suíte de produtividade completa para escritório",
        "description": "Pacote abrangente com processador de texto (Writer), planilhas (Calc), apresentações (Impress) e compatibilidade com formatos MS Office.",
        "category": "office",
        "icon_name": "libreoffice-main",
        "url": "https://www.libreoffice.org/",
        "license": "MPL-2.0",
        "repository": "extra",
        "source": "official",
    },
)


class CatalogService:
    """Service providing package discovery, indexing, metadata enrichment and updates."""

    def __init__(self, mock_mode: bool | None = None) -> None:
        self.mock_mode = is_mock_mode() if mock_mode is None else mock_mode
        self._installed_cache: dict[str, PackageItem] = {}
        self._official_repo_cache: dict[str, dict[str, Any]] = {}
        self._desktop_entries: dict[str, dict[str, str]] = {}
        self._appstream_entries: dict[str, dict[str, str]] = {}
        self._aur_cache: dict[str, tuple[float, list[PackageItem]]] = {}
        self._aur_cache_ttl = 120.0  # 2 minutes TTL for search queries

        self._load_appstream_metadata()
        self._load_desktop_entries()
        self.refresh_installed()

    # -------------------------------------------------------------------------
    # Indexing: Local Pacman Database (/var/lib/pacman/local)
    # -------------------------------------------------------------------------

    def refresh_installed(self) -> dict[str, PackageItem]:
        """Read and parse /var/lib/pacman/local/*/desc into PackageItem instances.

        Fast native parser executing in ~50ms on Arch Linux.
        """
        if self.mock_mode:
            self._installed_cache = self._get_mock_installed_packages()
            return self._installed_cache

        local_dir = os.environ.get("REDSHIFT_PACMAN_LOCAL_DIR", DEFAULT_PACMAN_LOCAL_DIR)
        if not os.path.isdir(local_dir):
            logger.warning("Local pacman directory not found: %s", local_dir)
            self._installed_cache = {}
            return self._installed_cache

        installed: dict[str, PackageItem] = {}

        try:
            with os.scandir(local_dir) as it:
                for entry in it:
                    if not entry.is_dir():
                        continue
                    desc_path = os.path.join(entry.path, "desc")
                    if not os.path.isfile(desc_path):
                        continue

                    item = self._parse_pacman_desc_file(desc_path)
                    if item and item.name:
                        installed[item.name] = item
        except Exception as e:
            logger.error("Error reading pacman local database: %s", e)

        self._installed_cache = installed
        return self._installed_cache

    def _parse_pacman_desc_file(self, path: str) -> PackageItem | None:
        """Parse a single pacman desc file into a PackageItem."""
        try:
            with open(path, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
        except OSError:
            return None

        data: dict[str, Any] = {
            "depends": [],
            "optdepends": [],
            "explicit": True,
            "installed": True,
            "source": "official",
            "repository": "local",
        }

        current_tag = ""
        lines = content.splitlines()
        i = 0
        n = len(lines)
        while i < n:
            line = lines[i].strip()
            if line.startswith("%") and line.endswith("%"):
                current_tag = line[1:-1]
                i += 1
                continue

            if not line:
                i += 1
                continue

            if current_tag == "NAME":
                data["name"] = line
            elif current_tag == "VERSION":
                data["version"] = line
                data["installed_version"] = line
            elif current_tag == "DESC":
                data["summary"] = line
                data["description"] = line
            elif current_tag == "URL":
                data["url"] = line
            elif current_tag == "LICENSE":
                data["license"] = line
            elif current_tag == "SIZE":
                data["installed_size"] = format_size(line)
            elif current_tag == "REASON":
                # 1 = installed as dependency, 0 or absent = explicit
                data["explicit"] = line != "1"
            elif current_tag == "DEPENDS":
                data["depends"].append(line)
            elif current_tag == "OPTDEPENDS":
                data["optdepends"].append(line)

            i += 1

        name = data.get("name")
        if not name or not validate_package_name(name):
            return None

        # Enrich with desktop entries or AppStream
        meta = self._get_metadata_for_package(name)
        display_name = meta.get("display_name") or name.capitalize()
        icon_name = meta.get("icon_name") or ""
        summary = meta.get("summary") or data.get("summary", "")
        description = meta.get("description") or data.get("description", "")
        category = meta.get("category") or ""

        if not category or not icon_name:
            inferred_cat, inferred_icon = infer_category_and_icon(name, summary)
            if not category:
                category = inferred_cat
            if not icon_name:
                icon_name = inferred_icon

        data["display_name"] = display_name
        data["icon_name"] = icon_name
        data["category"] = category
        data["summary"] = summary
        data["description"] = description
        data["is_protected"] = is_protected_package(name)

        return PackageItem.from_dict(data)

    # -------------------------------------------------------------------------
    # Metadata Enrichment: AppStream & .desktop files
    # -------------------------------------------------------------------------

    def _load_appstream_metadata(self) -> None:
        """Load AppStream metadata using gi.repository.AppStream if available."""
        if self.mock_mode:
            return

        try:
            import gi
            gi.require_version("AppStream", "1.0")
            from gi.repository import AppStream

            pool = AppStream.Pool()
            pool.load()
            components = pool.get_components()
            total = components.get_size() if hasattr(components, "get_size") else 0

            for i in range(total):
                c = components.index_safe(i)
                if not c:
                    continue
                pkg_name = c.get_pkgname()
                c_id = c.get_id() or ""
                # Use pkgname if present, otherwise strip .desktop suffix
                key = pkg_name or c_id.replace(".desktop", "").lower()
                if not key:
                    continue

                summary = c.get_summary() or ""
                cat_list = c.get_categories() or []
                raw_cat = cat_list[0] if cat_list else ""
                icon_val = ""
                # Get preferred icon
                icons = c.get_icons() if hasattr(c, "get_icons") else []
                if icons:
                    for ic in icons:
                        name_ic = ic.get_name() if hasattr(ic, "get_name") else ""
                        if name_ic:
                            icon_val = name_ic
                            break

                self._appstream_entries[key] = {
                    "display_name": c.get_name() or "",
                    "summary": summary,
                    "description": c.get_description() or summary,
                    "icon_name": icon_val or c_id.replace(".desktop", ""),
                    "category": normalize_category(raw_cat),
                }
            logger.info("Loaded %d AppStream components into catalog cache", len(self._appstream_entries))
        except Exception as e:
            logger.debug("AppStream gi introspection unavailable or error: %s", e)

    def _load_desktop_entries(self) -> None:
        """Parse XDG .desktop application files for icon, name and category mapping."""
        if self.mock_mode:
            return

        desktop_paths = glob.glob("/usr/share/applications/*.desktop")
        user_apps = os.path.expanduser("~/.local/share/applications/*.desktop")
        desktop_paths.extend(glob.glob(user_apps))

        for path in desktop_paths:
            try:
                with open(path, "r", encoding="utf-8", errors="ignore") as f:
                    lines = f.readlines()

                in_entry = False
                entry_data: dict[str, str] = {}
                for line in lines:
                    line = line.strip()
                    if line == "[Desktop Entry]":
                        in_entry = True
                        continue
                    if line.startswith("[") and in_entry:
                        break
                    if in_entry and "=" in line and not line.startswith("#"):
                        k, v = line.split("=", 1)
                        entry_data[k.strip()] = v.strip()

                if entry_data.get("Type") != "Application" or entry_data.get("NoDisplay") == "true":
                    continue

                display_name = entry_data.get("Name", "")
                icon = entry_data.get("Icon", "")
                comment = entry_data.get("Comment", "") or entry_data.get("GenericName", "")
                raw_cat = entry_data.get("Categories", "")
                exec_cmd = entry_data.get("Exec", "").split()[0] if entry_data.get("Exec") else ""
                base_exec = os.path.basename(exec_cmd).lower()
                file_base = os.path.basename(path).replace(".desktop", "").lower()

                meta = {
                    "display_name": display_name,
                    "summary": comment,
                    "description": comment,
                    "icon_name": icon or file_base,
                    "category": normalize_category(raw_cat),
                }

                if file_base:
                    self._desktop_entries[file_base] = meta
                if base_exec and base_exec not in self._desktop_entries:
                    self._desktop_entries[base_exec] = meta
            except Exception:
                continue

    def _get_metadata_for_package(self, pkg_name: str) -> dict[str, str]:
        """Lookup metadata in AppStream and desktop files with fallbacks."""
        key = pkg_name.lower()
        if key in self._appstream_entries:
            return self._appstream_entries[key]
        if key in self._desktop_entries:
            return self._desktop_entries[key]
        return {}

    # -------------------------------------------------------------------------
    # Public Query Methods
    # -------------------------------------------------------------------------

    def get_installed_packages(self, explicit_only: bool = False) -> list[PackageItem]:
        """Return list of all locally installed packages."""
        if not self._installed_cache:
            self.refresh_installed()
        packages = list(self._installed_cache.values())
        if explicit_only:
            packages = [p for p in packages if p.explicit]
        return sorted(packages, key=lambda x: (x.display_name or x.name).lower())

    def get_package(self, name: str, repository: str = "") -> PackageItem | None:
        """Find a package by name from installed, featured or repository caches."""
        if not name:
            return None
        clean_name = name.strip()

        # Check installed first
        if clean_name in self._installed_cache:
            return self._installed_cache[clean_name]

        # Check featured catalog
        for feat in self.get_featured_packages():
            if feat.name == clean_name:
                return feat

        # Check official repo cache
        if clean_name in self._official_repo_cache:
            repo_info = self._official_repo_cache[clean_name]
            meta = self._get_metadata_for_package(clean_name)
            cat, icon = infer_category_and_icon(clean_name, meta.get("summary", ""))
            return PackageItem(
                name=clean_name,
                display_name=meta.get("display_name") or clean_name,
                summary=meta.get("summary", ""),
                description=meta.get("description", ""),
                version=repo_info.get("version", ""),
                repository=repo_info.get("repository", "extra"),
                source="official",
                installed=False,
                category=meta.get("category") or cat,
                icon_name=meta.get("icon_name") or icon,
                is_protected=is_protected_package(clean_name),
            )

        # Fallback query from AUR if repository is 'aur'
        if repository == "aur":
            aur_results = self.search_aur(clean_name, limit=5)
            for res in aur_results:
                if res.name == clean_name:
                    return res

        return None

    def get_featured_packages(self) -> list[PackageItem]:
        """Return curated list of featured applications synchronized with system status."""
        items: list[PackageItem] = []
        for feat in FEATURED_PACKAGES_METADATA:
            name = feat["name"]
            is_inst = name in self._installed_cache
            inst_item = self._installed_cache.get(name)

            pkg = PackageItem(
                name=name,
                display_name=feat["display_name"],
                summary=feat["summary"],
                description=feat["description"],
                version=inst_item.version if (inst_item and inst_item.version) else "available",
                installed_version=inst_item.installed_version if inst_item else "",
                repository=feat["repository"],
                source=feat["source"],
                installed=is_inst,
                explicit=inst_item.explicit if inst_item else False,
                category=feat["category"],
                icon_name=feat["icon_name"],
                installed_size=inst_item.installed_size if inst_item else "",
                license=feat.get("license", ""),
                url=feat.get("url", ""),
                is_protected=is_protected_package(name),
            )
            items.append(pkg)
        return items

    # -------------------------------------------------------------------------
    # Updates: checkupdates + yay -Qua
    # -------------------------------------------------------------------------

    def check_updates(self) -> list[PackageItem]:
        """Check for pending system updates using checkupdates and yay.

        Never touches pacman lock or requires root permissions.
        """
        if self.mock_mode:
            return self._get_mock_updates()

        updates: list[PackageItem] = []
        seen: set[str] = set()

        # 1. Official updates via checkupdates
        try:
            res = subprocess.run(
                ["/usr/bin/checkupdates"],
                capture_output=True,
                text=True,
                timeout=15,
                check=False,
            )
            # Exit code 0 = updates found, exit code 2 = no updates
            if res.returncode == 0 and res.stdout:
                for line in res.stdout.splitlines():
                    parts = line.strip().split()
                    # Expected format: pkgname old_ver -> new_ver
                    if len(parts) >= 4 and parts[2] == "->":
                        pkgname, old_ver, _, new_ver = parts[0], parts[1], parts[2], parts[3]
                        if not validate_package_name(pkgname):
                            continue
                        seen.add(pkgname)
                        inst_item = self._installed_cache.get(pkgname)
                        meta = self._get_metadata_for_package(pkgname)
                        cat, icon = infer_category_and_icon(pkgname, inst_item.summary if inst_item else "")

                        updates.append(
                            PackageItem(
                                name=pkgname,
                                display_name=inst_item.display_name if inst_item else (meta.get("display_name") or pkgname),
                                summary=inst_item.summary if inst_item else meta.get("summary", ""),
                                description=inst_item.description if inst_item else meta.get("description", ""),
                                version=new_ver,
                                installed_version=old_ver,
                                repository="official",
                                source="official",
                                installed=True,
                                update_available=True,
                                category=inst_item.category if inst_item else (meta.get("category") or cat),
                                icon_name=inst_item.icon_name if inst_item else (meta.get("icon_name") or icon),
                                installed_size=inst_item.installed_size if inst_item else "",
                                is_protected=is_protected_package(pkgname),
                            )
                        )
        except Exception as e:
            logger.warning("checkupdates failed or timed out: %s", e)

        # 2. AUR updates via yay -Qua
        try:
            res_aur = subprocess.run(
                ["/usr/bin/yay", "-Qua", "--color=never"],
                capture_output=True,
                text=True,
                timeout=15,
                check=False,
            )
            if res_aur.returncode == 0 and res_aur.stdout:
                for line in res_aur.stdout.splitlines():
                    parts = line.strip().split()
                    if len(parts) >= 4 and parts[2] == "->":
                        pkgname, old_ver, _, new_ver = parts[0], parts[1], parts[2], parts[3]
                        if not validate_package_name(pkgname) or pkgname in seen:
                            continue
                        seen.add(pkgname)
                        inst_item = self._installed_cache.get(pkgname)
                        meta = self._get_metadata_for_package(pkgname)
                        cat, icon = infer_category_and_icon(pkgname, inst_item.summary if inst_item else "")

                        updates.append(
                            PackageItem(
                                name=pkgname,
                                display_name=inst_item.display_name if inst_item else (meta.get("display_name") or pkgname),
                                summary=inst_item.summary if inst_item else meta.get("summary", ""),
                                description=inst_item.description if inst_item else meta.get("description", ""),
                                version=new_ver,
                                installed_version=old_ver,
                                repository="aur",
                                source="aur",
                                installed=True,
                                update_available=True,
                                category=inst_item.category if inst_item else (meta.get("category") or cat),
                                icon_name=inst_item.icon_name if inst_item else (meta.get("icon_name") or icon),
                                installed_size=inst_item.installed_size if inst_item else "",
                                is_protected=is_protected_package(pkgname),
                            )
                        )
        except Exception as e:
            logger.debug("yay -Qua check unavailable: %s", e)

        return updates

    # -------------------------------------------------------------------------
    # AUR: RPC Search & PKGBUILD Inspection
    # -------------------------------------------------------------------------

    def search_aur(self, query: str, limit: int = 30) -> list[PackageItem]:
        """Query AUR RPC v5 with debounced memory caching (TTL 120s)."""
        clean_query = query.strip()
        if not clean_query:
            return []

        # Check mock mode
        if self.mock_mode:
            return self._get_mock_aur_results(clean_query, limit)

        # Check memory cache
        cache_key = clean_query.lower()
        now = time.time()
        if cache_key in self._aur_cache:
            ts, cached_items = self._aur_cache[cache_key]
            if now - ts < self._aur_cache_ttl:
                return cached_items

        url = AUR_RPC_SEARCH_URL.format(query=urllib.parse.quote(clean_query))
        req = urllib.request.Request(url, headers={"User-Agent": "RedshiftStore/1.0"})

        items: list[PackageItem] = []
        try:
            with urllib.request.urlopen(req, timeout=5) as resp:
                data = json.loads(resp.read().decode("utf-8", errors="replace"))
                results = data.get("results", [])

                for r in results:
                    name = r.get("Name", "")
                    if not validate_package_name(name):
                        continue

                    desc = r.get("Description") or ""
                    version = r.get("Version") or ""
                    pkg_url = r.get("URL") or ""
                    maintainer = r.get("Maintainer") or ""
                    votes = int(r.get("NumVotes") or 0)
                    pop = float(r.get("Popularity") or 0.0)

                    inst_item = self._installed_cache.get(name)
                    is_inst = inst_item is not None
                    meta = self._get_metadata_for_package(name)
                    cat, icon = infer_category_and_icon(name, desc)

                    pkg = PackageItem(
                        name=name,
                        display_name=meta.get("display_name") or name,
                        summary=desc,
                        description=desc,
                        version=version,
                        installed_version=inst_item.installed_version if inst_item else "",
                        repository="aur",
                        source="aur",
                        installed=is_inst,
                        explicit=inst_item.explicit if inst_item else False,
                        category=meta.get("category") or cat,
                        icon_name=meta.get("icon_name") or icon,
                        url=pkg_url,
                        votes=votes,
                        popularity=pop,
                        maintainer=maintainer,
                        is_protected=is_protected_package(name),
                    )
                    items.append(pkg)
        except Exception as e:
            logger.warning("AUR RPC query error for %r: %s", clean_query, e)

        # Sort by popularity descending
        items.sort(key=lambda x: (x.popularity, x.votes), reverse=True)
        items = items[:limit]
        self._aur_cache[cache_key] = (now, items)
        return items

    def fetch_aur_pkgbuild(self, pkg_name: str) -> str:
        """Fetch and return AUR PKGBUILD script text for user security review."""
        clean_name = ensure_valid_package_name(pkg_name)

        if self.mock_mode:
            return self._get_mock_pkgbuild(clean_name)

        url = AUR_CGIT_PKGBUILD_URL.format(pkg=urllib.parse.quote(clean_name))
        req = urllib.request.Request(url, headers={"User-Agent": "RedshiftStore/1.0"})

        try:
            with urllib.request.urlopen(req, timeout=5) as resp:
                content = resp.read().decode("utf-8", errors="replace")
                return content
        except Exception as e:
            logger.warning("Error fetching PKGBUILD for %r: %s", clean_name, e)
            return f"# Redshift Store: Failed to fetch PKGBUILD for {clean_name}\n# Error: {e}"

    # -------------------------------------------------------------------------
    # Search & Filtering
    # -------------------------------------------------------------------------

    def search(
        self,
        query: str = "",
        source_filter: str = "all",
        category_filter: str = "all",
        limit: int = 50,
    ) -> list[PackageItem]:
        """Search catalog with text query, source filter and category filter."""
        clean_query = query.strip().lower()
        results: list[PackageItem] = []
        seen_names: set[str] = set()

        # 1. Search in featured packages
        for feat in self.get_featured_packages():
            if not self._matches_filters(feat, clean_query, source_filter, category_filter):
                continue
            if feat.name not in seen_names:
                seen_names.add(feat.name)
                results.append(feat)

        # 2. Search in installed packages
        for inst in self.get_installed_packages():
            if not self._matches_filters(inst, clean_query, source_filter, category_filter):
                continue
            if inst.name not in seen_names:
                seen_names.add(inst.name)
                results.append(inst)

        # 3. Search in AUR if requested
        if source_filter in ("all", "aur") and clean_query:
            aur_items = self.search_aur(clean_query, limit=30)
            for aur_pkg in aur_items:
                if not self._matches_filters(aur_pkg, clean_query, source_filter, category_filter):
                    continue
                if aur_pkg.name not in seen_names:
                    seen_names.add(aur_pkg.name)
                    results.append(aur_pkg)

        # Sort: installed first, then matching display_name, then by popularity
        results.sort(
            key=lambda x: (
                not x.installed,
                not (clean_query and clean_query in (x.display_name or x.name).lower()),
                -x.popularity,
                (x.display_name or x.name).lower(),
            )
        )
        return results[:limit]

    def _matches_filters(
        self,
        pkg: PackageItem,
        query: str,
        source_filter: str,
        category_filter: str,
    ) -> bool:
        """Check if package matches query string and active filters."""
        if source_filter != "all" and pkg.source != source_filter:
            return False

        if category_filter != "all" and pkg.category != category_filter:
            return False

        if not query:
            return True

        text_to_search = f"{pkg.name} {pkg.display_name} {pkg.summary} {pkg.description}".lower()
        return query in text_to_search

    # -------------------------------------------------------------------------
    # Mock Data Fixtures (REDSHIFT_STORE_MOCK=1)
    # -------------------------------------------------------------------------

    def _get_mock_installed_packages(self) -> dict[str, PackageItem]:
        """Return deterministic mock installed packages for sandbox tests."""
        raw_list = [
            PackageItem(
                name="firefox",
                display_name="Firefox",
                summary="Navegador web rápido, privado e seguro",
                version="134.0-1",
                installed_version="134.0-1",
                repository="extra",
                source="official",
                installed=True,
                explicit=True,
                category="internet",
                icon_name="firefox",
                installed_size="250.0 MiB",
            ),
            PackageItem(
                name="kitty",
                display_name="Kitty",
                summary="Emulador de terminal moderno acelerado por GPU",
                version="0.39.0-1",
                installed_version="0.39.0-1",
                repository="extra",
                source="official",
                installed=True,
                explicit=True,
                category="system",
                icon_name="kitty",
                installed_size="42.5 MiB",
            ),
            PackageItem(
                name="visual-studio-code-bin",
                display_name="Visual Studio Code",
                summary="Editor de código avançado",
                version="1.143.0-1",
                installed_version="1.143.0-1",
                repository="aur",
                source="aur",
                installed=True,
                explicit=True,
                category="development",
                icon_name="visual-studio-code",
                installed_size="350.0 MiB",
            ),
            PackageItem(
                name="pacman",
                display_name="Pacman",
                summary="Gerenciador de pacotes do Arch Linux",
                version="7.1.0-3",
                installed_version="7.1.0-3",
                repository="core",
                source="official",
                installed=True,
                explicit=False,
                category="system",
                icon_name="applications-system",
                is_protected=True,
            ),
            PackageItem(
                name="hyprland",
                display_name="Hyprland",
                summary="Compositor Wayland dinâmico",
                version="0.47.0-1",
                installed_version="0.47.0-1",
                repository="extra",
                source="official",
                installed=True,
                explicit=True,
                category="system",
                icon_name="preferences-system-windows",
                is_protected=True,
            ),
        ]
        return {p.name: p for p in raw_list}

    def _get_mock_updates(self) -> list[PackageItem]:
        """Return deterministic mock updates for testing."""
        return [
            PackageItem(
                name="firefox",
                display_name="Firefox",
                summary="Navegador web rápido, privado e seguro",
                version="135.0-1",
                installed_version="134.0-1",
                repository="extra",
                source="official",
                installed=True,
                update_available=True,
                category="internet",
                icon_name="firefox",
                installed_size="252.0 MiB",
            ),
            PackageItem(
                name="visual-studio-code-bin",
                display_name="Visual Studio Code",
                summary="Editor de código avançado",
                version="1.144.0-1",
                installed_version="1.143.0-1",
                repository="aur",
                source="aur",
                installed=True,
                update_available=True,
                category="development",
                icon_name="visual-studio-code",
                installed_size="355.0 MiB",
            ),
        ]

    def _get_mock_aur_results(self, query: str, limit: int) -> list[PackageItem]:
        """Return deterministic mock AUR search results."""
        candidates = [
            PackageItem(
                name="spotify",
                display_name="Spotify",
                summary="Cliente de streaming de músicas Spotify",
                version="1.2.53-1",
                repository="aur",
                source="aur",
                category="multimedia",
                icon_name="spotify-client",
                votes=3450,
                popularity=25.4,
                maintainer="alucryd",
            ),
            PackageItem(
                name="visual-studio-code-bin",
                display_name="Visual Studio Code",
                summary="Editor de código Microsoft VSCode",
                version="1.144.0-1",
                repository="aur",
                source="aur",
                category="development",
                icon_name="visual-studio-code",
                votes=1711,
                popularity=13.01,
                maintainer="bboozzoo",
            ),
            PackageItem(
                name="zen-browser-bin",
                display_name="Zen Browser",
                summary="Navegador focado em abas verticais e privacidade baseado em Firefox",
                version="1.0.2-1",
                repository="aur",
                source="aur",
                category="internet",
                icon_name="zen-browser",
                votes=420,
                popularity=9.8,
                maintainer="zen-team",
            ),
            PackageItem(
                name="paru",
                display_name="Paru",
                summary="Feature packed AUR helper in Rust",
                version="2.0.4-1",
                repository="aur",
                source="aur",
                category="system",
                icon_name="utilities-terminal",
                votes=2300,
                popularity=18.5,
                maintainer="morganamilo",
            ),
        ]
        q = query.lower()
        filtered = [c for c in candidates if q in c.name.lower() or q in c.summary.lower()]
        return filtered[:limit]

    def _get_mock_pkgbuild(self, pkg_name: str) -> str:
        """Return safe mock PKGBUILD script for testing."""
        return f"""# Maintainer: Redshift OS Mock <maintainer@redshift.internal>
pkgname={pkg_name}
pkgver=1.0.0
pkgrel=1
pkgdesc="Mock package for {pkg_name} in Redshift Store"
arch=('x86_64')
url="https://aur.archlinux.org/packages/{pkg_name}"
license=('GPL-3.0-or-later')
depends=('glibc')
source=("https://example.com/{pkg_name}-1.0.0.tar.gz")
sha256sums=('SKIP')

package() {{
    mkdir -p "$pkgdir/usr/share/doc/$pkgname"
    echo "Installed by Redshift Store Mock" > "$pkgdir/usr/share/doc/$pkgname/README"
}}
"""
