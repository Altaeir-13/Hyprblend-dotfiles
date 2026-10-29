"""Catalog and package indexing service for Redshift Store.

Provides indexing of locally installed packages (/var/lib/pacman/local),
official pacman sync repositories (/var/lib/pacman/sync/*.db),
AppStream metadata (gi and raw XML/XML.GZ parser), desktop entries,
curated featured packages, update checking (checkupdates + yay -Qua),
AUR discovery & search with disk/memory caching, pkgstats community popularity,
privacy-respecting local personalization, and multi-tier relevance ranking.
Supports offline/mock execution when REDSHIFT_STORE_MOCK=1 or REDSHIFT_STORE_SANDBOX=1.
"""

from __future__ import annotations

import glob
import gzip
import json
import logging
import os
import re
import subprocess
import tarfile
import threading
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from typing import Any, Callable, Sequence

from .models import PackageItem
from .security import (
    DEFAULT_PACMAN_LOCK_PATH,
    alpm_vercmp,
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
    "design",
    "utilities",
    "system",
    "office",
)

DEFAULT_PACMAN_LOCAL_DIR = "/var/lib/pacman/local"
DEFAULT_PACMAN_SYNC_DIR = "/var/lib/pacman/sync"
AUR_RPC_SEARCH_URL = "https://aur.archlinux.org/rpc/v5/search/{query}"
AUR_RPC_INFO_URL = "https://aur.archlinux.org/rpc/v5/info"
AUR_CGIT_PKGBUILD_URL = "https://aur.archlinux.org/cgit/aur.git/plain/PKGBUILD?h={pkg}"
PKGSTATS_API_URL = "https://pkgstats.archlinux.de/api/packages/{pkg}"

# Arch Linux pkgstats baseline percentages
PKGSTATS_BASELINE: dict[str, float] = {
    "git": 93.4,
    "python": 98.7,
    "curl": 97.5,
    "firefox": 69.13,
    "bash": 99.8,
    "vim": 61.2,
    "neovim": 44.2,
    "vlc": 48.5,
    "mpv": 52.1,
    "steam": 45.9,
    "fastfetch": 42.1,
    "gimp": 41.8,
    "docker": 41.2,
    "libreoffice-fresh": 39.7,
    "discord": 38.2,
    "btop": 37.9,
    "obs-studio": 36.4,
    "chromium": 35.6,
    "kitty": 34.6,
    "qbittorrent": 33.8,
    "alacritty": 32.1,
    "telegram-desktop": 31.5,
    "thunderbird": 29.4,
    "gparted": 28.7,
    "keepassxc": 28.1,
    "inkscape": 27.3,
    "audacity": 26.7,
    "okular": 25.3,
    "code": 24.8,
    "lutris": 24.5,
    "flameshot": 22.9,
    "krita": 21.4,
    "kdenlive": 19.8,
    "blender": 18.81,
    "remmina": 16.5,
    "dbeaver": 12.4,
    "zed": 11.2,
    "timeshift": 15.4,
    "filezilla": 14.2,
    "wireshark-qt": 13.8,
    "geany": 12.1,
    "darktable": 8.7,
    "freecad": 7.9,
    "scribus": 6.4,
    "retroarch": 11.5,
    "supertuxkart": 9.2,
    "0ad": 8.5,
    "dolphin-emu": 10.3,
    "handbrake": 14.1,
    "strawberry": 7.4,
    "easyeffects": 17.6,
    "bitwarden": 16.2,
    "syncthing": 18.9,
    "bleachbit": 9.5,
}

# Rich metadata catalog of >80 real official packages
KNOWN_APPLICATIONS_CATALOG: dict[str, dict[str, Any]] = {
    # Internet
    "firefox": {
        "display_name": "Firefox",
        "summary": "Navegador web rápido, privado e seguro",
        "description": "Mozilla Firefox é um navegador livre e de código aberto com foco em privacidade, extensões completas e renderização moderna.",
        "category": "internet",
        "icon_name": "firefox",
        "repository": "extra",
        "source": "official",
        "url": "https://www.mozilla.org/firefox/",
        "license": "MPL-2.0",
        "popularity": 69.13,
    },
    "chromium": {
        "display_name": "Chromium",
        "summary": "Navegador web de código aberto base do Chrome",
        "description": "Projeto de navegador livre que alimenta o Google Chrome, com suporte a tecnologias web de última geração e extensões WebStore.",
        "category": "internet",
        "icon_name": "chromium",
        "repository": "extra",
        "source": "official",
        "url": "https://www.chromium.org/chromium-projects/",
        "license": "BSD-3-Clause",
        "popularity": 35.6,
    },
    "vivaldi": {
        "display_name": "Vivaldi",
        "summary": "Navegador altamente personalizável com painéis laterais",
        "description": "Navegador rico em recursos com bloqueador nativo de anúncios, cliente de email, painéis web e controle avançado de abas.",
        "category": "internet",
        "icon_name": "vivaldi",
        "repository": "extra",
        "source": "official",
        "url": "https://vivaldi.com/",
        "license": "custom",
        "popularity": 14.5,
    },
    "torbrowser-launcher": {
        "display_name": "Tor Browser Launcher",
        "summary": "Navegador anônimo com roteamento em cebola",
        "description": "Gerenciador e iniciador do Tor Browser para navegação segura e anônima através da rede Tor descentralizada.",
        "category": "internet",
        "icon_name": "torbrowser",
        "repository": "extra",
        "source": "official",
        "url": "https://github.com/micahflee/torbrowser-launcher",
        "license": "MIT",
        "popularity": 12.3,
    },
    "thunderbird": {
        "display_name": "Thunderbird",
        "summary": "Cliente completo de e-mail, calendário e contatos",
        "description": "Cliente de mensagens robusto da Mozilla com suporte a múltiplos protocolos IMAP/POP3, criptografia OpenPGP e feeds RSS.",
        "category": "internet",
        "icon_name": "thunderbird",
        "repository": "extra",
        "source": "official",
        "url": "https://www.thunderbird.net/",
        "license": "MPL-2.0",
        "popularity": 29.4,
    },
    "telegram-desktop": {
        "display_name": "Telegram Desktop",
        "summary": "Mensageiro instantâneo sincronizado em nuvem e canais",
        "description": "Aplicativo oficial para desktop do Telegram, com suporte a chamadas de voz/vídeo, grupos e compartilhamento veloz de arquivos de até 2GB.",
        "category": "internet",
        "icon_name": "telegram",
        "repository": "extra",
        "source": "official",
        "url": "https://desktop.telegram.org/",
        "license": "GPL-3.0-only",
        "popularity": 31.5,
    },
    "discord": {
        "display_name": "Discord",
        "summary": "Comunicação por voz, vídeo e chat para comunidades",
        "description": "Plataforma de voz sobre IP e mensagens projetada para grupos, servidores de games, trabalho em equipe e compartilhamento de tela.",
        "category": "internet",
        "icon_name": "discord",
        "repository": "extra",
        "source": "official",
        "url": "https://discord.com/",
        "license": "custom",
        "popularity": 38.2,
    },
    "signal-desktop": {
        "display_name": "Signal",
        "summary": "Mensageiro com criptografia ponta a ponta intransponível",
        "description": "Comunicação privada por excelência com protocolo de criptografia Signal de última geração sem rastreamento de metadados.",
        "category": "internet",
        "icon_name": "signal-desktop",
        "repository": "extra",
        "source": "official",
        "url": "https://signal.org/",
        "license": "AGPL-3.0-only",
        "popularity": 18.2,
    },
    "element-desktop": {
        "display_name": "Element",
        "summary": "Cliente seguro e descentralizado para a rede Matrix",
        "description": "Mensageiro Matrix criptografado com canais descentralizados, pontes para outras redes e conferências por vídeo.",
        "category": "internet",
        "icon_name": "element-desktop",
        "repository": "extra",
        "source": "official",
        "url": "https://element.io/",
        "license": "Apache-2.0",
        "popularity": 9.8,
    },
    "neochat": {
        "display_name": "NeoChat",
        "summary": "Cliente Matrix nativo para o ambiente KDE e Wayland",
        "description": "Cliente Matrix moderno construído com Kirigami, totalmente integrado aos padrões visuais e notificações do Linux.",
        "category": "internet",
        "icon_name": "org.kde.neochat",
        "repository": "extra",
        "source": "official",
        "url": "https://apps.kde.org/neochat/",
        "license": "GPL-3.0-or-later",
        "popularity": 6.4,
    },
    "fractal": {
        "display_name": "Fractal",
        "summary": "Cliente Matrix elegante construído em Rust e GTK4",
        "description": "Mensageiro para Matrix moderno e minimalista com renderização fluida em Wayland e suporte a criptografia avançada.",
        "category": "internet",
        "icon_name": "org.gnome.Fractal",
        "repository": "extra",
        "source": "official",
        "url": "https://gitlab.gnome.org/World/fractal",
        "license": "GPL-3.0-or-later",
        "popularity": 5.7,
    },
    "qbittorrent": {
        "display_name": "qBittorrent",
        "summary": "Cliente BitTorrent livre sem anúncios e com motor de busca",
        "description": "Alternativa leve e confiável ao uTorrent com motor de busca de torrents integrado, controle de banda e interface web.",
        "category": "internet",
        "icon_name": "org.qbittorrent.qBittorrent",
        "repository": "extra",
        "source": "official",
        "url": "https://www.qbittorrent.org/",
        "license": "GPL-2.0-or-later",
        "popularity": 33.8,
    },
    "transmission-gtk": {
        "display_name": "Transmission",
        "summary": "Cliente BitTorrent simples, rápido e econômico",
        "description": "Cliente BitTorrent minimalista projetado para baixo consumo de memória RAM e recursos da CPU com integração nativa.",
        "category": "internet",
        "icon_name": "transmission",
        "repository": "extra",
        "source": "official",
        "url": "https://transmissionbt.com/",
        "license": "GPL-2.0-or-later",
        "popularity": 21.6,
    },
    "filezilla": {
        "display_name": "FileZilla",
        "summary": "Cliente gráfico de transferência de arquivos FTP, FTPS e SFTP",
        "description": "Solução estável para gerenciamento e transferência de arquivos em servidores remotos com gerenciador de sites e fila de transferências.",
        "category": "internet",
        "icon_name": "filezilla",
        "repository": "extra",
        "source": "official",
        "url": "https://filezilla-project.org/",
        "license": "GPL-2.0-or-later",
        "popularity": 14.2,
    },
    "remmina": {
        "display_name": "Remmina",
        "summary": "Cliente versátil para acesso a desktops remotos (RDP, VNC, SSH)",
        "description": "Ferramenta de desktop remoto com suporte a protocolos RDP, VNC, SPICE, SSH e gerenciamento centralizado de conexões.",
        "category": "internet",
        "icon_name": "org.remmina.Remmina",
        "repository": "extra",
        "source": "official",
        "url": "https://remmina.org/",
        "license": "GPL-2.0-or-later",
        "popularity": 16.5,
    },
    "wireshark-qt": {
        "display_name": "Wireshark",
        "summary": "Analisador profissional de protocolos e tráfego de rede",
        "description": "Ferramenta padrão da indústria para captura, inspeção detalhada e diagnóstico de pacotes em redes locais e virtuais.",
        "category": "internet",
        "icon_name": "wireshark",
        "repository": "extra",
        "source": "official",
        "url": "https://www.wireshark.org/",
        "license": "GPL-2.0-or-later",
        "popularity": 13.8,
    },

    # Development
    "neovim": {
        "display_name": "Neovim",
        "summary": "Editor de texto moderno hiper-extensível baseado em Vim",
        "description": "Evolução moderna do Vim com suporte nativo a Lua, Language Server Protocol (LSP), Treesitter e alta performance.",
        "category": "development",
        "icon_name": "nvim",
        "repository": "extra",
        "source": "official",
        "url": "https://neovim.io/",
        "license": "Apache-2.0",
        "popularity": 44.2,
    },
    "code": {
        "display_name": "Code - OSS",
        "summary": "Versão livre e de código aberto do Visual Studio Code",
        "description": "Compilação de código aberto da distribuição do VS Code sem telemetria proprietária e com amplo ecossistema de extensões.",
        "category": "development",
        "icon_name": "com.visualstudio.code.oss",
        "repository": "extra",
        "source": "official",
        "url": "https://github.com/microsoft/vscode",
        "license": "MIT",
        "popularity": 24.8,
    },
    "zed": {
        "display_name": "Zed",
        "summary": "Editor de código de alta performance acelerado por GPU",
        "description": "Editor ultrarrápido escrito em Rust com edição colaborativa multiplayer, terminal integrado e suporte a LSP nativo.",
        "category": "development",
        "icon_name": "dev.zed.Zed",
        "repository": "extra",
        "source": "official",
        "url": "https://zed.dev/",
        "license": "GPL-3.0-only",
        "popularity": 11.2,
    },
    "qtcreator": {
        "display_name": "Qt Creator",
        "summary": "Ambiente de desenvolvimento integrado profissional para C++ e QML",
        "description": "IDE completa e multiplataforma adaptada para criação de interfaces modernas com Qt, QML, C++, CMake e Python.",
        "category": "development",
        "icon_name": "org.qt-project.qtcreator",
        "repository": "extra",
        "source": "official",
        "url": "https://www.qt.io/product/development-tools",
        "license": "GPL-3.0-only",
        "popularity": 9.4,
    },
    "gnome-builder": {
        "display_name": "GNOME Builder",
        "summary": "IDE especializada para desenvolvimento de aplicativos Linux",
        "description": "Ambiente de desenvolvimento para criação de aplicativos GTK4, Flatpak e C/Rust com depuração integrada.",
        "category": "development",
        "icon_name": "org.gnome.Builder",
        "repository": "extra",
        "source": "official",
        "url": "https://wiki.gnome.org/Apps/Builder",
        "license": "GPL-3.0-or-later",
        "popularity": 5.1,
    },
    "kate": {
        "display_name": "Kate",
        "summary": "Editor de texto avançado com abas, terminal e LSP",
        "description": "Editor de texto poderoso do projeto KDE com realce de sintaxe em centenas de linguagens, suporte a LSP e projetos integrados.",
        "category": "development",
        "icon_name": "org.kde.kate",
        "repository": "extra",
        "source": "official",
        "url": "https://kate-editor.org/",
        "license": "LGPL-2.0-or-later",
        "popularity": 18.5,
    },
    "geany": {
        "display_name": "Geany",
        "summary": "IDE leve e ágil baseada em GTK",
        "description": "Editor de código leve com características de IDE, auto-completar básico, árvore de símbolos e execução direta de programas.",
        "category": "development",
        "icon_name": "geany",
        "repository": "extra",
        "source": "official",
        "url": "https://www.geany.org/",
        "license": "GPL-2.0-or-later",
        "popularity": 12.1,
    },
    "meld": {
        "display_name": "Meld",
        "summary": "Ferramenta visual para comparação de arquivos e controle de versão",
        "description": "Utilitário gráfico para comparar arquivos, diretórios e repositórios Git, facilitando a resolução de conflitos e merge.",
        "category": "development",
        "icon_name": "org.gnome.Meld",
        "repository": "extra",
        "source": "official",
        "url": "https://meldmerge.org/",
        "license": "GPL-2.0-or-later",
        "popularity": 17.8,
    },
    "git": {
        "display_name": "Git",
        "summary": "Sistema de controle de versão distribuído mais utilizado do mundo",
        "description": "Controle de versão rápido e distribuído projetado para lidar com tudo, desde projetos pequenos a imensos com velocidade e eficiência.",
        "category": "development",
        "icon_name": "git",
        "repository": "extra",
        "source": "official",
        "url": "https://git-scm.com/",
        "license": "GPL-2.0-only",
        "popularity": 93.4,
    },
    "lazygit": {
        "display_name": "LazyGit",
        "summary": "Interface em terminal rápida e intuitiva para comandos Git",
        "description": "Interface TUI rica para Git que torna commits, rebase interativo, branches e visualização de diffs uma tarefa instantânea.",
        "category": "development",
        "icon_name": "utilities-terminal",
        "repository": "extra",
        "source": "official",
        "url": "https://github.com/jesseduffield/lazygit",
        "license": "MIT",
        "popularity": 22.3,
    },
    "docker": {
        "display_name": "Docker",
        "summary": "Plataforma de virtualização leve em containers de software",
        "description": "Ferramenta para empacotar, distribuir e executar aplicativos dentro de containers isolados em qualquer ambiente Linux.",
        "category": "development",
        "icon_name": "docker",
        "repository": "extra",
        "source": "official",
        "url": "https://www.docker.com/",
        "license": "Apache-2.0",
        "popularity": 41.2,
    },
    "podman": {
        "display_name": "Podman",
        "summary": "Motor de containers sem daemon e sem privilégios de root",
        "description": "Substituto direto do Docker com segurança aprimorada, suporte a pods no estilo Kubernetes e arquitetura sem daemon permanente.",
        "category": "development",
        "icon_name": "podman",
        "repository": "extra",
        "source": "official",
        "url": "https://podman.io/",
        "license": "Apache-2.0",
        "popularity": 19.8,
    },
    "dbeaver": {
        "display_name": "DBeaver",
        "summary": "Gerenciador universal e profissional de bancos de dados SQL/NoSQL",
        "description": "Ferramenta gráfica com suporte a PostgreSQL, MySQL, SQLite, Oracle, Redis e dezenas de outros bancos de dados relacionais e em nuvem.",
        "category": "development",
        "icon_name": "dbeaver",
        "repository": "extra",
        "source": "official",
        "url": "https://dbeaver.io/",
        "license": "Apache-2.0",
        "popularity": 12.4,
    },

    # Games
    "steam": {
        "display_name": "Steam",
        "summary": "Plataforma líder para jogos e entretenimento digital",
        "description": "Cliente Steam oficial com integração nativa ao Proton/Vulkan para rodar milhares de jogos Windows no Redshift OS.",
        "category": "games",
        "icon_name": "steam",
        "repository": "multilib",
        "source": "official",
        "url": "https://steampowered.com/",
        "license": "custom",
        "popularity": 45.9,
    },
    "lutris": {
        "display_name": "Lutris",
        "summary": "Gerenciador centralizado de jogos para PC, Wine e emuladores",
        "description": "Plataforma livre para organizar, configurar e executar jogos de múltiplas fontes como GOG, Epic Games e títulos independentes.",
        "category": "games",
        "icon_name": "net.lutris.Lutris",
        "repository": "extra",
        "source": "official",
        "url": "https://lutris.net/",
        "license": "GPL-3.0-or-later",
        "popularity": 24.5,
    },
    "mangohud": {
        "display_name": "MangoHud",
        "summary": "Overlay de telemetria de FPS, temperatura e uso de CPU/GPU",
        "description": "Exibição sobreposta em jogos Vulkan e OpenGL para monitoramento em tempo real de taxas de quadros, temperaturas e consumo.",
        "category": "games",
        "icon_name": "applications-games",
        "repository": "extra",
        "source": "official",
        "url": "https://github.com/flightlessmango/MangoHud",
        "license": "MIT",
        "popularity": 22.1,
    },
    "gamemode": {
        "display_name": "GameMode",
        "summary": "Otimizador dinâmico de performance do sistema para jogos",
        "description": "Serviço que ajusta dinamicamente governador de CPU, prioridade de agendamento e GPU para maximizar o desempenho em jogos.",
        "category": "games",
        "icon_name": "applications-system",
        "repository": "extra",
        "source": "official",
        "url": "https://github.com/FeralInteractive/gamemode",
        "license": "BSD-3-Clause",
        "popularity": 27.8,
    },
    "goverlay": {
        "display_name": "GOverlay",
        "summary": "Configurador visual para MangoHud, vkBasalt e replay-sorcery",
        "description": "Interface gráfica para personalizar facilmente posição, cores e métricas do MangoHud e efeitos visuais nos seus jogos.",
        "category": "games",
        "icon_name": "io.github.benjamimgois.goverlay",
        "repository": "extra",
        "source": "official",
        "url": "https://github.com/benjamimgois/goverlay",
        "license": "GPL-3.0-or-later",
        "popularity": 8.9,
    },
    "retroarch": {
        "display_name": "RetroArch",
        "summary": "Frontend universal para emuladores e motores de jogos clássicos",
        "description": "Plataforma modular para emulação de dezenas de consoles de videogame clássicos com filtros visuais, netplay e retroconquistas.",
        "category": "games",
        "icon_name": "org.libretro.RetroArch",
        "repository": "extra",
        "source": "official",
        "url": "https://www.retroarch.com/",
        "license": "GPL-3.0-only",
        "popularity": 11.5,
    },
    "0ad": {
        "display_name": "0 A.D.",
        "summary": "Jogo de estratégia em tempo real de civilizações históricas",
        "description": "Estratégia militar e econômica de civilizações antigas com gráficos 3D detalhados, mapas aleatórios e modo multijogador livre.",
        "category": "games",
        "icon_name": "0ad",
        "repository": "extra",
        "source": "official",
        "url": "https://play0ad.com/",
        "license": "GPL-2.0-or-later",
        "popularity": 8.5,
    },
    "supertuxkart": {
        "display_name": "SuperTuxKart",
        "summary": "Jogo 3D de corrida de kart com mascotes do código aberto",
        "description": "Corridas divertidas de kart com diversos personagens, pistas desafiadoras, modos de batalha e multiplayer online.",
        "category": "games",
        "icon_name": "supertuxkart",
        "repository": "extra",
        "source": "official",
        "url": "https://supertuxkart.net/",
        "license": "GPL-3.0-or-later",
        "popularity": 9.2,
    },
    "luanti": {
        "display_name": "Luanti (Minetest)",
        "summary": "Motor de jogos voxel infinito em estilo sandbox de blocos",
        "description": "Plataforma de jogos de blocos expansível via mods Lua, suporte a servidores mundiais e geração de mundos infinitos.",
        "category": "games",
        "icon_name": "net.minetest.minetest",
        "repository": "extra",
        "source": "official",
        "url": "https://www.luanti.org/",
        "license": "LGPL-2.1-or-later",
        "popularity": 6.8,
    },
    "wesnoth": {
        "display_name": "Battle for Wesnoth",
        "summary": "Estratégia em turnos de alta fantasia com campanhas ricas",
        "description": "Jogo tático em grade hexagonal com diversas facções fantásticas, centenas de unidades evolutivas e campanhas envolventes.",
        "category": "games",
        "icon_name": "org.wesnoth.Wesnoth",
        "repository": "extra",
        "source": "official",
        "url": "https://www.wesnoth.org/",
        "license": "GPL-2.0-or-later",
        "popularity": 7.1,
    },
    "openmw": {
        "display_name": "OpenMW",
        "summary": "Recriação livre moderna do motor de jogo RPG Morrowind",
        "description": "Motor de jogo moderno em C++ que recria o clássico The Elder Scrolls III com física aprimorada, suporte a 64 bits e widescreen.",
        "category": "games",
        "icon_name": "openmw",
        "repository": "extra",
        "source": "official",
        "url": "https://openmw.org/",
        "license": "GPL-3.0-only",
        "popularity": 5.4,
    },
    "prismlauncher": {
        "display_name": "Prism Launcher",
        "summary": "Iniciador personalizável para Minecraft com suporte a instâncias e mods",
        "description": "Launcher livre com suporte facilitado a modpacks do CurseForge/Modrinth, gerenciamento de versões de Java e múltiplas contas.",
        "category": "games",
        "icon_name": "org.prismlauncher.PrismLauncher",
        "repository": "extra",
        "source": "official",
        "url": "https://prismlauncher.org/",
        "license": "GPL-3.0-only",
        "popularity": 14.7,
    },
    "dolphin-emu": {
        "display_name": "Dolphin Emulator",
        "summary": "Emulador com alta fidelidade para GameCube e Wii",
        "description": "Emulação precisa com renderização em 4K, suporte a controles modernos, shaders visuais e compatibilidade com quase 100% dos títulos.",
        "category": "games",
        "icon_name": "dolphin-emu",
        "repository": "extra",
        "source": "official",
        "url": "https://dolphin-emu.org/",
        "license": "GPL-2.0-or-later",
        "popularity": 10.3,
    },
    "ppsspp": {
        "display_name": "PPSSPP",
        "summary": "Emulador de alta definição para jogos de PlayStation Portable",
        "description": "Emulador de PSP rápido com texturas aprimoradas, suporte a savestates, controles mapeáveis e renderização Vulkan.",
        "category": "games",
        "icon_name": "ppsspp",
        "repository": "extra",
        "source": "official",
        "url": "https://www.ppsspp.org/",
        "license": "GPL-2.0-or-later",
        "popularity": 7.8,
    },

    # Multimedia
    "obs-studio": {
        "display_name": "OBS Studio",
        "summary": "Software profissional para gravação de vídeo e transmissão ao vivo",
        "description": "Ferramenta essencial para criadores de conteúdo com captura de janelas Wayland/PipeWire, filtros de áudio e streaming para Twitch/YouTube.",
        "category": "multimedia",
        "icon_name": "com.obsproject.Studio",
        "repository": "extra",
        "source": "official",
        "url": "https://obsproject.com/",
        "license": "GPL-2.0-or-later",
        "popularity": 36.4,
    },
    "vlc": {
        "display_name": "VLC Media Player",
        "summary": "Reprodutor de mídia universal com suporte a todos os codecs",
        "description": "Reprodutor multimídia capaz de decodificar quase qualquer formato de vídeo ou áudio sem necessidade de instalação de codecs extras.",
        "category": "multimedia",
        "icon_name": "vlc",
        "repository": "extra",
        "source": "official",
        "url": "https://www.videolan.org/vlc/",
        "license": "GPL-2.0-or-later",
        "popularity": 48.5,
    },
    "mpv": {
        "display_name": "MPV",
        "summary": "Reprodutor multimídia minimalista de alta performance",
        "description": "Reprodutor com foco em qualidade visual impecável, aceleração por hardware, integração a scripts Lua e suporte a Wayland.",
        "category": "multimedia",
        "icon_name": "mpv",
        "repository": "extra",
        "source": "official",
        "url": "https://mpv.io/",
        "license": "GPL-2.0-or-later",
        "popularity": 52.1,
    },
    "audacity": {
        "display_name": "Audacity",
        "summary": "Editor e gravador de áudio multifaixa profissional",
        "description": "Edição de formas de onda de áudio, gravação de microfone, redução de ruído, equalização e aplicação de efeitos VST/LADSPA.",
        "category": "multimedia",
        "icon_name": "audacity",
        "repository": "extra",
        "source": "official",
        "url": "https://www.audacityteam.org/",
        "license": "GPL-3.0-or-later",
        "popularity": 26.7,
    },
    "kdenlive": {
        "display_name": "Kdenlive",
        "summary": "Editor de vídeo não-linear multifaixa poderoso",
        "description": "Edição de vídeo avançada com suporte a linha do tempo ilimitada, transições, animação de títulos, correção de cor e aceleração por GPU.",
        "category": "multimedia",
        "icon_name": "kdenlive",
        "repository": "extra",
        "source": "official",
        "url": "https://kdenlive.org/",
        "license": "GPL-3.0-or-later",
        "popularity": 19.8,
    },
    "handbrake": {
        "display_name": "HandBrake",
        "summary": "Transcodificador de vídeo multiformato versátil",
        "description": "Ferramenta para conversão de vídeos de quase qualquer formato para codecs modernos como H.264, H.265, AV1 com presets prontos.",
        "category": "multimedia",
        "icon_name": "fr.handbrake.ghb",
        "repository": "extra",
        "source": "official",
        "url": "https://handbrake.fr/",
        "license": "GPL-2.0-only",
        "popularity": 14.1,
    },
    "ardour": {
        "display_name": "Ardour",
        "summary": "Estação de trabalho de áudio digital (DAW) profissional",
        "description": "Gravação, mixagem e masterização de áudio e MIDI de padrão de estúdio com suporte total ao PipeWire/JACK.",
        "category": "multimedia",
        "icon_name": "ardour",
        "repository": "extra",
        "source": "official",
        "url": "https://ardour.org/",
        "license": "GPL-2.0-or-later",
        "popularity": 6.8,
    },
    "lmms": {
        "display_name": "LMMS",
        "summary": "Produção musical completa com sintetizadores e sequenciadores",
        "description": "Crie melodias, batidas e sintetize faixas completas com instrumentos virtuais, biblioteca de samples e sequenciador em grade.",
        "category": "multimedia",
        "icon_name": "lmms",
        "repository": "extra",
        "source": "official",
        "url": "https://lmms.io/",
        "license": "GPL-2.0-or-later",
        "popularity": 7.9,
    },
    "strawberry": {
        "display_name": "Strawberry Music Player",
        "summary": "Reprodutor de áudio para audiófilos e coleções de música",
        "description": "Tocador focado em fidelidade sonora impecável, reprodução bit-perfect, suporte a formatos DSD/FLAC e busca de letras.",
        "category": "multimedia",
        "icon_name": "org.strawberrymusicplayer.strawberry",
        "repository": "extra",
        "source": "official",
        "url": "https://www.strawberrymusicplayer.org/",
        "license": "GPL-3.0-or-later",
        "popularity": 7.4,
    },
    "elisa": {
        "display_name": "Elisa",
        "summary": "Reprodutor de música elegante e moderno do KDE",
        "description": "Tocador com visual limpo integrado ao desktop, organização fluida por artistas, álbuns e rádios online.",
        "category": "multimedia",
        "icon_name": "org.kde.elisa",
        "repository": "extra",
        "source": "official",
        "url": "https://apps.kde.org/elisa/",
        "license": "LGPL-3.0-or-later",
        "popularity": 8.3,
    },
    "easyeffects": {
        "display_name": "EasyEffects",
        "summary": "Equalizador e efeitos avançados de áudio para PipeWire",
        "description": "Ajuste fino de som com equalizador paramétrico, supressão de ruído com IA para microfones, compressor e amplificador de graves.",
        "category": "multimedia",
        "icon_name": "com.github.wwmm.easyeffects",
        "repository": "extra",
        "source": "official",
        "url": "https://github.com/wwmm/easyeffects",
        "license": "GPL-3.0-or-later",
        "popularity": 17.6,
    },
    "pavucontrol": {
        "display_name": "Controle de Volume PulseAudio / PipeWire",
        "summary": "Mixer gráfico para gerenciamento individual de volume",
        "description": "Controle de saída e entrada de áudio canal por canal para cada aplicativo individual em execução no sistema.",
        "category": "multimedia",
        "icon_name": "org.pulseaudio.pavucontrol",
        "repository": "extra",
        "source": "official",
        "url": "https://freedesktop.org/software/pulseaudio/pavucontrol/",
        "license": "GPL-2.0-or-later",
        "popularity": 45.1,
    },
    "qpwgraph": {
        "display_name": "qpwgraph",
        "summary": "Gerenciador gráfico visual de conexões PipeWire",
        "description": "Interface visual intuitiva para rotear fluxos de áudio, vídeo e MIDI entre aplicativos e dispositivos de hardware.",
        "category": "multimedia",
        "icon_name": "org.rncbc.qpwgraph",
        "repository": "extra",
        "source": "official",
        "url": "https://gitlab.freedesktop.org/rncbc/qpwgraph",
        "license": "GPL-2.0-or-later",
        "popularity": 9.2,
    },

    # Design
    "blender": {
        "display_name": "Blender",
        "summary": "Suíte profissional para modelagem 3D, animação e renderização",
        "description": "Software completo para artistas 3D com pipelines de animação, escultura, simulação física e renderização Cycles/Eevee.",
        "category": "design",
        "icon_name": "blender",
        "repository": "extra",
        "source": "official",
        "url": "https://www.blender.org/",
        "license": "GPL-3.0-or-later",
        "popularity": 18.81,
    },
    "gimp": {
        "display_name": "GIMP",
        "summary": "Editor profissional de imagens e retoque fotográfico",
        "description": "GNU Image Manipulation Program para composição de imagens, edição em camadas, filtros artísticos e pintura digital.",
        "category": "design",
        "icon_name": "gimp",
        "repository": "extra",
        "source": "official",
        "url": "https://www.gimp.org/",
        "license": "GPL-3.0-or-later",
        "popularity": 41.8,
    },
    "inkscape": {
        "display_name": "Inkscape",
        "summary": "Editor de ilustrações e gráficos vetoriais em padrão SVG",
        "description": "Ferramenta de desenho vetorial com ferramentas de caminhos, nós, tipografia avançada e suporte total ao padrão SVG livre.",
        "category": "design",
        "icon_name": "org.inkscape.Inkscape",
        "repository": "extra",
        "source": "official",
        "url": "https://inkscape.org/",
        "license": "GPL-3.0-or-later",
        "popularity": 27.3,
    },
    "krita": {
        "display_name": "Krita",
        "summary": "Estúdio profissional para pintura digital e ilustração artística",
        "description": "Aplicativo líder para ilustradores, artistas conceituais e quadrinistas com motores avançados de pincéis e camadas de animação.",
        "category": "design",
        "icon_name": "krita",
        "repository": "extra",
        "source": "official",
        "url": "https://krita.org/",
        "license": "GPL-3.0-or-later",
        "popularity": 21.4,
    },
    "darktable": {
        "display_name": "Darktable",
        "summary": "Laboratório digital para fotografia RAW e fluxo de trabalho",
        "description": "Mesa de luz virtual para gerenciamento de negativos digitais RAW com processamento não-destrutivo acelerado por GPU.",
        "category": "design",
        "icon_name": "darktable",
        "repository": "extra",
        "source": "official",
        "url": "https://www.darktable.org/",
        "license": "GPL-3.0-or-later",
        "popularity": 8.7,
    },
    "rawtherapee": {
        "display_name": "RawTherapee",
        "summary": "Processador poderoso e detalhado de imagens fotográficas RAW",
        "description": "Processamento avançado de cores, demosicing de alta fidelidade e ajustes finos de nitidez para câmeras profissionais.",
        "category": "design",
        "icon_name": "rawtherapee",
        "repository": "extra",
        "source": "official",
        "url": "https://rawtherapee.com/",
        "license": "GPL-3.0-or-later",
        "popularity": 7.3,
    },
    "freecad": {
        "display_name": "FreeCAD",
        "summary": "Modelador paramétrico 3D para engenharia e arquitetura",
        "description": "Software de CAD paramétrico para desenhar objetos mecânicos, componentes para impressão 3D e plantas de construção.",
        "category": "design",
        "icon_name": "org.freecad.FreeCAD",
        "repository": "extra",
        "source": "official",
        "url": "https://www.freecad.org/",
        "license": "LGPL-2.0-or-later",
        "popularity": 7.9,
    },
    "scribus": {
        "display_name": "Scribus",
        "summary": "Software profissional para diagramação e editoração gráfica (DTP)",
        "description": "Ferramenta para diagramação de jornais, revistas, cartazes e livros com gerenciamento de cores CMYK e saída PDF de alta precisão.",
        "category": "design",
        "icon_name": "scribus",
        "repository": "extra",
        "source": "official",
        "url": "https://www.scribus.net/",
        "license": "GPL-2.0-or-later",
        "popularity": 6.4,
    },
    "fontforge": {
        "display_name": "FontForge",
        "summary": "Editor e criador de fontes tipográficas vetoriais (OTF/TTF)",
        "description": "Crie e edite fontes tipográficas completas com curvas de Bézier e geração de arquivos OpenType, TrueType e fontes web.",
        "category": "design",
        "icon_name": "org.fontforge.FontForge",
        "repository": "extra",
        "source": "official",
        "url": "https://fontforge.org/",
        "license": "GPL-3.0-or-later",
        "popularity": 6.1,
    },
    "mypaint": {
        "display_name": "MyPaint",
        "summary": "Programa ágil e sem distrações para pintura digital",
        "description": "Pintura livre em tela infinita com foco no manuseio de mesas digitalizadoras e rica biblioteca de pincéis expressivos.",
        "category": "design",
        "icon_name": "mypaint",
        "repository": "extra",
        "source": "official",
        "url": "https://mypaint.app/",
        "license": "GPL-2.0-or-later",
        "popularity": 5.2,
    },

    # Office
    "libreoffice-fresh": {
        "display_name": "LibreOffice",
        "summary": "Suíte completa de produtividade para escritório e documentos",
        "description": "Pacote completo com processador de texto (Writer), planilhas (Calc), apresentações (Impress) e alta compatibilidade com MS Office.",
        "category": "office",
        "icon_name": "libreoffice-main",
        "repository": "extra",
        "source": "official",
        "url": "https://www.libreoffice.org/",
        "license": "MPL-2.0",
        "popularity": 39.7,
    },
    "okular": {
        "display_name": "Okular",
        "summary": "Visualizador universal e anotador de documentos PDF, ePub e quadrinhos",
        "description": "Leitor versátil com ferramentas de anotação de texto, preenchimento de formulários e suporte a dezenas de formatos de documentos.",
        "category": "office",
        "icon_name": "okular",
        "repository": "extra",
        "source": "official",
        "url": "https://okular.kde.org/",
        "license": "GPL-2.0-or-later",
        "popularity": 25.3,
    },
    "evince": {
        "display_name": "Evince",
        "summary": "Visualizador de documentos PDF simples e eficiente",
        "description": "Leitor minimalista do GNOME para documentos PDF, PostScript e TIFF com foco em rapidez e fluidez de navegação.",
        "category": "office",
        "icon_name": "org.gnome.Evince",
        "repository": "extra",
        "source": "official",
        "url": "https://wiki.gnome.org/Apps/Evince",
        "license": "GPL-2.0-or-later",
        "popularity": 16.4,
    },
    "foliate": {
        "display_name": "Foliate",
        "summary": "Leitor moderno de livros digitais ePub com tipografia impecável",
        "description": "Experiência de leitura imersiva com suporte a anotações, dicionários integrados, temas de cores e sincronização de progresso.",
        "category": "office",
        "icon_name": "com.github.johnfactotum.Foliate",
        "repository": "extra",
        "source": "official",
        "url": "https://johnfactotum.github.io/foliate/",
        "license": "GPL-3.0-or-later",
        "popularity": 7.5,
    },
    "calibre": {
        "display_name": "Calibre",
        "summary": "Gerenciador, conversor e catálogo abrangente de e-books",
        "description": "Solução definitiva para organizar sua biblioteca de livros digitais, converter formatos (mobi, epub, pdf) e sincronizar leitores digitais.",
        "category": "office",
        "icon_name": "calibre-gui",
        "repository": "extra",
        "source": "official",
        "url": "https://calibre-ebook.com/",
        "license": "GPL-3.0-only",
        "popularity": 13.9,
    },
    "ghostwriter": {
        "display_name": "Ghostwriter",
        "summary": "Editor de texto Markdown sem distrações",
        "description": "Ambiente de escrita focado em concentração com visualização em tempo real de Markdown, estatísticas de escrita e modo Hemingway.",
        "category": "office",
        "icon_name": "ghostwriter",
        "repository": "extra",
        "source": "official",
        "url": "https://ghostwriter.kde.org/",
        "license": "GPL-3.0-or-later",
        "popularity": 5.8,
    },
    "xournalpp": {
        "display_name": "Xournal++",
        "summary": "Caderno de anotações manuscritas e anotação em PDFs",
        "description": "Excelente para estudantes e profissionais fazerem notas com caneta stylus, equações em LaTeX e anotações diretas sobre apostilas PDF.",
        "category": "office",
        "icon_name": "com.github.xournalpp.xournalpp",
        "repository": "extra",
        "source": "official",
        "url": "https://xournalpp.github.io/",
        "license": "GPL-2.0-or-later",
        "popularity": 11.8,
    },
    "gnucash": {
        "display_name": "GnuCash",
        "summary": "Gerenciador financeiro pessoal e de pequenas empresas",
        "description": "Software de contabilidade por partidas dobradas com controle de contas bancárias, investimentos, orçamentos e relatórios em gráficos.",
        "category": "office",
        "icon_name": "org.gnucash.GnuCash",
        "repository": "extra",
        "source": "official",
        "url": "https://gnucash.org/",
        "license": "GPL-2.0-or-later",
        "popularity": 6.2,
    },

    # System & Utilities
    "kitty": {
        "display_name": "Kitty",
        "summary": "Emulador de terminal moderno acelerado por GPU",
        "description": "Emulador de terminal rápido com renderização OpenGL, suporte a gráficos, splits de janela e extensibilidade com kittens.",
        "category": "system",
        "icon_name": "kitty",
        "repository": "extra",
        "source": "official",
        "url": "https://sw.kovidgoyal.net/kitty/",
        "license": "GPL-3.0-only",
        "popularity": 34.6,
    },
    "alacritty": {
        "display_name": "Alacritty",
        "summary": "Terminal acelerado por GPU leve e focado em simplicidade",
        "description": "Emulador de terminal escrito em Rust focado exclusivamente em velocidade extrema e renderização OpenGL com baixo uso de CPU.",
        "category": "system",
        "icon_name": "Alacritty",
        "repository": "extra",
        "source": "official",
        "url": "https://alacritty.org/",
        "license": "Apache-2.0",
        "popularity": 32.1,
    },
    "wezterm": {
        "display_name": "WezTerm",
        "summary": "Emulador de terminal e multiplexador configurável em Lua",
        "description": "Terminal em Rust com abas, painéis divididos, renderização de fontes e ligaduras impecáveis e configuração total em Lua.",
        "category": "system",
        "icon_name": "org.wezfurlong.wezterm",
        "repository": "extra",
        "source": "official",
        "url": "https://wezfurlong.org/wezterm/",
        "license": "MIT",
        "popularity": 12.8,
    },
    "foot": {
        "display_name": "Foot",
        "summary": "Terminal Wayland ultraleve, rápido e com baixo consumo",
        "description": "Emulador de terminal projetado especificamente para Wayland, com suporte a modo servidor-cliente para inicialização em milissegundos.",
        "category": "system",
        "icon_name": "foot",
        "repository": "extra",
        "source": "official",
        "url": "https://codeberg.org/dnkl/foot",
        "license": "MIT",
        "popularity": 14.3,
    },
    "btop": {
        "display_name": "Btop",
        "summary": "Monitor de recursos e processos do sistema em terminal",
        "description": "Monitor visual de CPU, memória, discos e rede com gráficos reativos, controle por mouse e suporte a temas variados.",
        "category": "system",
        "icon_name": "utilities-system-monitor",
        "repository": "extra",
        "source": "official",
        "url": "https://github.com/aristocratos/btop",
        "license": "Apache-2.0",
        "popularity": 37.9,
    },
    "htop": {
        "display_name": "Htop",
        "summary": "Visualizador interativo clássico de processos em tempo real",
        "description": "Visualizador de processos leve com barras de uso de CPU por núcleo, medidor de memória e gerenciador interativo de prioridades.",
        "category": "system",
        "icon_name": "htop",
        "repository": "extra",
        "source": "official",
        "url": "https://htop.dev/",
        "license": "GPL-2.0-only",
        "popularity": 55.4,
    },
    "fastfetch": {
        "display_name": "Fastfetch",
        "summary": "Utilitário ultrarrápido para exibição de informações do sistema",
        "description": "Ferramenta em C que imprime detalhes do hardware, ambiente Hyprland e sistema operacional com logos ASCII e imagens.",
        "category": "system",
        "icon_name": "utilities-terminal",
        "repository": "extra",
        "source": "official",
        "url": "https://github.com/fastfetch-cli/fastfetch",
        "license": "MIT",
        "popularity": 42.1,
    },
    "gparted": {
        "display_name": "GParted",
        "summary": "Editor gráfico avançado de partições de disco",
        "description": "Gerencie partições de disco, redimensione, crie tabelas GPT/MBR e verifique sistemas de arquivos de forma segura e visual.",
        "category": "system",
        "icon_name": "gparted",
        "repository": "extra",
        "source": "official",
        "url": "https://gparted.org/",
        "license": "GPL-2.0-or-later",
        "popularity": 28.7,
    },
    "baobab": {
        "display_name": "Analisador de Uso de Disco (Baobab)",
        "summary": "Mapeador gráfico visual do espaço ocupado em disco",
        "description": "Descubra rapidamente quais pastas e arquivos estão ocupando espaço no sistema com diagramas em anéis e gráficos em árvore.",
        "category": "system",
        "icon_name": "org.gnome.baobab",
        "repository": "extra",
        "source": "official",
        "url": "https://wiki.gnome.org/Apps/Baobab",
        "license": "GPL-2.0-or-later",
        "popularity": 18.2,
    },
    "filelight": {
        "display_name": "Filelight",
        "summary": "Visualizador concêntrico de espaço em disco do KDE",
        "description": "Navegue pelo seu sistema de arquivos através de gráficos circulares interativos para liberar espaço com facilidade.",
        "category": "system",
        "icon_name": "org.kde.filelight",
        "repository": "extra",
        "source": "official",
        "url": "https://apps.kde.org/filelight/",
        "license": "GPL-2.0-or-later",
        "popularity": 9.4,
    },
    "timeshift": {
        "display_name": "Timeshift",
        "summary": "Utilitário de restauração e snapshots do sistema (BTRFS/RSYNC)",
        "description": "Crie pontos de restauração incrementais para proteger o sistema operacional contra falhas ou atualizações problemáticas.",
        "category": "system",
        "icon_name": "timeshift",
        "repository": "extra",
        "source": "official",
        "url": "https://github.com/linuxmint/timeshift",
        "license": "GPL-3.0-or-later",
        "popularity": 15.4,
    },
    "flameshot": {
        "display_name": "Flameshot",
        "summary": "Captura de tela com ferramentas avançadas de anotação e desenho",
        "description": "Capture áreas da tela com facilidade, adicione setas, destaques, desfoque de dados sensíveis e envie para a nuvem.",
        "category": "utilities",
        "icon_name": "org.flameshot.Flameshot",
        "repository": "extra",
        "source": "official",
        "url": "https://flameshot.org/",
        "license": "GPL-3.0-or-later",
        "popularity": 22.9,
    },
    "ark": {
        "display_name": "Ark",
        "summary": "Gerenciador gráfico para arquivos compactados e zip",
        "description": "Extraia, crie e explore arquivos compactados nos formatos zip, tar, 7z, rar e tar.gz com integração ao gerenciador de arquivos.",
        "category": "utilities",
        "icon_name": "org.kde.ark",
        "repository": "extra",
        "source": "official",
        "url": "https://apps.kde.org/ark/",
        "license": "GPL-2.0-or-later",
        "popularity": 17.5,
    },
    "7zip": {
        "display_name": "7-Zip",
        "summary": "Compactador de alta taxa de compressão e criptografia AES-256",
        "description": "Utilitário robusto de compressão e descompactação com suporte a formatos modernos e proteção por senha.",
        "category": "utilities",
        "icon_name": "utilities-terminal",
        "repository": "extra",
        "source": "official",
        "url": "https://www.7-zip.org/",
        "license": "LGPL-2.1-or-later",
        "popularity": 29.8,
    },
    "keepassxc": {
        "display_name": "KeePassXC",
        "summary": "Cofre de senhas seguro e local com criptografia ponta a ponta",
        "description": "Gerenciador de senhas multiplataforma sem depender de nuvem de terceiros, com preenchimento automático em navegadores.",
        "category": "utilities",
        "icon_name": "org.keepassxc.KeePassXC",
        "repository": "extra",
        "source": "official",
        "url": "https://keepassxc.org/",
        "license": "GPL-2.0-or-later",
        "popularity": 28.1,
    },
    "bitwarden": {
        "display_name": "Bitwarden",
        "summary": "Gerenciador de senhas seguro e sincronizado em nuvem ou self-host",
        "description": "Armazene logins, notas seguras e cartões com criptografia de ponta a ponta zero-knowledge e sincronização em múltiplos aparelhos.",
        "category": "utilities",
        "icon_name": "bitwarden",
        "repository": "extra",
        "source": "official",
        "url": "https://bitwarden.com/",
        "license": "GPL-3.0-only",
        "popularity": 16.2,
    },
    "syncthing": {
        "display_name": "Syncthing",
        "summary": "Sincronização contínua de pastas entre dispositivos ponto a ponto",
        "description": "Sincronize arquivos entre computadores e celulares de forma descentralizada, privada e criptografada sem depender da nuvem.",
        "category": "utilities",
        "icon_name": "syncthing",
        "repository": "extra",
        "source": "official",
        "url": "https://syncthing.net/",
        "license": "MPL-2.0",
        "popularity": 18.9,
    },
    "bleachbit": {
        "display_name": "BleachBit",
        "summary": "Limpeza de arquivos temporários, caches e privacidade do sistema",
        "description": "Libere espaço em disco apagando caches obsoletos, cookies, histórico e arquivos residuais de dezenas de aplicativos.",
        "category": "utilities",
        "icon_name": "org.bleachbit.BleachBit",
        "repository": "extra",
        "source": "official",
        "url": "https://www.bleachbit.org/",
        "license": "GPL-3.0-or-later",
        "popularity": 9.5,
    },
    "mission-center": {
        "display_name": "Mission Center",
        "summary": "Monitor visual de hardware moderno estilo gerenciador de tarefas",
        "description": "Acompanhe o uso de CPU, GPU, memória, disco e rede em tempo real com gráficos fluidos construídos em GTK4 e Rust.",
        "category": "system",
        "icon_name": "io.missioncenter.MissionCenter",
        "repository": "extra",
        "source": "official",
        "url": "https://missioncenter.io/",
        "license": "GPL-3.0-or-later",
        "popularity": 8.4,
    },
}

# Curated candidates for AUR discovery (>40 real AUR packages)
AUR_DISCOVERY_CANDIDATES: dict[str, dict[str, Any]] = {
    # Popular
    "visual-studio-code-bin": {
        "display_name": "Visual Studio Code",
        "summary": "Editor de código profissional com ecossistema de extensões",
        "description": "Distribuição oficial do VS Code da Microsoft para Linux com IntelliSense, Git integrado e suporte a extensões proprietárias.",
        "category": "development",
        "icon_name": "visual-studio-code",
        "section": "aur_popular",
        "version": "1.95.3-1",
        "votes": 1711,
        "popularity": 13.01,
        "maintainer": "bboozzoo",
    },
    "vscodium-bin": {
        "display_name": "VSCodium",
        "summary": "Distribuição livre do VS Code sem telemetria ou rastreamento",
        "description": "Binários da comunidade do VS Code com foco total em privacidade, livre de telemetria e licença 100% open source.",
        "category": "development",
        "icon_name": "vscodium",
        "section": "aur_development",
        "version": "1.95.3-1",
        "votes": 750,
        "popularity": 8.4,
        "maintainer": "lucy",
    },
    "zen-browser-bin": {
        "display_name": "Zen Browser",
        "summary": "Navegador inovador com abas verticais e privacidade baseado em Firefox",
        "description": "Navegador moderno com interface customizada, abas verticais compactas, perfis divididos e motor Gecko de alta performance.",
        "category": "internet",
        "icon_name": "zen-browser",
        "section": "aur_popular",
        "version": "1.0.1-1",
        "votes": 520,
        "popularity": 12.5,
        "maintainer": "zen-team",
    },
    "brave-bin": {
        "display_name": "Brave Browser",
        "summary": "Navegador focado em privacidade com bloqueador nativo de anúncios",
        "description": "Navegador baseado no Chromium que bloqueia rastreadores e anúncios invasivos por padrão, garantindo navegação veloz.",
        "category": "internet",
        "icon_name": "brave-browser",
        "section": "aur_popular",
        "version": "1.71.123-1",
        "votes": 1280,
        "popularity": 11.2,
        "maintainer": "krayon",
    },
    "google-chrome": {
        "display_name": "Google Chrome",
        "summary": "Navegador oficial do Google com sincronização de conta",
        "description": "Navegador com motor Blink, tradução integrada, sincronização completa de favoritos, senhas e serviços do ecossistema Google.",
        "category": "internet",
        "icon_name": "google-chrome",
        "section": "aur_popular",
        "version": "130.0.6723.116-1",
        "votes": 2980,
        "popularity": 19.4,
        "maintainer": "frealgawd",
    },
    "spotify": {
        "display_name": "Spotify",
        "summary": "Cliente oficial de streaming de músicas e podcasts",
        "description": "Acesso a milhões de músicas, playlists curadas e podcasts com reprodução em alta definição e suporte a controle remoto.",
        "category": "multimedia",
        "icon_name": "spotify-client",
        "section": "aur_popular",
        "version": "1.2.50-1",
        "votes": 3450,
        "popularity": 25.4,
        "maintainer": "alucryd",
    },
    "vesktop-bin": {
        "display_name": "Vesktop",
        "summary": "Cliente Discord leve com Vencord e compartilhamento de tela com áudio em Wayland",
        "description": "Alternativa de ponta para o Discord com compartilhamento de tela fluido no Wayland com áudio do PipeWire e plugins Vencord nativos.",
        "category": "internet",
        "icon_name": "vesktop",
        "section": "aur_popular",
        "version": "1.5.3-1",
        "votes": 610,
        "popularity": 14.8,
        "maintainer": "vendicated",
    },
    "heroic-games-launcher-bin": {
        "display_name": "Heroic Games Launcher",
        "summary": "Iniciador livre para Epic Games, GOG e Amazon Games no Linux",
        "description": "Gerenciador nativo de jogos para títulos da Epic Games e GOG com suporte a Wine, Proton, DXVK e sincronização de saves na nuvem.",
        "category": "games",
        "icon_name": "com.heroicgameslauncher.hgl",
        "section": "aur_games",
        "version": "2.15.1-1",
        "votes": 890,
        "popularity": 10.6,
        "maintainer": "flavioislima",
    },
    "protonup-qt-bin": {
        "display_name": "ProtonUp-Qt",
        "summary": "Gerenciador visual para versões do GE-Proton, Wine-GE e Luxtorpeda",
        "description": "Instale e atualize versões comunitárias do Proton-GE para Steam, Lutris e Heroic com um único clique para máxima compatibilidade.",
        "category": "games",
        "icon_name": "net.davidotek.pupgui2",
        "section": "aur_games",
        "version": "2.10.0-1",
        "votes": 620,
        "popularity": 8.9,
        "maintainer": "davidotek",
    },
    "localsend-bin": {
        "display_name": "LocalSend",
        "summary": "Compartilhamento seguro de arquivos em rede local sem internet",
        "description": "Alternativa livre e aberta ao AirDrop para transferir arquivos entre Linux, Android, iOS e Windows na rede Wi-Fi local sem nuvem.",
        "category": "utilities",
        "icon_name": "localsend",
        "section": "aur_popular",
        "version": "1.15.4-1",
        "votes": 430,
        "popularity": 9.4,
        "maintainer": "tien",
    },
    "obsidian-bin": {
        "display_name": "Obsidian",
        "summary": "Base de conhecimento e anotações com links bidirecionais em Markdown",
        "description": "Segunda memória em arquivos Markdown locais com gráficos de conexão de ideias, plugins comunitários e sem aprisionamento.",
        "category": "office",
        "icon_name": "obsidian",
        "section": "aur_productivity",
        "version": "1.7.7-1",
        "votes": 980,
        "popularity": 11.7,
        "maintainer": "argent",
    },
    "paru": {
        "display_name": "Paru",
        "summary": "Auxiliar moderno do AUR e frontend do pacman escrito em Rust",
        "description": "AUR helper ultrarrápido com revisão de PKGBUILD interativa, ordenação inteligente e compilação otimizada.",
        "category": "system",
        "icon_name": "utilities-terminal",
        "section": "aur_community",
        "version": "2.0.4-1",
        "votes": 2300,
        "popularity": 18.5,
        "maintainer": "morganamilo",
    },
    "yay": {
        "display_name": "Yay",
        "summary": "Auxiliar clássico do AUR com sintaxe idêntica ao pacman em Go",
        "description": "O mais popular AUR helper com resolução automática de dependências, busca intuitiva e manutenção constante pela comunidade.",
        "category": "system",
        "icon_name": "utilities-terminal",
        "section": "aur_community",
        "version": "12.4.2-1",
        "votes": 4200,
        "popularity": 28.2,
        "maintainer": "jguer",
    },
    "cursor-bin": {
        "display_name": "Cursor",
        "summary": "Editor de código alimentado por inteligência artificial",
        "description": "Fork do VS Code com assistência de IA integrada para edição de código em múltiplos arquivos e geração assistida.",
        "category": "development",
        "icon_name": "cursor",
        "section": "aur_development",
        "version": "0.42.5-1",
        "votes": 310,
        "popularity": 7.8,
        "maintainer": "anysphere",
    },
    "sublime-text-4": {
        "display_name": "Sublime Text",
        "summary": "Editor de texto veloz com renderização acelerada por GPU",
        "description": "Editor clássico ultra-rápido com suporte a seleções múltiplas, mini-mapa fluído e inicialização instantânea.",
        "category": "development",
        "icon_name": "sublime-text",
        "section": "aur_development",
        "votes": 1420,
        "popularity": 8.2,
        "maintainer": "sublimehq",
    },
    "postman-bin": {
        "display_name": "Postman",
        "summary": "Plataforma de testes e documentação de APIs REST e GraphQL",
        "description": "Ambiente completo para projetar, testar, depurar e monitorar requisições HTTP e fluxos de APIs web.",
        "category": "development",
        "icon_name": "postman",
        "section": "aur_development",
        "votes": 850,
        "popularity": 6.9,
        "maintainer": "postman",
    },
    "insomnia-bin": {
        "display_name": "Insomnia",
        "summary": "Cliente de design e depuração de APIs REST, gRPC e GraphQL",
        "description": "Ferramenta intuitiva e limpa para enviar requisições de API, gerenciar ambientes e inspecionar respostas com rapidez.",
        "category": "development",
        "icon_name": "insomnia",
        "section": "aur_development",
        "votes": 420,
        "popularity": 5.1,
        "maintainer": "kong",
    },
    "github-desktop-bin": {
        "display_name": "GitHub Desktop",
        "summary": "Interface gráfica simplificada para Git e fluxo de trabalho no GitHub",
        "description": "Gerenciador visual para clonar repositórios, ramificar, criar commits e pull requests de forma transparente.",
        "category": "development",
        "icon_name": "github-desktop",
        "section": "aur_development",
        "votes": 680,
        "popularity": 6.4,
        "maintainer": "shiftkey",
    },
    "lazydocker-bin": {
        "display_name": "LazyDocker",
        "summary": "Interface TUI rica para gerenciamento de containers Docker",
        "description": "Visualize logs em tempo real, monitore CPU/RAM de containers e reinicie serviços Docker pelo terminal facilmente.",
        "category": "development",
        "icon_name": "utilities-terminal",
        "section": "aur_development",
        "votes": 340,
        "popularity": 4.8,
        "maintainer": "jesseduffield",
    },
    "r2modman-bin": {
        "display_name": "r2modman",
        "summary": "Gerenciador simples de mods para jogos no Steam e PC",
        "description": "Instalador de mods com suporte a Risk of Rain 2, Valheim, Lethal Company e dezenas de outros jogos com perfis isolados.",
        "category": "games",
        "icon_name": "r2modman",
        "section": "aur_games",
        "votes": 290,
        "popularity": 5.2,
        "maintainer": "ebkr",
    },
    "osu-lazer-bin": {
        "display_name": "osu!lazer",
        "summary": "Jogo de ritmo musical moderno de código aberto",
        "description": "Nova versão do famoso jogo de ritmo com interface moderna, suporte multiplataforma e dezenas de milhares de beatmaps.",
        "category": "games",
        "icon_name": "osu-lazer",
        "section": "aur_games",
        "votes": 520,
        "popularity": 6.7,
        "maintainer": "ppy",
    },
    "minecraft-launcher": {
        "display_name": "Minecraft Launcher",
        "summary": "Iniciador oficial para Minecraft: Java Edition e Bedrock",
        "description": "Launcher oficial da Mojang Studios para instalação e inicialização do Minecraft Java no Linux.",
        "category": "games",
        "icon_name": "minecraft-launcher",
        "section": "aur_games",
        "votes": 910,
        "popularity": 8.1,
        "maintainer": "mojang",
    },
    "freetube-bin": {
        "display_name": "FreeTube",
        "summary": "Cliente privado do YouTube sem anúncios e sem rastreamento",
        "description": "Assista a vídeos do YouTube sem anúncios, sem contas do Google e com armazenamento local de inscrições e histórico.",
        "category": "multimedia",
        "icon_name": "freetube",
        "section": "aur_community",
        "votes": 670,
        "popularity": 7.4,
        "maintainer": "freetube",
    },
    "feishin-bin": {
        "display_name": "Feishin",
        "summary": "Player de música moderno para servidores Navidrome e Subsonic",
        "description": "Cliente elegante para streaming da sua biblioteca de música própria com suporte a letras sincronizadas e cache offline.",
        "category": "multimedia",
        "icon_name": "feishin",
        "section": "aur_community",
        "votes": 180,
        "popularity": 3.9,
        "maintainer": "jeffvli",
    },
    "stremio": {
        "display_name": "Stremio",
        "summary": "Central multimídia para filmes, séries e transmissões de vídeo",
        "description": "Organizador de conteúdo de vídeo com suporte a complementos comunitários, sinopses e reprodução integrada.",
        "category": "multimedia",
        "icon_name": "smartcode-stremio",
        "section": "aur_community",
        "votes": 820,
        "popularity": 8.5,
        "maintainer": "stremio",
    },
    "zoom": {
        "display_name": "Zoom",
        "summary": "Plataforma de videoconferências e reuniões online",
        "description": "Cliente para chamadas de vídeo corporativas, aulas remotas, bate-papo em grupo e compartilhamento de apresentações.",
        "category": "internet",
        "icon_name": "Zoom",
        "section": "aur_productivity",
        "votes": 1150,
        "popularity": 7.2,
        "maintainer": "zoom",
    },
    "slack-desktop": {
        "display_name": "Slack",
        "summary": "Plataforma de comunicação e colaboração para equipes",
        "description": "Canais organizados de bate-papo em equipe, integração com serviços corporativos e compartilhamento ágil de mensagens.",
        "category": "internet",
        "icon_name": "slack",
        "section": "aur_productivity",
        "votes": 1390,
        "popularity": 8.7,
        "maintainer": "slack",
    },
    "onlyoffice-bin": {
        "display_name": "ONLYOFFICE Desktop Editors",
        "summary": "Suíte de escritório com máxima compatibilidade com formatos MS Office",
        "description": "Editores de documentos de texto, planilhas e apresentações com interface em abas e compatibilidade nativa com DOCX/XLSX.",
        "category": "office",
        "icon_name": "onlyoffice-desktopeditors",
        "section": "aur_productivity",
        "votes": 580,
        "popularity": 6.8,
        "maintainer": "onlyoffice",
    },
    "logseq-desktop-bin": {
        "display_name": "Logseq",
        "summary": "Plataforma local de anotações em tópicos estruturados (Outliner)",
        "description": "Gerenciamento de conhecimento com foco em privacidade, links em grafos e escrita orientada a tópicos diários.",
        "category": "office",
        "icon_name": "logseq",
        "section": "aur_productivity",
        "votes": 410,
        "popularity": 5.4,
        "maintainer": "logseq",
    },
    "anytype-bin": {
        "display_name": "Anytype",
        "summary": "Ambiente pessoal local e criptografado para tarefas e notas",
        "description": "Alternativa privada ao Notion com arquitetura ponto a ponto, armazenamento local e criptografia ponta a ponta.",
        "category": "office",
        "icon_name": "anytype",
        "section": "aur_productivity",
        "votes": 260,
        "popularity": 4.2,
        "maintainer": "anytype",
    },
    "joplin-desktop": {
        "display_name": "Joplin",
        "summary": "Aplicativo seguro de anotações com suporte a sincronização",
        "description": "Caderno de anotações com suporte a Markdown, anexos, criptografia E2E e sincronização com Nextcloud, Dropbox ou WebDAV.",
        "category": "office",
        "icon_name": "joplin",
        "section": "aur_productivity",
        "votes": 630,
        "popularity": 5.9,
        "maintainer": "joplin",
    },
    "1password": {
        "display_name": "1Password",
        "summary": "Gerenciador de senhas corporativo com desbloqueio biométrico",
        "description": "Cliente desktop oficial do 1Password com suporte a integração de terminal, chaves SSH e preenchimento seguro.",
        "category": "utilities",
        "icon_name": "1password",
        "section": "aur_productivity",
        "votes": 480,
        "popularity": 4.9,
        "maintainer": "agilebits",
    },
    "bottles": {
        "display_name": "Bottles",
        "summary": "Gerenciador visual fácil de prefixos e aplicativos Wine",
        "description": "Execute softwares e jogos do Windows no Linux com ambientes isolados pré-configurados com DXVK, vkd3d e dependências.",
        "category": "utilities",
        "icon_name": "com.usebottles.bottles",
        "section": "aur_community",
        "votes": 590,
        "popularity": 6.3,
        "maintainer": "bottles",
    },
    "peazip": {
        "display_name": "PeaZip",
        "summary": "Gerenciador de arquivos compactados com suporte a mais de 200 formatos",
        "description": "Utilitário gráfico completo com suporte a 7Z, RAR, TAR, ZIP, encriptação avançada e verificação de hashes SHA/MD5.",
        "category": "utilities",
        "icon_name": "peazip",
        "section": "aur_community",
        "votes": 340,
        "popularity": 4.2,
        "maintainer": "giorgio",
    },
    "ventoy-bin": {
        "display_name": "Ventoy",
        "summary": "Criador de pendrive multiboot copiando arquivos ISO diretamente",
        "description": "Gere pendrives bootáveis sem precisar formatar a cada nova ISO: basta copiar os arquivos .iso para o pendrive.",
        "category": "utilities",
        "icon_name": "ventoy",
        "section": "aur_community",
        "votes": 820,
        "popularity": 9.1,
        "maintainer": "ventoy",
    },
    "waterfox-bin": {
        "display_name": "Waterfox",
        "summary": "Navegador web focado em privacidade e personalização",
        "description": "Navegador de código aberto derivado do Firefox com suporte a extensões legadas e sem coleta de telemetria.",
        "category": "internet",
        "icon_name": "waterfox",
        "section": "aur_community",
        "votes": 310,
        "popularity": 4.1,
        "maintainer": "alex",
    },
    "floorp-bin": {
        "display_name": "Floorp",
        "summary": "Navegador veloz com abas verticais e painel lateral expansível",
        "description": "Fork japonês avançado do Firefox com customização completa de layout, barra lateral web e workspaces.",
        "category": "internet",
        "icon_name": "floorp",
        "section": "aur_community",
        "votes": 490,
        "popularity": 7.3,
        "maintainer": "suru",
    },
    "beekeeper-studio-bin": {
        "display_name": "Beekeeper Studio",
        "summary": "Editor SQL moderno e elegante para desenvolvedores",
        "description": "Cliente visual limpo para SQLite, PostgreSQL, MySQL e SQL Server com abas e consultas parametrizadas.",
        "category": "development",
        "icon_name": "beekeeper-studio",
        "section": "aur_development",
        "votes": 240,
        "popularity": 3.8,
        "maintainer": "rathboma",
    },
    "spacedrive-bin": {
        "display_name": "Spacedrive",
        "summary": "Explorador de arquivos universal de código aberto (VDFS)",
        "description": "Gerenciador de arquivos distribuído que conecta todos os seus dispositivos e nuvens em uma única interface moderna.",
        "category": "utilities",
        "icon_name": "spacedrive",
        "section": "aur_productivity",
        "votes": 320,
        "popularity": 4.5,
        "maintainer": "spacedrive",
    },
    "tidal-hifi-bin": {
        "display_name": "TIDAL Hi-Fi",
        "summary": "Cliente desktop não-oficial para streaming do TIDAL com áudio Hi-Res",
        "description": "Reprodução de música com qualidade Lossless e Master, suporte a integração MPRIS e atalhos globais.",
        "category": "multimedia",
        "icon_name": "tidal-hifi",
        "section": "aur_community",
        "votes": 210,
        "popularity": 3.4,
        "maintainer": "mastermind",
    },
    "betterbird-bin": {
        "display_name": "Betterbird",
        "summary": "Versão aprimorada do Thunderbird com melhorias da comunidade",
        "description": "Cliente de e-mail avançado com correções de bugs complexos, visualização em árvore de mensagens e busca instantânea.",
        "category": "internet",
        "icon_name": "betterbird",
        "section": "aur_productivity",
        "votes": 380,
        "popularity": 5.1,
        "maintainer": "betterbird",
    },
    "cider": {
        "display_name": "Cider",
        "summary": "Cliente moderno acelerado por Electron para Apple Music",
        "description": "Player alternativo veloz para Apple Music com equalizador de áudio, integração Discord RPC e temas dinâmicos.",
        "category": "multimedia",
        "icon_name": "cider",
        "section": "aur_community",
        "votes": 540,
        "popularity": 6.2,
        "maintainer": "ciderapp",
    },
}

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
        "version": "132.0.2-1",
        "popularity": 69.13,
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
        "version": "0.38.0-1",
        "popularity": 34.6,
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
        "version": "1.95.3-1",
        "popularity": 13.01,
        "votes": 1711,
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
        "version": "30.2.3-1",
        "popularity": 36.4,
    },
    {
        "name": "gimp",
        "display_name": "GIMP",
        "summary": "Editor profissional de imagens e retoque fotográfico",
        "description": "GNU Image Manipulation Program para retoque de fotos, composição de imagens e criação de arte digital.",
        "category": "design",
        "icon_name": "gimp",
        "url": "https://www.gimp.org/",
        "license": "GPL-3.0-or-later",
        "repository": "extra",
        "source": "official",
        "version": "2.10.38-2",
        "popularity": 41.8,
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
        "version": "0.39.0-1",
        "popularity": 52.1,
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
        "version": "3.0.21-1",
        "popularity": 48.5,
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
        "version": "1.0.0.82-1",
        "popularity": 45.9,
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
        "version": "0.5.17-1",
        "popularity": 24.5,
    },
    {
        "name": "telegram-desktop",
        "display_name": "Telegram Desktop",
        "summary": "Mensageiro instantâneo seguro, rápido e sincronizado",
        "description": "Aplicativo oficial para desktop do serviço de mensagens em nuvem Telegram, com canais, grupos e compartilhamento veloz.",
        "category": "internet",
        "icon_name": "telegram",
        "url": "https://desktop.telegram.org/",
        "license": "GPL-3.0-only",
        "repository": "extra",
        "source": "official",
        "version": "5.6.3-1",
        "popularity": 31.5,
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
        "version": "1.2.50-1",
        "popularity": 25.4,
        "votes": 3450,
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
        "version": "0.0.73-1",
        "popularity": 38.2,
    },
    {
        "name": "blender",
        "display_name": "Blender",
        "summary": "Suíte profissional para modelagem 3D, animação e renderização",
        "description": "Software completo para artistas 3D com pipelines de animação, escultura, simulação física e renderização Cycles/Eevee.",
        "category": "design",
        "icon_name": "blender",
        "url": "https://www.blender.org/",
        "license": "GPL-3.0-or-later",
        "repository": "extra",
        "source": "official",
        "version": "4.2.3-1",
        "popularity": 18.81,
    },
    {
        "name": "inkscape",
        "display_name": "Inkscape",
        "summary": "Editor de gráficos vetoriais com padrão SVG",
        "description": "Ferramenta de ilustração vetorial para designers, artistas e desenvolvedores com exportação precisa em múltiplos formatos.",
        "category": "design",
        "icon_name": "org.inkscape.Inkscape",
        "url": "https://inkscape.org/",
        "license": "GPL-3.0-or-later",
        "repository": "extra",
        "source": "official",
        "version": "1.4-1",
        "popularity": 27.3,
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
        "version": "0.10.2-1",
        "popularity": 44.2,
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
        "version": "1.4.0-1",
        "popularity": 37.9,
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
        "version": "2.30.1-1",
        "popularity": 42.1,
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
        "version": "24.8.3-1",
        "popularity": 39.7,
    },
)


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
    """Map any raw category string into one of the 9 canonical store categories."""
    if not category_raw:
        return default
    cat_lower = category_raw.lower()

    # Terminal / Shell / Console is System, never Games (even if described as 'terminal emulator')
    if any(k in cat_lower for k in ("terminal", "shell", "console")):
        return "system"

    if any(k in cat_lower for k in ("design", "3d", "vector", "photography", "cad", "illustration", "painting", "draw", "krita", "blender", "inkscape", "gimp", "darktable", "freecad", "scribus")):
        return "design"
    if "game" in cat_lower or ("emulator" in cat_lower and "terminal" not in cat_lower) or "arcade" in cat_lower:
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
        "design": "applications-graphics",
        "development": "applications-development",
        "internet": "applications-internet",
        "office": "applications-office",
        "system": "applications-system",
        "utilities": "applications-utilities",
        "featured": "emblem-favorite",
    }
    return cat, category_icons.get(cat, "applications-other")


def is_user_application(
    name: str,
    summary: str = "",
    groups: Sequence[str] = (),
    has_appstream_or_desktop: bool = False,
) -> bool:
    """Classify whether a package is a user application or a library/system component."""
    clean_name = name.lower()

    if has_appstream_or_desktop:
        return True

    if clean_name in KNOWN_APPLICATIONS_CATALOG or clean_name in AUR_DISCOVERY_CANDIDATES:
        return True

    for feat in FEATURED_PACKAGES_METADATA:
        if feat["name"] == clean_name:
            return True

    # Technical prefix filters (libraries, toolchains, bindings, fonts, headers)
    lib_prefixes = (
        "lib",
        "lib32-",
        "python-",
        "python2-",
        "perl-",
        "ruby-",
        "lua-",
        "lua5",
        "haskell-",
        "rust-",
        "go-",
        "nodejs-",
        "php-",
        "r-",
        "texlive-",
        "ttf-",
        "otf-",
        "woff",
        "noto-fonts",
        "xorg-",
        "xf86-",
        "vulkan-headers",
        "linux-headers",
        "linux-lts-headers",
        "linux-zen-headers",
    )
    if any(clean_name.startswith(p) for p in lib_prefixes):
        return False

    lib_suffixes = (
        "-headers",
        "-docs",
        "-doc",
        "-debug",
        "-common",
        "-data",
        "-libs",
        "-devel",
        "-i18n",
        "-l10n",
    )
    if any(clean_name.endswith(s) for s in lib_suffixes):
        return False

    # Check known groups
    for g in groups:
        if g in ("gnome", "kde-applications", "xfce4-apps", "pro-audio"):
            return True

    return False


class CatalogService:
    """Service providing package discovery, indexing, metadata enrichment and updates."""

    def __init__(
        self,
        mock_mode: bool | None = None,
        on_index_ready: Callable[[], None] | None = None,
    ) -> None:
        self.mock_mode = is_mock_mode() if mock_mode is None else mock_mode
        self._on_index_ready = on_index_ready
        self._installed_cache: dict[str, PackageItem] = {}
        self._official_repo_cache: dict[str, dict[str, Any]] = {}
        self._desktop_entries: dict[str, dict[str, Any]] = {}
        self._appstream_entries: dict[str, dict[str, Any]] = {}
        self._aur_cache: dict[str, tuple[float, list[PackageItem]]] = {}
        self._package_cache: dict[str, PackageItem] = {}
        self._aur_cache_ttl = 120.0  # 2 minutes TTL for search queries

        self._unsynced_repos: bool = False
        self.last_network_error: bool = False
        self._is_indexing: bool = False
        self._indexing_thread: threading.Thread | None = None
        self._sync_index_lock = threading.Lock()

        # Load personalization
        self._load_user_preferences()

        # Load enrichment
        self._load_appstream_metadata()
        self._load_desktop_entries()
        self.refresh_installed()

        # Sync database initialization
        self._init_official_sync_index()

    # -------------------------------------------------------------------------
    # Personalization with Privacy (Local Only)
    # -------------------------------------------------------------------------

    def _get_prefs_path(self) -> str:
        """Resolve path to local user preferences JSON file."""
        override = os.environ.get("REDSHIFT_PREFS_PATH")
        if override:
            return override
        state_dir = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
        return os.path.join(state_dir, "redshift-store", "user_preferences.json")

    def _load_user_preferences(self) -> None:
        """Load local user preferences."""
        path = self._get_prefs_path()
        self._user_prefs: dict[str, Any] = {
            "personalization_enabled": True,
            "visited_categories": {},
            "search_terms": [],
            "viewed_packages": [],
            "favorites": [],
        }
        if os.path.isfile(path):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    if isinstance(data, dict):
                        self._user_prefs.update(data)
            except Exception as e:
                logger.warning("Error reading user preferences: %s", e)

    def _save_user_preferences(self) -> None:
        """Save local user preferences atomically."""
        path = self._get_prefs_path()
        try:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            tmp_path = path + ".tmp"
            with open(tmp_path, "w", encoding="utf-8") as f:
                json.dump(self._user_prefs, f, indent=2, ensure_ascii=False)
            os.replace(tmp_path, path)
        except Exception as e:
            logger.warning("Error writing user preferences: %s", e)

    def is_personalization_enabled(self) -> bool:
        """Return True if personalization is active."""
        return bool(self._user_prefs.get("personalization_enabled", True))

    def set_personalization_enabled(self, enabled: bool) -> None:
        """Enable or disable recommendations personalization."""
        self._user_prefs["personalization_enabled"] = bool(enabled)
        self._save_user_preferences()

    def clear_personalization_history(self) -> None:
        """Clear all browsing and search history."""
        self._user_prefs["visited_categories"] = {}
        self._user_prefs["search_terms"] = []
        self._user_prefs["viewed_packages"] = []
        self._save_user_preferences()

    def record_category_visit(self, category: str) -> None:
        """Record visit to category for local preference weighting."""
        if not self.is_personalization_enabled() or not category or category in ("all", "featured"):
            return
        v = self._user_prefs.setdefault("visited_categories", {})
        v[category] = v.get(category, 0) + 1
        self._save_user_preferences()

    def record_search_query(self, query: str) -> None:
        """Record search keyword for local preference weighting."""
        clean = query.strip().lower()
        if not self.is_personalization_enabled() or not clean or len(clean) < 2:
            return
        terms: list[str] = self._user_prefs.setdefault("search_terms", [])
        if clean in terms:
            terms.remove(clean)
        terms.insert(0, clean)
        self._user_prefs["search_terms"] = terms[:20]
        self._save_user_preferences()

    def record_package_view(self, pkg_name: str) -> None:
        """Record package view."""
        clean = pkg_name.strip()
        if not self.is_personalization_enabled() or not clean:
            return
        viewed: list[str] = self._user_prefs.setdefault("viewed_packages", [])
        if clean in viewed:
            viewed.remove(clean)
        viewed.insert(0, clean)
        self._user_prefs["viewed_packages"] = viewed[:30]
        self._save_user_preferences()

    def toggle_favorite(self, pkg_name: str) -> bool:
        """Toggle favorite status of a package."""
        clean = pkg_name.strip()
        if not clean:
            return False
        favs: list[str] = self._user_prefs.setdefault("favorites", [])
        if clean in favs:
            favs.remove(clean)
            is_fav = False
        else:
            favs.append(clean)
            is_fav = True
        self._save_user_preferences()
        return is_fav

    def is_favorite(self, pkg_name: str) -> bool:
        """Check if package is favorited."""
        return pkg_name.strip() in self._user_prefs.get("favorites", [])

    def get_favorites_count(self) -> int:
        """Return total favorites count."""
        return len(self._user_prefs.get("favorites", []))

    def has_personalization_history(self) -> bool:
        """Return True if user has any local activity history."""
        return bool(
            self._user_prefs.get("visited_categories")
            or self._user_prefs.get("search_terms")
            or self._user_prefs.get("viewed_packages")
            or self._user_prefs.get("favorites")
        )

    def _update_installed_cache_repos(self) -> None:
        """Resolve repository and source for all installed packages and invalidate package cache."""
        for inst_name, inst_pkg in self._installed_cache.items():
            if inst_name in self._official_repo_cache:
                inst_pkg.repository = self._official_repo_cache[inst_name].get("repository", "extra")
                inst_pkg.source = self._official_repo_cache[inst_name].get("source", "official")
            elif inst_name in KNOWN_APPLICATIONS_CATALOG:
                inst_pkg.repository = KNOWN_APPLICATIONS_CATALOG[inst_name].get("repository", "extra")
                inst_pkg.source = KNOWN_APPLICATIONS_CATALOG[inst_name].get("source", "official")
            elif inst_name in AUR_DISCOVERY_CANDIDATES:
                inst_pkg.repository = "aur"
                inst_pkg.source = "aur"
        self._package_cache.clear()

    # -------------------------------------------------------------------------
    # Indexing: Official Pacman Databases (/var/lib/pacman/sync/*.db)
    # -------------------------------------------------------------------------

    def _get_sync_cache_path(self) -> str:
        """Return path to persistent sync index JSON file."""
        cache_dir = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
        return os.path.join(cache_dir, "redshift-store", "sync_index_v2.json")

    def _init_official_sync_index(self) -> None:
        """Initialize sync index from cache or populate immediately and index in background."""
        if self.mock_mode:
            self.refresh_official_sync_db()
            return

        sync_cache_path = self._get_sync_cache_path()
        sync_dir = os.environ.get("REDSHIFT_PACMAN_SYNC_DIR", DEFAULT_PACMAN_SYNC_DIR)

        # Check if valid cached index exists on disk
        if os.path.isfile(sync_cache_path):
            try:
                with open(sync_cache_path, "r", encoding="utf-8") as f:
                    cached = json.load(f)
                signatures = cached.get("signatures", {})
                current_sigs = self._compute_sync_signatures(sync_dir)
                if signatures == current_sigs and "packages" in cached:
                    self._official_repo_cache = cached["packages"]
                    logger.info("Loaded %d official packages from sync cache in ~50ms", len(self._official_repo_cache))
                    return
            except Exception as e:
                logger.warning("Could not read sync cache: %s", e)

        # Cache missing or outdated: populate initially with known applications for immediate response
        self._official_repo_cache = dict(KNOWN_APPLICATIONS_CATALOG)
        # Trigger background indexing
        self.ensure_sync_index_loaded()

    def _compute_sync_signatures(self, sync_dir: str) -> dict[str, list[int]]:
        """Compute mtime and size signatures for all sync db files."""
        sigs: dict[str, list[int]] = {}
        if not os.path.isdir(sync_dir):
            return sigs
        for fname in sorted(os.listdir(sync_dir)):
            if fname.endswith(".db") and not fname.endswith(".sig"):
                fpath = os.path.join(sync_dir, fname)
                try:
                    st = os.stat(fpath)
                    sigs[fname] = [int(st.st_mtime), int(st.st_size)]
                except OSError:
                    pass
        return sigs

    def ensure_sync_index_loaded(self) -> None:
        """Trigger background thread to index official sync databases."""
        if self._is_indexing:
            return

        def _worker() -> None:
            self._is_indexing = True
            try:
                self.refresh_official_sync_db(force=False)
            finally:
                self._is_indexing = False
                if self._on_index_ready:
                    self._on_index_ready()

        t = threading.Thread(target=_worker, daemon=True)
        self._indexing_thread = t
        t.start()

    def wait_for_sync_index(self, timeout: float = 5.0) -> None:
        """Wait for background sync database indexing thread to complete if active."""
        if self._indexing_thread and self._indexing_thread.is_alive():
            self._indexing_thread.join(timeout=timeout)

    def refresh_official_sync_db(self, force: bool = False) -> dict[str, dict[str, Any]]:
        """Parse /var/lib/pacman/sync/*.db and cache index."""
        if self.mock_mode:
            # Populate mock official database with known catalog + technical libs
            mock_db: dict[str, dict[str, Any]] = dict(KNOWN_APPLICATIONS_CATALOG)
            for feat in FEATURED_PACKAGES_METADATA:
                if feat["source"] == "official":
                    mock_db[feat["name"]] = dict(feat)

            # Add technical packages (mostly NOT installed)
            tech_pkgs = [
                ("lib32-mesa", "32-bit OpenGL and Vulkan drivers", "multilib", "24.3.0-1"),
                ("linux-headers", "Header files and scripts for building modules for Linux kernel", "core", "6.12.0.arch1-1"),
                ("python-requests", "Python HTTP for Humans", "extra", "2.32.3-1"),
                ("zlib", "Compression library implementing the deflate compression method", "core", "1.3.1-1"),
                ("curl", "An URL retrieval utility and library", "core", "8.11.0-1"),
                ("cmake", "A cross-platform open-source make system", "extra", "3.31.0-1"),
                ("gcc", "The GNU Compiler Collection - C and C++ frontends", "core", "14.2.1-1"),
                ("rustup", "The Rust toolchain installer", "extra", "1.27.1-1"),
                ("nodejs", "Evented I/O for V8 JavaScript", "extra", "23.2.0-1"),
                ("python", "Next generation of the python high-level scripting language", "core", "3.13.0-1"),
            ]
            for p_name, p_desc, p_repo, p_ver in tech_pkgs:
                mock_db[p_name] = {
                    "name": p_name,
                    "display_name": p_name,
                    "summary": p_desc,
                    "description": p_desc,
                    "repository": p_repo,
                    "source": "official",
                    "version": p_ver,
                    "category": "development" if "build" in p_desc or "compiler" in p_desc else "system",
                    "is_application": False,
                }
            self._official_repo_cache = mock_db
            self._update_installed_cache_repos()
            return self._official_repo_cache

        sync_dir = os.environ.get("REDSHIFT_PACMAN_SYNC_DIR", DEFAULT_PACMAN_SYNC_DIR)
        if not os.path.isdir(sync_dir):
            self._unsynced_repos = True
            self._update_installed_cache_repos()
            return self._official_repo_cache

        sync_files = [
            os.path.join(sync_dir, f)
            for f in os.listdir(sync_dir)
            if f.endswith(".db") and not f.endswith(".sig")
        ]
        if not sync_files:
            self._unsynced_repos = True
            self._update_installed_cache_repos()
            return self._official_repo_cache

        sync_cache_path = self._get_sync_cache_path()
        current_sigs = self._compute_sync_signatures(sync_dir)

        with self._sync_index_lock:
            # Re-check persistent cache inside lock
            if not force and os.path.isfile(sync_cache_path):
                try:
                    with open(sync_cache_path, "r", encoding="utf-8") as f:
                        cached = json.load(f)
                    if cached.get("signatures") == current_sigs and "packages" in cached:
                        self._official_repo_cache = cached["packages"]
                        self._update_installed_cache_repos()
                        return self._official_repo_cache
                except Exception:
                    pass

            # Parse sync databases
            packages: dict[str, dict[str, Any]] = {}
            for db_path in sync_files:
                repo_name = os.path.basename(db_path).replace(".db", "")
                try:
                    with tarfile.open(db_path, "r:*") as tf:
                        for member in tf.getmembers():
                            if not member.name.endswith("/desc"):
                                continue
                            f = tf.extractfile(member)
                            if not f:
                                continue
                            content = f.read().decode("utf-8", errors="replace")
                            pkg_info = self._parse_pacman_sync_desc(content, repo_name)
                            if pkg_info and pkg_info.get("name"):
                                packages[pkg_info["name"]] = pkg_info
                except Exception as e:
                    logger.warning("Error parsing sync db %s: %s", db_path, e)

            if packages:
                self._official_repo_cache = packages
                self._unsynced_repos = False
                # Save cache atomically with unique temp file per thread/process
                try:
                    os.makedirs(os.path.dirname(sync_cache_path), exist_ok=True)
                    tmp_cache = f"{sync_cache_path}.{os.getpid()}.{threading.get_ident()}.tmp"
                    with open(tmp_cache, "w", encoding="utf-8") as f:
                        json.dump(
                            {"signatures": current_sigs, "packages": packages},
                            f,
                            ensure_ascii=False,
                        )
                    os.replace(tmp_cache, sync_cache_path)
                    logger.info("Saved %d official sync packages to %s", len(packages), sync_cache_path)
                except Exception as e:
                    logger.warning("Failed saving sync index cache: %s", e)

        self._update_installed_cache_repos()
        return self._official_repo_cache

    def _parse_pacman_sync_desc(self, content: str, repo_name: str) -> dict[str, Any] | None:
        """Parse single desc member from pacman sync db."""
        data: dict[str, Any] = {
            "repository": repo_name,
            "source": "official",
            "depends": [],
            "optdepends": [],
            "groups": [],
        }

        current_tag = ""
        for line in content.splitlines():
            line = line.strip()
            if line.startswith("%") and line.endswith("%"):
                current_tag = line[1:-1]
                continue
            if not line:
                continue

            if current_tag == "NAME":
                data["name"] = line
            elif current_tag == "VERSION":
                data["version"] = line
            elif current_tag == "DESC":
                data["summary"] = line
                data["description"] = line
            elif current_tag == "URL":
                data["url"] = line
            elif current_tag == "LICENSE":
                data["license"] = line
            elif current_tag == "CSIZE":
                try:
                    data["csize"] = int(line)
                except ValueError:
                    pass
            elif current_tag == "ISIZE":
                try:
                    data["isize"] = int(line)
                except ValueError:
                    pass
            elif current_tag == "BUILDDATE":
                try:
                    data["build_date"] = int(line)
                except ValueError:
                    pass
            elif current_tag == "PACKAGER":
                data["maintainer"] = line
            elif current_tag == "DEPENDS":
                data["depends"].append(line)
            elif current_tag == "OPTDEPENDS":
                data["optdepends"].append(line)
            elif current_tag == "GROUPS":
                data["groups"].append(line)

        name = data.get("name")
        if not name or not validate_package_name(name):
            return None

        return data

    # -------------------------------------------------------------------------
    # Indexing: Local Pacman Database (/var/lib/pacman/local)
    # -------------------------------------------------------------------------

    def refresh_installed(self) -> dict[str, PackageItem]:
        """Read and parse /var/lib/pacman/local/*/desc into PackageItem instances."""
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
        self._update_installed_cache_repos()
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
            "groups": [],
            "explicit": True,
            "installed": True,
            "source": "official",
            "repository": "local",
        }

        current_tag = ""
        for line in content.splitlines():
            line = line.strip()
            if line.startswith("%") and line.endswith("%"):
                current_tag = line[1:-1]
                continue
            if not line:
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
            elif current_tag == "BUILDDATE":
                try:
                    data["build_date"] = int(line)
                except ValueError:
                    pass
            elif current_tag == "REASON":
                data["explicit"] = line != "1"
            elif current_tag == "DEPENDS":
                data["depends"].append(line)
            elif current_tag == "OPTDEPENDS":
                data["optdepends"].append(line)
            elif current_tag == "GROUPS":
                data["groups"].append(line)

        name = data.get("name")
        if not name or not validate_package_name(name):
            return None

        # Enrich with desktop entries or AppStream
        meta = self._get_metadata_for_package(name)
        known = KNOWN_APPLICATIONS_CATALOG.get(name, {})
        display_name = known.get("display_name") or meta.get("display_name") or name.capitalize()
        icon_name = known.get("icon_name") or meta.get("icon_name") or ""
        summary = known.get("summary") or meta.get("summary") or data.get("summary", "")
        description = known.get("description") or meta.get("description") or data.get("description", "")
        category = known.get("category") or meta.get("category") or ""

        if not category or not icon_name:
            inferred_cat, inferred_icon = infer_category_and_icon(name, summary)
            if not category:
                category = inferred_cat
            if not icon_name:
                icon_name = inferred_icon

        pop_float, pop_src, pop_lbl = self.get_official_popularity(name)

        # Resolve repository and source from sync cache, known catalog, or AUR candidates
        repo = "local"
        src = "official"
        if name in self._official_repo_cache:
            repo = self._official_repo_cache[name].get("repository", "extra")
            src = self._official_repo_cache[name].get("source", "official")
        elif name in KNOWN_APPLICATIONS_CATALOG:
            repo = KNOWN_APPLICATIONS_CATALOG[name].get("repository", "extra")
            src = KNOWN_APPLICATIONS_CATALOG[name].get("source", "official")
        elif name in AUR_DISCOVERY_CANDIDATES:
            repo = "aur"
            src = "aur"

        data["repository"] = repo
        data["source"] = src
        data["display_name"] = display_name
        data["icon_name"] = icon_name
        data["category"] = category
        data["summary"] = summary
        data["description"] = description
        data["is_protected"] = is_protected_package(name)
        data["is_application"] = is_user_application(
            name, summary, data.get("groups", []), has_appstream_or_desktop=bool(meta)
        )
        data["app_id"] = meta.get("app_id", "")
        data["screenshots"] = meta.get("screenshots", [])
        data["popularity"] = pop_float
        data["popularity_source"] = pop_src
        data["popularity_label"] = pop_lbl
        data["provenance"] = "pacman_sync"
        data["provenance_label"] = "Instalado no sistema"
        data["is_favorite"] = self.is_favorite(name)

        return PackageItem.from_dict(data)

    # -------------------------------------------------------------------------
    # Metadata Enrichment: AppStream XML & .desktop files
    # -------------------------------------------------------------------------

    def _load_appstream_metadata(self) -> None:
        """Load AppStream metadata using gi.repository.AppStream and XML parser fallback."""
        if self.mock_mode:
            return

        # 1. Try gi.repository.AppStream
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
                key = (pkg_name or c_id.replace(".desktop", "")).lower()
                if not key:
                    continue

                summary = c.get_summary() or ""
                cat_list = c.get_categories() or []
                raw_cat = " ".join(cat_list) if cat_list else ""
                icon_val = ""
                icons = c.get_icons() if hasattr(c, "get_icons") else []
                if icons:
                    for ic in icons:
                        name_ic = ic.get_name() if hasattr(ic, "get_name") else ""
                        if name_ic:
                            icon_val = name_ic
                            break

                screenshots: list[str] = []
                if hasattr(c, "get_screenshots"):
                    for sc in c.get_screenshots():
                        if hasattr(sc, "get_images"):
                            for img in sc.get_images():
                                if hasattr(img, "get_url"):
                                    u = img.get_url()
                                    if u and u not in screenshots:
                                        screenshots.append(u)

                entry = {
                    "display_name": c.get_name() or "",
                    "summary": summary,
                    "description": c.get_description() or summary,
                    "icon_name": icon_val or c_id.replace(".desktop", ""),
                    "category": normalize_category(raw_cat),
                    "app_id": c_id,
                    "screenshots": screenshots,
                    "license": c.get_project_license() or "",
                }
                self._appstream_entries[key] = entry
                if pkg_name:
                    self._appstream_entries[pkg_name.lower()] = entry
        except Exception as e:
            logger.debug("AppStream gi introspection unavailable or partial: %s", e)

        # 2. Parse raw XML & XML.GZ files in AppStream directories
        xml_dirs: list[str] = []
        override_dir = os.environ.get("REDSHIFT_APPSTREAM_DIR")
        if override_dir:
            xml_dirs.append(override_dir)
        xml_dirs.extend([
            "/usr/share/swcatalog/xml",
            "/usr/share/app-info/xmls",
            "/usr/share/metainfo",
        ])

        for xdir in xml_dirs:
            if not os.path.isdir(xdir):
                continue
            for root, _, files in os.walk(xdir):
                for fname in files:
                    fpath = os.path.join(root, fname)
                    if fname.endswith(".xml.gz"):
                        self._parse_appstream_xml_file(fpath, is_gz=True)
                    elif fname.endswith(".xml"):
                        self._parse_appstream_xml_file(fpath, is_gz=False)

    def _parse_appstream_xml_file(self, fpath: str, is_gz: bool = False) -> None:
        """Parse AppStream XML/XML.GZ file using xml.etree.ElementTree."""
        try:
            if is_gz:
                with gzip.open(fpath, "rb") as gf:
                    tree = ET.parse(gf)
            else:
                tree = ET.parse(fpath)

            root = tree.getroot()
            components = root.findall(".//component")
            if not components and root.tag == "component":
                components = [root]

            for comp in components:
                pkgname_el = comp.find("pkgname")
                id_el = comp.find("id")
                name_el = comp.find("name")
                summary_el = comp.find("summary")
                desc_el = comp.find("description")
                license_el = comp.find("project_license")
                icon_el = comp.find("icon")
                cat_el = comp.find(".//category")

                pkg_name = pkgname_el.text.strip() if (pkgname_el is not None and pkgname_el.text) else ""
                c_id = id_el.text.strip() if (id_el is not None and id_el.text) else ""
                display_name = name_el.text.strip() if (name_el is not None and name_el.text) else ""
                summary = summary_el.text.strip() if (summary_el is not None and summary_el.text) else ""

                description = ""
                if desc_el is not None:
                    description = "".join(desc_el.itertext()).strip()

                icon_name = icon_el.text.strip() if (icon_el is not None and icon_el.text) else ""
                cat_els = comp.findall(".//category")
                category = " ".join([el.text.strip() for el in cat_els if el.text and el.text.strip()])
                license_str = license_el.text.strip() if (license_el is not None and license_el.text) else ""

                screenshots: list[str] = []
                for img_el in comp.findall(".//screenshot/image"):
                    if img_el.text and img_el.text.strip():
                        screenshots.append(img_el.text.strip())

                entry = {
                    "display_name": display_name,
                    "summary": summary,
                    "description": description or summary,
                    "icon_name": icon_name or c_id.replace(".desktop", ""),
                    "category": normalize_category(category),
                    "app_id": c_id,
                    "screenshots": screenshots,
                    "license": license_str,
                }

                if pkg_name:
                    self._appstream_entries[pkg_name.lower()] = entry
                if c_id:
                    clean_id = c_id.replace(".desktop", "").lower()
                    self._appstream_entries[clean_id] = entry
        except Exception:
            pass

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
                    "app_id": os.path.basename(path),
                }

                if file_base:
                    self._desktop_entries[file_base] = meta
                if base_exec and base_exec not in self._desktop_entries:
                    self._desktop_entries[base_exec] = meta
            except Exception:
                continue

    def _get_metadata_for_package(self, pkg_name: str) -> dict[str, Any]:
        """Lookup metadata in AppStream and desktop files with fallbacks."""
        key = pkg_name.lower()
        if key in self._appstream_entries:
            return self._appstream_entries[key]
        if key in self._desktop_entries:
            return self._desktop_entries[key]
        return {}

    # -------------------------------------------------------------------------
    # Popularity: pkgstats & AUR RPC
    # -------------------------------------------------------------------------

    def get_official_popularity(self, pkg_name: str) -> tuple[float, str, str]:
        """Return popularity percentage from pkgstats cache or baseline."""
        clean = pkg_name.strip()
        pop_float = PKGSTATS_BASELINE.get(clean, 0.0)

        # Check local cache
        cache_dir = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
        pstats_cache = os.path.join(cache_dir, "redshift-store", "pkgstats_cache.json")
        if os.path.isfile(pstats_cache):
            try:
                with open(pstats_cache, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    if clean in data:
                        pop_float = float(data[clean])
            except Exception:
                pass

        if pop_float > 0.0:
            return pop_float, "pkgstats", f"{pop_float:.1f}% pkgstats"
        return 0.0, "", ""

    # -------------------------------------------------------------------------
    # AUR: Discovery Sections, RPC & Batch Info
    # -------------------------------------------------------------------------

    def fetch_aur_info_batch(self, pkg_names: Sequence[str]) -> list[PackageItem]:
        """Query AUR RPC v5 info batch with disk caching."""
        names = [p.strip() for p in pkg_names if validate_package_name(p.strip())]
        if not names:
            return []

        if self.mock_mode:
            items: list[PackageItem] = []
            for n in names:
                if n in AUR_DISCOVERY_CANDIDATES:
                    c = AUR_DISCOVERY_CANDIDATES[n]
                    item = PackageItem(
                        name=n,
                        display_name=c.get("display_name", n),
                        summary=c.get("summary", ""),
                        description=c.get("description", ""),
                        version=c.get("version", "1.0.0-1"),
                        repository="aur",
                        source="aur",
                        installed=n in self._installed_cache,
                        category=c.get("category", "utilities"),
                        icon_name=c.get("icon_name", "application-x-executable"),
                        votes=c.get("votes", 100),
                        popularity=c.get("popularity", 5.0),
                        popularity_source="aur_rpc",
                        popularity_label=f"{c.get('votes', 100)} votos · pop {c.get('popularity', 5.0):.1f}",
                        provenance="aur_popular",
                        provenance_label="Popular na comunidade AUR",
                        is_favorite=self.is_favorite(n),
                    )
                    items.append(item)
            return items

        cache_dir = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
        aur_cache_file = os.path.join(cache_dir, "redshift-store", "aur_discovery_cache.json")
        cached_data: dict[str, Any] = {}
        now = time.time()

        if os.path.isfile(aur_cache_file):
            try:
                with open(aur_cache_file, "r", encoding="utf-8") as f:
                    cached_data = json.load(f)
            except Exception:
                pass

        # Check if any requested items are missing or expired in cache
        needed: list[str] = []
        for n in names:
            c_entry = cached_data.get(n)
            if not c_entry or (now - c_entry.get("_cached_at", 0) > 21600):
                needed.append(n)

        if needed:
            def _fetch_aur_worker(pkgs_to_fetch: list[str]) -> None:
                query_params = [("v", "5"), ("type", "info")]
                for n in pkgs_to_fetch:
                    query_params.append(("arg[]", n))
                url = f"{AUR_RPC_INFO_URL}?{urllib.parse.urlencode(query_params)}"
                req = urllib.request.Request(url, headers={"User-Agent": "RedshiftStore/2.0"})
                try:
                    with urllib.request.urlopen(req, timeout=5) as resp:
                        resp_json = json.loads(resp.read().decode("utf-8", errors="replace"))
                        cur_now = time.time()
                        for r in resp_json.get("results", []):
                            r_name = r.get("Name")
                            if r_name:
                                r["_cached_at"] = cur_now
                                cached_data[r_name] = r
                    os.makedirs(os.path.dirname(aur_cache_file), exist_ok=True)
                    tmp_f = f"{aur_cache_file}.{os.getpid()}.{threading.get_ident()}.tmp"
                    with open(tmp_f, "w", encoding="utf-8") as f:
                        json.dump(cached_data, f, ensure_ascii=False)
                    os.replace(tmp_f, aur_cache_file)
                except Exception as e:
                    logger.debug("Background AUR RPC query failed: %s", e)
                    self.last_network_error = True

            threading.Thread(target=_fetch_aur_worker, args=(needed,), daemon=True).start()

        results: list[PackageItem] = []
        for n in names:
            r = cached_data.get(n)
            c = AUR_DISCOVERY_CANDIDATES.get(n, {})
            inst = self._installed_cache.get(n)

            if r:
                votes = int(r.get("NumVotes", 0))
                pop = float(r.get("Popularity", 0.0))
                desc = r.get("Description") or c.get("summary") or ""
                version = r.get("Version") or c.get("version") or ""
                url = r.get("URL") or ""
                maintainer = r.get("Maintainer") or c.get("maintainer") or ""
            else:
                votes = int(c.get("votes", 0))
                pop = float(c.get("popularity", 0.0))
                desc = c.get("summary", "")
                version = c.get("version", "")
                url = c.get("url", "")
                maintainer = c.get("maintainer", "")

            meta = self._get_metadata_for_package(n)
            cat, icon = infer_category_and_icon(n, desc)

            item = PackageItem(
                name=n,
                display_name=c.get("display_name") or meta.get("display_name") or n,
                summary=desc,
                description=c.get("description") or meta.get("description") or desc,
                version=version,
                installed_version=inst.installed_version if inst else "",
                repository="aur",
                source="aur",
                installed=inst is not None,
                explicit=inst.explicit if inst else False,
                category=c.get("category") or meta.get("category") or cat,
                icon_name=c.get("icon_name") or meta.get("icon_name") or icon,
                url=url,
                votes=votes,
                popularity=pop,
                maintainer=maintainer,
                is_protected=is_protected_package(n),
                is_application=True,
                popularity_source="aur_rpc",
                popularity_label=f"{votes} votos · pop {pop:.1f}",
                provenance="aur_popular",
                provenance_label="Popular na comunidade AUR",
                is_favorite=self.is_favorite(n),
            )
            results.append(item)

        return results

    def get_aur_discovery_sections(self) -> dict[str, list[PackageItem]]:
        """Return 6 curated discovery sections for the AUR page."""
        sections = {
            "aur_popular": [
                "visual-studio-code-bin",
                "zen-browser-bin",
                "brave-bin",
                "spotify",
                "vesktop-bin",
                "localsend-bin",
                "obsidian-bin",
                "google-chrome",
            ],
            "aur_community": [
                "paru",
                "yay",
                "bottles",
                "peazip",
                "ventoy-bin",
                "freetube-bin",
                "feishin-bin",
                "stremio",
            ],
            "aur_development": [
                "vscodium-bin",
                "cursor-bin",
                "sublime-text-4",
                "postman-bin",
                "insomnia-bin",
                "github-desktop-bin",
                "lazydocker-bin",
            ],
            "aur_games": [
                "heroic-games-launcher-bin",
                "protonup-qt-bin",
                "r2modman-bin",
                "osu-lazer-bin",
                "minecraft-launcher",
            ],
            "aur_productivity": [
                "onlyoffice-bin",
                "logseq-desktop-bin",
                "anytype-bin",
                "joplin-desktop",
                "1password",
            ],
            "aur_curated": [
                "zen-browser-bin",
                "localsend-bin",
                "obsidian-bin",
                "heroic-games-launcher-bin",
                "vesktop-bin",
                "spotify",
            ],
        }

        all_names = list({n for names in sections.values() for n in names})
        items_list = self.fetch_aur_info_batch(all_names)
        items_by_name = {it.name: it for it in items_list}

        result: dict[str, list[PackageItem]] = {}
        for sec_id, names in sections.items():
            result[sec_id] = [items_by_name[n] for n in names if n in items_by_name]

        return result

    def get_aur_discovery_packages(self) -> list[PackageItem]:
        """Return flat list of unique AUR discovery packages."""
        sections = self.get_aur_discovery_sections()
        seen: set[str] = set()
        flat: list[PackageItem] = []
        for items in sections.values():
            for it in items:
                if it.name not in seen:
                    seen.add(it.name)
                    flat.append(it)
        return flat

    # -------------------------------------------------------------------------
    # Home Page: 8 Dynamic Sections with Privacy-Preserving Personalization
    # -------------------------------------------------------------------------

    def get_home_sections(self) -> dict[str, list[PackageItem]]:
        """Return 8 independent sections for the Redshift Store Home page."""
        sections: dict[str, list[PackageItem]] = {}

        # 1. Featured
        sections["featured"] = self.get_featured_packages()

        # 2. Recommended (Personalized or Curated fallback)
        sections["recommended"] = self._build_recommended_section()

        # 3. Popular
        popular_candidates = [
            "git",
            "firefox",
            "vlc",
            "mpv",
            "steam",
            "neovim",
            "gimp",
            "btop",
            "fastfetch",
            "visual-studio-code-bin",
            "spotify",
            "zen-browser-bin",
            "paru",
            "discord",
            "libreoffice-fresh",
        ]
        sections["popular"] = [
            p for n in popular_candidates if (p := self.get_package(n)) is not None
        ]

        # 4. Getting Started
        getting_started_candidates = [
            "firefox",
            "kitty",
            "fastfetch",
            "btop",
            "keepassxc",
            "flameshot",
            "vlc",
            "telegram-desktop",
            "ark",
            "7zip",
        ]
        sections["getting_started"] = [
            p for n in getting_started_candidates if (p := self.get_package(n)) is not None
        ]
        for p in sections["getting_started"]:
            p.provenance_label = "Essencial pós-instalação do Redshift OS"

        # 5. Development
        dev_candidates = [
            "neovim",
            "code",
            "zed",
            "kate",
            "visual-studio-code-bin",
            "git",
            "lazygit",
            "meld",
            "docker",
            "podman",
            "dbeaver",
            "qtcreator",
        ]
        sections["development"] = [
            p for n in dev_candidates if (p := self.get_package(n)) is not None
        ]

        # 6. Games
        games_candidates = [
            "steam",
            "lutris",
            "heroic-games-launcher-bin",
            "mangohud",
            "gamemode",
            "goverlay",
            "retroarch",
            "0ad",
            "supertuxkart",
            "prismlauncher",
            "dolphin-emu",
        ]
        sections["games"] = [
            p for n in games_candidates if (p := self.get_package(n)) is not None
        ]

        # 7. Design
        design_candidates = [
            "blender",
            "gimp",
            "inkscape",
            "krita",
            "darktable",
            "freecad",
            "kdenlive",
            "obs-studio",
            "audacity",
            "rawtherapee",
            "scribus",
        ]
        sections["design"] = [
            p for n in design_candidates if (p := self.get_package(n)) is not None
        ]

        # 8. Communication
        comm_candidates = [
            "firefox",
            "telegram-desktop",
            "discord",
            "thunderbird",
            "signal-desktop",
            "element-desktop",
            "zen-browser-bin",
            "neochat",
            "qbittorrent",
        ]
        sections["communication"] = [
            p for n in comm_candidates if (p := self.get_package(n)) is not None
        ]

        return sections

    def _build_recommended_section(self) -> list[PackageItem]:
        """Build transparent personalized recommendations prioritizing non-installed apps."""
        results: list[PackageItem] = []
        seen: set[str] = set()

        # Combine candidate universe from known applications catalog and curated AUR candidates
        candidate_universe: dict[str, dict[str, Any]] = {
            **KNOWN_APPLICATIONS_CATALOG,
            **AUR_DISCOVERY_CANDIDATES,
        }

        if self.is_personalization_enabled():
            # 1. Favorites signal
            favs = self._user_prefs.get("favorites", [])
            for f_name in favs[:3]:
                f_pkg = self.get_package(f_name)
                if f_pkg:
                    for k, v in candidate_universe.items():
                        if v.get("category") == f_pkg.category and k != f_name and k not in seen and k not in favs:
                            p = self.get_package(k)
                            if p and not p.installed:
                                p.provenance = "personalized"
                                p.provenance_label = "Relacionado a aplicativos que você favoritou"
                                results.append(p)
                                seen.add(k)
                                if len(results) >= 3:
                                    break

            # 2. Viewed packages signal
            viewed = self._user_prefs.get("viewed_packages", [])
            for v_name in viewed[:3]:
                v_pkg = self.get_package(v_name)
                if v_pkg:
                    for k, v in candidate_universe.items():
                        if v.get("category") == v_pkg.category and k != v_name and k not in seen:
                            p = self.get_package(k)
                            if p and not p.installed:
                                p.provenance = "personalized"
                                p.provenance_label = "Semelhante a aplicativos visualizados recentemente"
                                results.append(p)
                                seen.add(k)
                                if len(results) >= 5:
                                    break

            # 3. Search terms signal
            terms = self._user_prefs.get("search_terms", [])
            for q in terms[:3]:
                for k, v in candidate_universe.items():
                    disp = v.get("display_name", "")
                    summ = v.get("summary", "")
                    if (q in k or q in summ.lower() or q in disp.lower()) and k not in seen:
                        p = self.get_package(k)
                        if p and not p.installed:
                            p.provenance = "personalized"
                            p.provenance_label = f"Relacionado à sua pesquisa '{q}'"
                            results.append(p)
                            seen.add(k)
                            if len(results) >= 6:
                                break

            # 4. Visited categories signal
            visited = self._user_prefs.get("visited_categories", {})
            if visited:
                top_cats = sorted(visited.items(), key=lambda x: x[1], reverse=True)
                for cat_name, _ in top_cats[:2]:
                    for k, v in candidate_universe.items():
                        if v.get("category") == cat_name and k not in seen:
                            p = self.get_package(k)
                            if p and not p.installed:
                                p.provenance = "personalized"
                                p.provenance_label = "Relacionado às categorias que você explora"
                                results.append(p)
                                seen.add(k)
                                if len(results) >= 7:
                                    break

            # 5. Explicitly installed applications categories signal
            if len(results) < 8:
                installed_app_cats = {
                    p.category
                    for p in self._installed_cache.values()
                    if p.installed and p.explicit and p.is_application and p.category
                }
                for cat in sorted(installed_app_cats):
                    for k, v in candidate_universe.items():
                        if v.get("category") == cat and k not in seen:
                            p = self.get_package(k)
                            if p and not p.installed:
                                p.provenance = "personalized"
                                p.provenance_label = "Baseado nos aplicativos que você usa"
                                results.append(p)
                                seen.add(k)
                                if len(results) >= 8:
                                    break
                    if len(results) >= 8:
                        break

        # Fallback to curated recommendations if none found or fewer than 8
        if len(results) < 8:
            curated_defaults = [
                "zen-browser-bin",
                "localsend-bin",
                "obsidian-bin",
                "krita",
                "blender",
                "heroic-games-launcher-bin",
                "keepassxc",
                "fastfetch",
                "vscodium-bin",
                "mpv",
                "vesktop-bin",
                "flameshot",
            ]
            for n in curated_defaults:
                if n not in seen:
                    pkg = self.get_package(n)
                    if pkg:
                        seen.add(pkg.name)
                        pkg.provenance = "editorial"
                        pkg.provenance_label = "Selecionado pela curadoria Redshift OS"
                        results.append(pkg)
                        if len(results) >= 8:
                            break

        # Prioritize non-installed apps in recommendations
        results.sort(key=lambda x: (x.installed, -x.popularity))
        return results[:8]

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
        """Find a package by name from installed, sync repo or AUR caches."""
        if not name:
            return None
        clean_name = name.strip()

        # Check item cache
        if not repository and clean_name in self._package_cache:
            return self._package_cache[clean_name]

        # 1. Check installed cache first
        if clean_name in self._installed_cache:
            self._package_cache[clean_name] = self._installed_cache[clean_name]
            return self._installed_cache[clean_name]

        # 2. Check official repo cache
        if clean_name in self._official_repo_cache:
            repo_info = self._official_repo_cache[clean_name]
            meta = self._get_metadata_for_package(clean_name)
            known = KNOWN_APPLICATIONS_CATALOG.get(clean_name, {})
            cat, icon = infer_category_and_icon(
                clean_name, meta.get("summary") or repo_info.get("summary", "")
            )
            pop_float, pop_src, pop_lbl = self.get_official_popularity(clean_name)

            pkg = PackageItem(
                name=clean_name,
                display_name=known.get("display_name") or meta.get("display_name") or repo_info.get("display_name") or clean_name,
                summary=known.get("summary") or meta.get("summary") or repo_info.get("summary", ""),
                description=known.get("description") or meta.get("description") or repo_info.get("description", ""),
                version=repo_info.get("version", ""),
                repository=repo_info.get("repository", "extra"),
                source="official",
                installed=False,
                category=known.get("category") or meta.get("category") or repo_info.get("category") or cat,
                icon_name=known.get("icon_name") or meta.get("icon_name") or repo_info.get("icon_name") or icon,
                installed_size=format_size(repo_info.get("isize")),
                download_size=format_size(repo_info.get("csize")),
                license=repo_info.get("license", ""),
                url=repo_info.get("url", ""),
                depends=list(repo_info.get("depends", [])),
                optdepends=list(repo_info.get("optdepends", [])),
                build_date=repo_info.get("build_date", 0),
                groups=list(repo_info.get("groups", [])),
                is_protected=is_protected_package(clean_name),
                is_application=is_user_application(
                    clean_name,
                    repo_info.get("summary", ""),
                    repo_info.get("groups", []),
                    has_appstream_or_desktop=bool(meta),
                ),
                app_id=meta.get("app_id", ""),
                screenshots=meta.get("screenshots", []),
                popularity=pop_float,
                popularity_source=pop_src,
                popularity_label=pop_lbl,
                provenance="pacman_sync",
                provenance_label="Repositório oficial do Arch Linux",
                is_favorite=self.is_favorite(clean_name),
            )
            self._package_cache[clean_name] = pkg
            return pkg

        # 3. Check featured metadata fallback
        for feat in FEATURED_PACKAGES_METADATA:
            if feat["name"] == clean_name:
                item = PackageItem.from_dict(dict(feat))
                item.installed = False
                item.is_application = True
                item.provenance = "editorial"
                item.provenance_label = "Selecionado pela curadoria Redshift OS"
                item.is_favorite = self.is_favorite(clean_name)
                pop_float, pop_src, pop_lbl = self.get_official_popularity(clean_name)
                item.popularity = pop_float or feat.get("popularity", 0.0)
                item.popularity_source = pop_src or ("aur_rpc" if feat.get("source") == "aur" else "")
                item.popularity_label = pop_lbl or (f"{feat.get('votes', 0)} votos · pop {feat.get('popularity', 0.0):.1f}" if feat.get("source") == "aur" else "")
                self._package_cache[clean_name] = item
                return item

        # 4. Check AUR candidates or query AUR
        if clean_name in AUR_DISCOVERY_CANDIDATES:
            batch = self.fetch_aur_info_batch([clean_name])
            if batch:
                self._package_cache[clean_name] = batch[0]
                return batch[0]

        if repository == "aur" or clean_name.endswith("-bin") or clean_name.endswith("-git"):
            aur_results = self.search_aur(clean_name, limit=5)
            for res in aur_results:
                if res.name == clean_name:
                    self._package_cache[clean_name] = res
                    return res

        return None

    def get_featured_packages(self) -> list[PackageItem]:
        """Return curated list of featured applications synchronized with system status."""
        items: list[PackageItem] = []
        for feat in FEATURED_PACKAGES_METADATA:
            name = feat["name"]
            is_inst = name in self._installed_cache
            inst_item = self._installed_cache.get(name)

            pop_float, pop_src, pop_lbl = self.get_official_popularity(name)
            if not pop_src and feat.get("source") == "aur":
                pop_src = "aur_rpc"
                pop_lbl = f"{feat.get('votes', 0)} votos · pop {feat.get('popularity', 0.0):.1f}"

            version_val = ""
            if inst_item and inst_item.version:
                version_val = inst_item.version
            elif self._official_repo_cache.get(name, {}).get("version"):
                version_val = self._official_repo_cache[name]["version"]
            elif name in AUR_DISCOVERY_CANDIDATES and AUR_DISCOVERY_CANDIDATES[name].get("version"):
                version_val = AUR_DISCOVERY_CANDIDATES[name]["version"]
            else:
                version_val = feat.get("version", "latest")

            pkg = PackageItem(
                name=name,
                display_name=feat["display_name"],
                summary=feat["summary"],
                description=feat["description"],
                version=version_val,
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
                is_application=True,
                popularity=pop_float or feat.get("popularity", 0.0),
                popularity_source=pop_src,
                popularity_label=pop_lbl,
                provenance="featured",
                provenance_label="Selecionado pela curadoria Redshift OS",
                is_favorite=self.is_favorite(name),
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
            if res.returncode == 0 and res.stdout:
                for line in res.stdout.splitlines():
                    parts = line.strip().split()
                    if len(parts) >= 4 and parts[2] == "->":
                        pkgname, old_ver, _, new_ver = parts[0], parts[1], parts[2], parts[3]
                        if not validate_package_name(pkgname):
                            continue
                        # Verify using ALPM version comparison that new_ver is strictly newer
                        if alpm_vercmp(new_ver, old_ver) <= 0:
                            logger.debug("Skipping non-upgrade candidate according to ALPM: %s %s -> %s", pkgname, old_ver, new_ver)
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
                                is_application=is_user_application(pkgname, inst_item.summary if inst_item else "", has_appstream_or_desktop=bool(meta)),
                                is_favorite=self.is_favorite(pkgname),
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
                        if alpm_vercmp(new_ver, old_ver) <= 0:
                            logger.debug("Skipping non-upgrade AUR candidate according to ALPM: %s %s -> %s", pkgname, old_ver, new_ver)
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
                                is_application=True,
                                is_favorite=self.is_favorite(pkgname),
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

        if self.mock_mode:
            return self._get_mock_aur_results(clean_query, limit)

        cache_key = clean_query.lower()
        now = time.time()
        if cache_key in self._aur_cache:
            ts, cached_items = self._aur_cache[cache_key]
            if now - ts < self._aur_cache_ttl:
                return cached_items

        url = AUR_RPC_SEARCH_URL.format(query=urllib.parse.quote(clean_query))
        req = urllib.request.Request(url, headers={"User-Agent": "RedshiftStore/2.0"})

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
                        popularity_source="aur_rpc",
                        popularity_label=f"{votes} votos · pop {pop:.1f}",
                        provenance="aur_popular",
                        provenance_label="Popular na comunidade AUR",
                        maintainer=maintainer,
                        is_protected=is_protected_package(name),
                        is_application=True,
                        is_favorite=self.is_favorite(name),
                    )
                    items.append(pkg)
        except Exception as e:
            logger.warning("AUR RPC query error for %r: %s", clean_query, e)
            self.last_network_error = True

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
        req = urllib.request.Request(url, headers={"User-Agent": "RedshiftStore/2.0"})

        try:
            with urllib.request.urlopen(req, timeout=5) as resp:
                content = resp.read().decode("utf-8", errors="replace")
                return content
        except Exception as e:
            logger.warning("Error fetching PKGBUILD for %r: %s", clean_name, e)
            return f"# Redshift Store: Falha ao obter PKGBUILD para {clean_name}\n# Erro: {e}"

    # -------------------------------------------------------------------------
    # Unified Search, Multi-Tier Ranking & Catalog Exploration
    # -------------------------------------------------------------------------

    def search_catalog(
        self,
        query: str = "",
        source_filter: str = "all",
        category_filter: str = "all",
        installed_filter: str = "all",
        apps_only: bool = True,
        sort_by: str = "relevance",
        offset: int = 0,
        limit: int = 60,
    ) -> dict[str, Any]:
        """Search catalog across pacman sync, installed and AUR with ranking."""
        clean_query = query.strip().lower()
        candidates: dict[str, PackageItem] = {}

        # 1. Official Sync Repositories & Known Applications
        if source_filter != "aur":
            for name, repo_info in self._official_repo_cache.items():
                meta_entry = self._get_metadata_for_package(name)
                known_entry = KNOWN_APPLICATIONS_CATALOG.get(name, {})
                has_app_entry = bool(meta_entry) or bool(known_entry)
                summ = meta_entry.get("summary") or known_entry.get("summary") or repo_info.get("summary", "")

                if apps_only:
                    if not is_user_application(
                        name,
                        summ,
                        repo_info.get("groups", []),
                        has_appstream_or_desktop=has_app_entry,
                    ):
                        continue

                disp = meta_entry.get("display_name") or known_entry.get("display_name") or repo_info.get("display_name") or name
                desc = meta_entry.get("description") or known_entry.get("description") or repo_info.get("description", "")
                app_id = meta_entry.get("app_id", "")

                if clean_query:
                    searchable = f"{name} {disp} {summ} {desc} {app_id}".lower()
                    if clean_query not in searchable:
                        continue

                if category_filter != "all":
                    pkg_cat = meta_entry.get("category") or known_entry.get("category") or repo_info.get("category")
                    if not pkg_cat:
                        pkg_cat, _ = infer_category_and_icon(name, summ)
                    if pkg_cat != category_filter:
                        continue

                pkg = self.get_package(name)
                if pkg and self._matches_filters(pkg, clean_query, source_filter, category_filter, installed_filter, apps_only):
                    candidates[pkg.name] = pkg

        # 2. Installed Packages
        for name, inst in self._installed_cache.items():
            if self._matches_filters(inst, clean_query, source_filter, category_filter, installed_filter, apps_only):
                if inst.name not in candidates:
                    candidates[inst.name] = inst

        # 3. Featured Packages
        for feat in self.get_featured_packages():
            if self._matches_filters(feat, clean_query, source_filter, category_filter, installed_filter, apps_only):
                if feat.name not in candidates:
                    candidates[feat.name] = feat

        # 4. AUR (Search or Discovery)
        if source_filter in ("all", "aur"):
            if clean_query:
                aur_items = self.search_aur(clean_query, limit=40)
                for a_item in aur_items:
                    if self._matches_filters(a_item, clean_query, source_filter, category_filter, installed_filter, apps_only):
                        if a_item.name not in candidates or candidates[a_item.name].provenance in ("featured", "editorial"):
                            candidates[a_item.name] = a_item
            else:
                for a_item in self.get_aur_discovery_packages():
                    if self._matches_filters(a_item, clean_query, source_filter, category_filter, installed_filter, apps_only):
                        if a_item.name not in candidates or candidates[a_item.name].provenance in ("featured", "editorial"):
                            candidates[a_item.name] = a_item

        # Ranking
        ranked_list = list(candidates.values())
        if sort_by == "relevance":
            ranked_list.sort(
                key=lambda p: (
                    -self._calculate_relevance_score(p, clean_query),
                    not p.is_application,
                    -p.popularity,
                    p.name.lower(),
                )
            )
        elif sort_by == "popularity":
            ranked_list.sort(key=lambda p: (-p.popularity, -p.votes, p.name.lower()))
        elif sort_by == "name":
            ranked_list.sort(key=lambda p: ((p.display_name or p.name).lower(), p.name.lower()))
        elif sort_by == "recent":
            ranked_list.sort(key=lambda p: (-p.build_date, -p.popularity, p.name.lower()))

        total = len(ranked_list)
        paged = ranked_list[offset : offset + limit]
        has_more = (offset + limit) < total

        status = "ready"
        message = ""
        if total == 0:
            if self.last_network_error and (source_filter == "aur" or not self._unsynced_repos):
                status = "network_error"
                message = "Não foi possível conectar aos servidores do AUR."
            elif self._unsynced_repos and source_filter in ("all", "official"):
                status = "unsynced_repos"
                message = "Repositórios do Arch Linux não sincronizados. Execute 'yay -Sy'."
            elif category_filter != "all":
                status = "empty_category"
                message = f"Nenhum pacote encontrado na categoria '{category_filter}'."
            else:
                status = "no_results"
                message = "Nenhum aplicativo encontrado para os filtros selecionados."

        return {
            "items": paged,
            "total": total,
            "has_more": has_more,
            "status": status,
            "message": message,
        }

    def search(
        self,
        query: str = "",
        source_filter: str = "all",
        category_filter: str = "all",
        limit: int = 50,
        installed_filter: str = "all",
        apps_only: bool = False,
        sort_by: str = "relevance",
        offset: int = 0,
    ) -> list[PackageItem]:
        """Search catalog and return flat list of PackageItem instances."""
        res = self.search_catalog(
            query=query,
            source_filter=source_filter,
            category_filter=category_filter,
            installed_filter=installed_filter,
            apps_only=apps_only,
            sort_by=sort_by,
            offset=offset,
            limit=limit,
        )
        return res["items"]

    def _calculate_relevance_score(self, pkg: PackageItem, query: str) -> int:
        """Calculate multi-tier relevance score for a package."""
        if not query:
            base = 100
            if pkg.is_application:
                base += 50
            if not pkg.installed and pkg.is_application:
                base += 45
            if pkg.name in KNOWN_APPLICATIONS_CATALOG or pkg.name in AUR_DISCOVERY_CANDIDATES:
                base += 25
            return base + int(min(pkg.popularity, 50.0))

        q = query.lower()
        score = 0
        p_name = pkg.name.lower()
        p_disp = (pkg.display_name or "").lower()

        # Tier 1: Exact name match
        if p_name == q:
            return 1000

        # Tier 2: Exact display name match
        if p_disp == q:
            return 900

        # Tier 3: Prefix match
        if p_name.startswith(q) or p_disp.startswith(q):
            score += 700

        # Tier 4: Substring in name or display_name
        elif q in p_name or q in p_disp:
            score += 550

        # Tier 5: Substring in summary, description or app_id
        elif q in (pkg.summary or "").lower() or q in (pkg.description or "").lower() or q in (pkg.app_id or "").lower():
            score += 350

        # Tier 6: Category match
        if q in (pkg.category or "").lower():
            score += 200

        # App boost
        if pkg.is_application:
            score += 100

        # Popularity bonus
        score += int(min(pkg.popularity, 100.0))

        return score

    def _matches_filters(
        self,
        pkg: PackageItem,
        query: str,
        source_filter: str,
        category_filter: str,
        installed_filter: str = "all",
        apps_only: bool = False,
    ) -> bool:
        """Check if package matches query string and all active filters."""
        if source_filter != "all" and pkg.source != source_filter:
            return False

        if category_filter != "all" and pkg.category != category_filter:
            return False

        if installed_filter == "installed" and not pkg.installed:
            return False
        if installed_filter == "not_installed" and pkg.installed:
            return False

        if apps_only and not pkg.is_application:
            return False

        if not query:
            return True

        known = KNOWN_APPLICATIONS_CATALOG.get(pkg.name, {})
        text_to_search = f"{pkg.name} {pkg.display_name} {pkg.summary} {pkg.description} {pkg.app_id} {known.get('summary', '')} {known.get('description', '')}".lower()
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
                is_application=True,
                popularity=69.13,
                popularity_source="pkgstats",
                popularity_label="69.1% pkgstats",
                provenance="pacman_sync",
                provenance_label="Instalado no sistema",
                is_favorite=self.is_favorite("firefox"),
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
                is_application=True,
                popularity=34.6,
                popularity_source="pkgstats",
                popularity_label="34.6% pkgstats",
                provenance="pacman_sync",
                provenance_label="Instalado no sistema",
                is_favorite=self.is_favorite("kitty"),
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
                is_application=True,
                votes=1711,
                popularity=13.01,
                popularity_source="aur_rpc",
                popularity_label="1.711 votos · pop 13.0",
                provenance="aur_popular",
                provenance_label="Popular na comunidade AUR",
                is_favorite=self.is_favorite("visual-studio-code-bin"),
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
                is_application=False,
                provenance="pacman_sync",
                provenance_label="Instalado no sistema",
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
                is_application=False,
                provenance="pacman_sync",
                provenance_label="Instalado no sistema",
            ),
            PackageItem(
                name="simdjson",
                display_name="simdjson",
                summary="Parsing gigabytes of JSON per second",
                version="1:5.0.5-1",
                installed_version="1:5.0.5-1",
                repository="extra",
                source="official",
                installed=True,
                explicit=False,
                category="development",
                icon_name="applications-development",
                is_protected=False,
                is_application=False,
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
                is_application=True,
                popularity=69.13,
                popularity_source="pkgstats",
                popularity_label="69.1% pkgstats",
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
                is_application=True,
                votes=1711,
                popularity=13.01,
                popularity_source="aur_rpc",
                popularity_label="1.711 votos · pop 13.0",
            ),
            PackageItem(
                name="simdjson",
                display_name="simdjson",
                summary="Parsing gigabytes of JSON per second",
                version="2:5.0.5-1",
                installed_version="1:5.0.5-1",
                repository="extra",
                source="official",
                installed=True,
                update_available=True,
                category="development",
                icon_name="applications-development",
                installed_size="1.2 MiB",
                is_application=False,
            ),
        ]

    def _get_mock_aur_results(self, query: str, limit: int) -> list[PackageItem]:
        """Return deterministic mock AUR search results."""
        candidates = self.get_aur_discovery_packages()
        q = query.lower()
        filtered = [c for c in candidates if q in c.name.lower() or q in (c.summary or "").lower()]
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
