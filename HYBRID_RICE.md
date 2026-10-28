# Redshift OS — Hyprland Hybrid Rice (`end-4 / illogical-impulse` + `Caelestia`)

Este repositório oficial do **Redshift OS** (<https://github.com/Altaeir-13/RedshiftOS-dotfiles>) integra a identidade visual e ergonomia do sistema com o ecossistema [end-4/dots-hyprland (`illogical-impulse`)](https://github.com/end-4/dots-hyprland) e o frontend escultural [Caelestia Shell](https://github.com/caelestia-dots/shell), permitindo alternância em tempo real entre os dois ambientes sem perda de estado, conflito de atalhos ou dessincronização de temas/wallpapers.

---

## 1. Atribuição e Licenças

* **Identidade Visual e Configurações Redshift OS:**
  - Repositório Oficial: [Altaeir-13/RedshiftOS-dotfiles](https://github.com/Altaeir-13/RedshiftOS-dotfiles)
  - Licença: `GPL-3.0`
* **Base do Repositório e Frontend `ii` / `waffle`:**
  - Projeto: [end-4/dots-hyprland](https://github.com/end-4/dots-hyprland)
  - Licença: `GPL-3.0` (ver [`LICENSE`](./LICENSE) e [`licenses/`](./licenses))
* **Frontend `caelestia-hybrid` e Plugin Nativo `Caelestia.*`:**
  - Projeto: [caelestia-dots/shell](https://github.com/caelestia-dots/shell)
  - Revisão Upstream Fixada: `454f46da16ae75cc57f34adf48dea74db0fa5175` (`v2.5.0-6-g454f46da`)
  - Licença: `GPL-3.0-only` (ver [`dots/.config/quickshell/caelestia-hybrid/LICENSE`](./dots/.config/quickshell/caelestia-hybrid/LICENSE))
* **Camada de Integração Híbrida (`ui-switch.sh`, `rice-lock`, bridges, `StatusCenter`, binds dinâmicos, `gamemode`):**
  - Desenvolvida especificamente para o Redshift OS e distribuída sob `GPL-3.0`.

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

## 3. Identidade Visual Redshift OS e Animações GPU

1. **Símbolo Vetorial Unificado:**
   - Centralizado em `~/.local/share/redshift-os/icons/`: dispõe de variantes vetoriais (`redshift-symbolic-compact.svg`, `redshift-symbolic.svg`) e renderizações em bitmap de 16px a 512px.
   - Proporção geométrica padronizada e presença visual equivalente aos botões originais das barras.
2. **Rotação GPU Nativa e Contínua:**
   - Implementada através de `RotationAnimation` com `loops: Animation.Infinite` em 8 segundos por ciclo.
   - Sem loop de processos externos, sem consumo ocioso e com pausa automática quando os componentes deixam de estar visíveis.
3. **Tingimento Dinâmico de Cores:**
   - No Caelestia: tingido com `Colours.palette.m3primary` via shader `Colouriser`.
   - No end-4: tingido com `colPrimary` via `ColorOverlay`.
   - Responde instantaneamente à alteração de wallpaper e de variante de cor Material You.
4. **Fastfetch Personalizado:**
   - Configuração pronta em `~/.config/fastfetch/config.jsonc` com arte ASCII da estrela flamejante em `redshift_logo.txt`.

---

## 4. Seletor de Variantes Material You e Game Mode

1. **Seletor de Variantes no Caelestia Nexus (`PaletteVariantSelector.qml`):**
   - Integrado à página `Settings > Wallpaper & style`.
   - Suporta seleção entre: Auto, Content, Expressive, Fidelity, Fruit Salad, Monochrome, Neutral, Rainbow, Tonal Spot e Vibrant.
   - Grava a preferência do usuário e aplica imediatamente no backend `matugen` sincronizando com o end-4.
2. **Game Mode (`gamemode.py` + `gamemode.sh` + `GameMode.qml`):**
   - Toggle disponível no menu de utilidades do Caelestia e via CLI.
   - Desativa animações, cantos arredondados, gaps e bordas de janelas para garantir a menor latência em jogos.
   - Salva o estado anterior atomicamente e restaura com fidelidade absoluta ao desativar.

---

## 5. Perfis do Instalador (`./setup`)

O script `./setup` suporta três perfis declarativos (definidos em [`sdata/profiles/`](./sdata/profiles)):

```bash
# Simulação não destrutiva (Dry-Run)
./setup install --profile hybrid --dry-run

# Instalação por perfil
./setup install --profile minimal   # Apenas Hyprland + end-4 (ii)
./setup install --profile hybrid    # Hyprland + end-4 + Caelestia Hybrid (padrão)
./setup install --profile complete  # Hybrid + apps opcionais (easyeffects, fish, foot, kitty, starship, plasma-browser-integration)
```
