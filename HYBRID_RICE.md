# Hyprland Hybrid Rice (`end-4 / illogical-impulse` + `Caelestia`)

Este repositório estende o [end-4/dots-hyprland (`illogical-impulse`)](https://github.com/end-4/dots-hyprland) com suporte nativo ao frontend [Caelestia Shell](https://github.com/caelestia-dots/shell), permitindo alternância em tempo real entre os dois ambientes sem perda de estado, conflito de atalhos ou dessincronização de temas/wallpapers.

---

## 1. Atribuição e Licenças

* **Base do Repositório e Frontend `ii` / `waffle`:**
  - Projeto: [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland)
  - Licença: `GPL-3.0` (ver [`LICENSE`](./LICENSE) e [`licenses/`](./licenses))
* **Frontend `caelestia-hybrid` e Plugin Nativo `Caelestia.*`:**
  - Projeto: [caelestia-dots/shell](https://github.com/caelestia-dots/shell)
  - Revisão Upstream Fixada: `454f46da16ae75cc57f34adf48dea74db0fa5175` (`v2.5.0-6-g454f46da`)
  - Licença: `GPL-3.0-only` (ver [`dots/.config/quickshell/caelestia-hybrid/LICENSE`](./dots/.config/quickshell/caelestia-hybrid/LICENSE))
* **Camada de Integração Híbrida (`ui-switch.sh`, `rice-lock`, bridges, `StatusCenter`, binds dinâmicos):**
  - Desenvolvida especificamente para este rice híbrido e distribuída sob `GPL-3.0`.

---

## 2. Arquitetura da Integração Híbrida

1. **Alternância Transacional (`dots/.config/quickshell/ui-switch.sh`):**
   - Alterna entre `qs -c ii` (`end-4`) e `qs -c caelestia-hybrid` (`Caelestia`).
   - Antes de iniciar o Caelestia, valida a presença do plugin nativo QML (`Caelestia.*`) e sincroniza a paleta Material You e o wallpaper via `end4-theme-bridge.sh`.
   - Caso o Caelestia falhe ao iniciar ou encerre prematuramente, executa **rollback automático** para o `end-4` e restaura os atalhos do Hyprland.
2. **Atalhos Dinâmicos e Brilho (`dots/.config/hypr/hyprland.lua`):**
   - A função `hybrid_frontend()` verifica tanto o arquivo de estado (`$XDG_STATE_HOME/quickshell/ui-switch/current`) quanto a instância real em execução no Quickshell (`qs list --all`).
   - Quando o Caelestia está ativo, `SUPER` aciona o launcher do Caelestia via IPC e `XF86MonBrightnessUp/Down` (`F5`/`F6`) acionam o serviço `brightness` do Caelestia (exibindo o OSD nativo).
   - `SUPER + Space` alterna o layout de teclado (`us,br`) via XKB sem disparar o launcher ao soltar `SUPER`.
3. **Bloqueio de Tela Unificado (`dots/.local/bin/rice-lock`):**
   - Acionado por `SUPER + L` e pelo `hypridle.conf`.
   - Respeita `.lock.useHyprlock` de `$XDG_CONFIG_HOME/illogical-impulse/config.json`; caso contrário, delega via IPC ao lockscreen do frontend ativo (`caelestia-hybrid` ou `ii`), com fallback seguro para `hyprlock`.
4. **Wallpapers Estáticos e em Vídeo (`end4-theme-bridge.sh` + `video-wallpaper-sync.sh` + `QuickConfig.qml`):**
   - `QuickConfig.qml` no `end-4` exibe pré-visualização em vídeo (`QtMultimedia`) para arquivos `.mp4`, `.webm`, `.mkv`, `.avi`, `.mov` e `.m4v`.
   - No Caelestia, `VideoWallpaperBridge.qml` mantém `video-wallpaper-sync.sh` ativo para gerenciar `mpvpaper` e alternar automaticamente `background.wallpaperEnabled` em `$XDG_CONFIG_HOME/caelestia/shell.json`.

---

## 3. Perfis do Instalador (`./setup`)

O script `./setup` suporta três perfis declarativos (definidos em [`sdata/profiles/`](./sdata/profiles)):

```bash
# Simulação não destrutiva (Dry-Run)
./setup install --profile hybrid --dry-run

# Instalação por perfil
./setup install --profile minimal   # Apenas Hyprland + end-4 (ii)
./setup install --profile hybrid    # Hyprland + end-4 + Caelestia Hybrid (padrão)
./setup install --profile complete  # Hybrid + apps opcionais (easyeffects, fish, foot, kitty, starship, plasma-browser-integration)
```
