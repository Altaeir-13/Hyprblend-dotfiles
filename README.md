# Hyprland Hybrid Rice

> **Ambiente Wayland híbrido moderno, fluido e esteticamente refinado, integrando o poder do [end-4/illogical-impulse](https://github.com/end-4/dots-hyprland) com a sofisticação do [Caelestia Shell](https://github.com/caelestia-dots/shell).**

[![Arch Linux](https://img.shields.io/badge/Arch_Linux-Officially_Supported-1793D1?logo=arch-linux&logoColor=white)](https://archlinux.org)
[![Hyprland](https://img.shields.io/badge/Compositor-Hyprland-00c8ff?logo=wayland&logoColor=white)](https://hyprland.org)
[![Quickshell](https://img.shields.io/badge/Shell-Quickshell_Qt6-41CD52?logo=qt&logoColor=white)](https://quickshell.outfoxxed.me)
[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](./LICENSE)
[![Status: v0.1.0--beta](https://img.shields.io/badge/Release-v0.1.0--beta-green.svg)](#)

---

## Visão Geral

O **Hyprland Hybrid Rice** une o melhor de dois ecossistemas visuais líderes para Hyprland em um ambiente único e coeso:
- **end-4 (illogical-impulse):** Rica central de controle (`StatusCenter`), widgets funcionais, extração dinâmica de cores Material You e ampla compatibilidade.
- **Caelestia Shell:** Design escultural em Material 3, animações baseadas em física vetorial, shaders fluidos e suporte avançado a papéis de parede animados.

A alternância entre as duas interfaces ocorre em **tempo de execução com um único clique ou atalho**, preservando o estado do compositor, a paleta de cores ativas e os atalhos de hardware.

---

## Capturas de Tela

### 1. Interface end-4 (illogical-impulse)
![Área de Trabalho end-4](./docs/screenshots/hybrid-end4-desktop.png)
*Barra dinâmica com botão dedicado de troca de frontend, central de notificações e StatusCenter integrado.*

### 2. Interface Caelestia Shell
![Área de Trabalho Caelestia](./docs/screenshots/hybrid-caelestia-desktop.png)
*Widgets esculturais, dock flutuante, shaders de blobs e sincronização contínua com a paleta Material You.*

### 3. Alternância Reversa e Estabilidade
![Retorno para end-4](./docs/screenshots/hybrid-end4-switched-back.png)
*Transição suave e restauração instantânea do estado operacional sem perda de janelas ativas.*

---

## Características Principais

- 🔄 **Dual Frontend em Tempo Real:** Alterne dinamicamente entre `end-4` e `Caelestia` via botão na barra ou pelo comando `ui-switch.sh`.
- 🛡️ **Mecanismo de Rollback da Interface:** Se o frontend secundário apresentar qualquer falha de inicialização ou crash de dependência, o sistema reverte automaticamente para a interface ativa anterior.
- 🎨 **Ponte de Cores Material You:** A paleta de 49 cores gerada pelo `matugen` a partir do seu wallpaper no end-4 é automaticamente traduzida e sincronizada para o `scheme.json` do Caelestia.
- 🎬 **Suporte a Wallpapers em Vídeo e GIF:** Integração automática com `mpvpaper` acelerado por hardware para arquivos `.mp4`, `.webm` e `.gif`.
- 🔒 **Dispatcher Inteligente de Bloqueio (`rice-lock`):** Gerencia a tela de bloqueio respeitando preferências locais (`hyprlock` nativo ou lockers integrados do Quickshell).
- ⌨️ **Layout de Teclado `us` / `br`:** Alternância rápida entre teclados com atalhos de brilho e áudio unificados.
- 📦 **Perfis Declarativos de Instalação:** Instale exatamente o que precisa através dos perfis `minimal`, `hybrid` ou `complete`.

---

## Requisitos do Sistema

- **Arquitetura:** `x86_64`.
- **GPU:** Suporte a OpenGL / Vulkan (Intel, AMD ou NVIDIA com modesetting habilitado).
- **Memória RAM:** Mínimo de 4 GiB (recomendado 8 GiB ou mais para compilação rápida do QuickShell).
- **Armazenamento Livre:** Mínimo de 15 GiB de espaço livre no disco raiz (`/`).
- **Acesso à Internet:** Necessário durante a instalação para download e compilação de pacotes.

---

## Distribuições Suportadas

- **Arch Linux:** **Oficialmente suportado e homologado.** O instalador resolve automaticamente metapacotes PKGBUILD, dependências oficiais e pacotes do AUR via `yay-bin`.
- **Outras Distribuições:** No momento, implementações para Fedora, NixOS ou Gentoo presentes no upstream do illogical-impulse não foram homologadas para o rice híbrido e encontram-se desativadas nesta versão beta.

---

## Perfis de Instalação

| Perfil | Descrição | Espaço em Disco |
| :--- | :--- | :--- |
| **`minimal`** | Hyprland + end-4 core essencial. Ideal para hardware modesto ou usuários focados em desempenho absoluto. | ~3.8 GiB |
| **`hybrid`** *(Padrão)* | end-4 + Caelestia Hybrid + Plugin C++ nativo + pontes de cores e wallpapers animados. | ~7.5 GiB |
| **`complete`** | Híbrido completo + suite expandida de ferramentas de terminal e mídia (`fish`, `kitty`, `foot`, `starship`, `easyeffects`). | ~7.6 GiB |

---

## Procedimento de Instalação

### 1. Clonar o Repositório
```bash
git clone --recursive https://github.com/SEU_USUARIO/dots-hyprland.git ~/dots-hyprland
cd ~/dots-hyprland
```

### 2. Simulação Não-Destrutiva (Recomendado)
Antes de efetuar alterações, você pode testar a instalação sem modificar arquivos:
```bash
./setup install --profile hybrid --dry-run
```

### 3. Instalar o Rice
Para instalar com o perfil híbrido padrão:
```bash
./setup install --profile hybrid
```

Para instalação automatizada/não-interativa:
```bash
./setup install --profile hybrid -f --log-file ~/install-hybrid.log
```

Para o perfil completo com todos os terminais e ferramentas extras:
```bash
./setup install --profile complete -f
```

---

## Dependências do AUR e Considerações de Segurança

O perfil híbrido compila e instala automaticamente os seguintes componentes do Arch User Repository (AUR):
- `qt6-m3shapes-git`: Primitivas vetoriais de animação do Caelestia.
- `libcava`: Biblioteca de visualização de espectro de áudio.
- `ttf-material-symbols-variable-git`, `ttf-rubik-vf`: Tipografia da interface.
- `breeze-plus`, `darkly-bin`: Estilos de janelas e temas Qt.

> [!WARNING]
> O instalador utiliza `yay-bin` de maneira não-interativa (`--sudoloop --needed --noconfirm`) para compilar dependências com as flags oficiais do sistema. Como em qualquer uso do AUR, certifique-se de que confia nas fontes e nos PKGBUILDs baixados.

---

## Operação do Ambiente Híbrido

### Alternando entre Interfaces
1. **Via Barra Gráfica:** Clique no ícone de alternância localizado na barra superior do desktop.
2. **Via Terminal / Atalho:**
   ```bash
   # Ativar Caelestia Shell
   ui-switch.sh caelestia

   # Ativar end-4 (illogical-impulse)
   ui-switch.sh end4
   ```

### Bloqueio de Tela
Acione a tela de bloqueio com `SUPER + L` ou via terminal:
```bash
rice-lock
```
O dispatcher detecta qual interface está em execução e aciona a rotina correta.

### Atualizando as Configurações
Para atualizar o rice preservando customizações locais:
```bash
cd ~/dots-hyprland
git pull
./setup install-files
```

---

## Backups e Recuperação Manual

### Backups Automáticos
Antes de sobrescrever arquivos conflitantes durante a instalação, o instalador cria automaticamente uma cópia de segurança em:
```
~/.config/hyprland-rice-backup-AAAA-MM-DD-HHMMSS/
```

### Recuperação Manual
Caso uma transição trave ou uma configuração impeça o carregamento da interface gráfica:
1. Abra um terminal virtual via `Ctrl + Alt + F3` ou conecte via SSH.
2. Force a restauração para o frontend end-4 base:
   ```bash
   killall -9 quickshell qs mpvpaper 2>/dev/null
   echo "end4" > ~/.local/state/quickshell/ui-switch/current
   qs -c ii &
   ```
3. Se necessário, restaure suas configurações anteriores copiando os arquivos de volta do diretório de backup correspondente.

---

## Limitações Conhecidas

> [!IMPORTANT]
> - **Escopo do Rollback:** O mecanismo de rollback automático embutido em `ui-switch.sh` aplica-se **estritamente à alternância em tempo real da interface visual (frontends)**. Ele **não constitui um rollback transacional do sistema operacional nem do gerenciador de pacotes pacman**.
> - **Ambientes Virtualizados (VMs):** O daemon `ydotool` requer acesso a `/dev/uinput`. Em algumas VMs, pode ser necessário carregar o módulo manualmente: `sudo modprobe uinput`.
> - **Placas NVIDIA:** Recomenda-se adicionar o parâmetro de kernel `nvidia-drm.modeset=1` e desabilitar cursores de hardware (`export WLR_NO_HARDWARE_CURSORS=1`) no Hyprland caso observe travamentos visuais.
> - **Recursos Pessoais:** Arquivos pessoais (como wallpapers locais em `~/Pictures`, chaves SSH ou tokens de API) **não são distribuídos** no repositório por razões de privacidade e licença.

---

## Atribuições e Licenciamento

Este projeto respeita e preserva integralmente os direitos dos autores originais:

- **Base do Sistema e Frontend `ii` / `waffle`:**  
  Desenvolvido por **[end-4](https://github.com/end-4)** sob a licença **GNU GPLv3**.  
  Consulte [`LICENSE`](./LICENSE) para o texto completo da licença.
- **Frontend Caelestia Hybrid e Plugin C++:**  
  Desenvolvido pela equipe **[Caelestia Dots](https://github.com/caelestia-dots/shell)** sob a licença **GNU GPLv3**.  
  Código do plugin compilado e integrado a partir da revisão upstream fixada `454f46da`.
- **Camada de Integração Híbrida (`ui-switch.sh`, `rice-lock`, bridges de cores e vídeo):**  
  Licenciada sob a licença **GNU GPLv3**.
- **Tipografia e Fontes:**
  - *Google Sans Flex*: Open Font License (OFL).
  - *JetBrains Mono Nerd Font*: SIL OFL / Apache-2.0.
  - *Material Symbols Variable*: Apache-2.0.
  - *Readex Pro / Rubik VF*: SIL OFL.
- **Ícones e Temas:**
  - *Fluent System Icons*: Microsoft (Licença MIT).
  - *Adwaita GTK Theme*: GNU LGPL-2.1.
  - *Bibata Modern Classic*: GNU GPLv3.
