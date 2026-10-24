# Caelestia Hybrid — Manifesto de Proveniência e Customizações

Este diretório (`dots/.config/quickshell/caelestia-hybrid`) contém o frontend Quickshell **Caelestia Hybrid**, adaptado para operar em conjunto com o **illogical-impulse (`end-4`)** sob o mesmo ambiente Hyprland.

## 1. Atribuição Upstream e Licença

* **Projeto Original:** [caelestia-dots/shell](https://github.com/caelestia-dots/shell)
* **Revisão Fixada (`UPSTREAM_REVISION`):** `454f46da16ae75cc57f34adf48dea74db0fa5175` (`v2.5.0-6-g454f46da`)
* **Licença:** GNU General Public License v3.0 (`GPL-3.0-only`, preservada em `./LICENSE`)

> **Nota sobre não duplicação:** Os diretórios de código C++ (`plugin/`, `extras/`), empacotamento Nix (`nix/`, `flake.*`) e ferramentas de lint do repositório `caelestia-dots/shell` **não** são duplicados aqui. O plugin C++/QML nativo (`Caelestia.*`) é compilado sob demanda a partir do commit fixado via `sdata/dist-arch/illogical-impulse-caelestia-plugin/PKGBUILD`.

---

## 2. Arquivos Próprios (Desenvolvidos Localmente)

| Arquivo | Finalidade |
| :--- | :--- |
| `UPSTREAM_REVISION` | Hash SHA-1 do commit base do `caelestia-dots/shell`. |
| `HYBRID_MANIFEST.md` | Este manifesto de rastreabilidade. |
| `scripts/end4-theme-bridge.sh` | Sincroniza o wallpaper e converte a paleta Material You do `end-4` (`colors.json` em `snake_case`) para o formato `camelCase` esperado pelo Caelestia (`scheme.json`). |
| `scripts/video-wallpaper-sync.sh` | Monitora wallpapers em vídeo/GIF definidos no `end-4`, desativa o fundo estático do Caelestia (`wallpaperEnabled: false`) e controla o `mpvpaper`. |
| `scripts/nightlight.sh` | Controle e leitura de estado de temperatura de cor via `hyprctl hyprsunset`. |
| `scripts/caelestia-runtime-binds.sh` | Helper de atualização de estado do frontend (`ui-switch/current`) e reload do Hyprland. |
| `modules/VideoWallpaperBridge.qml` | Gerencia o processo `video-wallpaper-sync.sh watch` acoplado ao ciclo de vida do `caelestia-hybrid`. |
| `modules/bar/components/UiFrontendSwitchButton.qml` | Botão na barra vertical do Caelestia para alternar de volta ao `end-4` via `ui-switch.sh end4`. |
| `modules/bar/popouts/StatusCenter.qml` | Popout unificado **Quick controls** na barra (layout de teclado US/BR, Microfone, Night Light, Game Mode, DND, Keep Awake, Settings e gravador de tela nativo). |

---

## 3. Arquivos do Upstream Modificados Localmente

| Arquivo | Alteração Aplicada |
| :--- | :--- |
| `shell.qml` | Instancia `VideoWallpaperBridge {}` e remove `IdleMonitors` (o bloqueio por inatividade é centralizado via `hypridle` + `rice-lock`). |
| `modules/bar/Bar.qml` | Adiciona `UiFrontendSwitchButton` na barra principal. |
| `modules/bar/components/Clock.qml` | Altera ícone para `schedule`. |
| `modules/bar/components/StatusIcons.qml` | Substitui o indicador textual de `kbLayout` pelo gatilho do popout `statuscenter` (ícone `tune`). |
| `modules/bar/popouts/ClipWrapper.qml` | Propaga a propriedade `screenState` para o `StatusCenter`. |
| `modules/bar/popouts/Content.qml` | Registra o `Popout` `statuscenter` instanciando `StatusCenter`. |
| `modules/bar/popouts/Wrapper.qml` | Propaga `screenState` para `Content`. |
| `modules/drawers/Panels.qml` | Passa `root.screenState` ao `popoutsWrapper`. |
| `modules/session/Content.qml` | Ajusta reprodução contínua (`playing: true`, `cache: false`) do GIF da tela de sessão. |
| `modules/Shortcuts.qml` | Desativa abertura do drawer lateral `utilities` (incorporado ao `StatusCenter`). |
| `modules/utilities/Wrapper.qml` | Fixa `shouldBeActive: false` para manter o drawer lateral desativado no modo híbrido. |
| `modules/utilities/cards/Toggles.qml` | Adiciona toggle `nightLight` integrado ao `hyprsunset` e `XDG_STATE_HOME/caelestia/nightlight`. |
| `services/Colours.qml` | Redireciona `setMode()` para `scripts/end4-theme-bridge.sh --mode <mode> --noswitch`. |
| `services/Wallpapers.qml` | Redireciona `setWallpaper()` e `setRandom()` para `scripts/end4-theme-bridge.sh`, removendo dependência da CLI `caelestia`. |
| `assets/kurukuru.gif` | Asset animado personalizado para a tela de sessão. |
