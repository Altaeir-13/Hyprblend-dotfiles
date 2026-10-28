# Redshift Store — Documentação Oficial

> **Central de Aplicativos nativa em Qt6/QML e PyQt6 para o Redshift OS, inspirada na ergonomia da Microsoft Store e profundamente integrada ao ecossistema Arch Linux (repositórios oficiais e AUR) com sincronização em tempo real das cores dinâmicas Material You.**

---

## 1. Visão Geral

A **Redshift Store** é a central gráfica oficial de gerenciamento de software do **Redshift OS**. Desenvolvida com **PyQt6** no backend e uma interface moderna e declarativa em **Qt6/QML**, a aplicação foi concebida para oferecer a melhor experiência possível de descoberta, instalação, atualização e remoção de aplicativos no Arch Linux.

### Principais Destaques:
- **Design Moderno e Expressivo:** Inspirada no layout limpo e intuitivo da Microsoft Store, com barra de navegação lateral (Navigation Rail), banners de destaque curados, chips de categorias e cartões visuais com elevação e microinterações fluidas.
- **Sincronização Dinâmica Material You:** Cores extraídas automaticamente do papel de parede do usuário via **Matugen**, compatível simultaneamente com os temas dos frontends **end-4 (illogical-impulse)** e **Caelestia Shell**.
- **Ecossistema Completo Arch Linux:** Pesquisa instantânea em repositórios oficiais (`core`, `extra`, `multilib`) via `pacman`, catálogo enriquecido via metadados **AppStream** e `.desktop`, e suporte completo ao **Arch User Repository (AUR)** via API RPC v5 e `yay`.
- **Segurança de Nível de Sistema Operacional:** Proteção rígida contra remoção de pacotes vitais (kernel, glibc, systemd, hyprland, quickshell), sanitização de nomes para prevenir injeção de comandos, bloqueio estrito de execução do AUR como root (`EUID != 0`), e elevação de privilégios via agente gráfico **Polkit** (`pkexec`).
- **Idempotência e Integração ao Instalador:** Fornecida como metapacote nativo (`illogical-impulse-redshift-store`) e integrada automaticamente aos perfis `minimal`, `hybrid` e `complete` do `./setup`.

---

## 2. Arquitetura e Estrutura de Módulos

A aplicação reside no repositório sob o caminho gerenciado `dots/.local/share/redshift-os/redshift-store/`, acompanhada de seu launcher no PATH (`dots/.local/bin/redshift-store`) e lançador de aplicativo XDG (`dots/.local/share/applications/redshift-store.desktop`).

```
dots/.local/share/redshift-os/redshift-store/
├── main.py                     # Ponto de entrada, configuração Qt6, flags CLI e autoteste
├── backend/                    # Camada de lógica, serviços assíncronos e modelos
│   ├── __init__.py             # Exportação unificada dos componentes do backend
│   ├── models.py               # Dataclass PackageItem e PackageListModel (24 roles QML)
│   ├── security.py             # Guardrails, validação regex, builders seguros e lock do pacman
│   ├── theme_service.py        # ThemeService (inotify QFileSystemWatcher, 49 tokens M3)
│   ├── catalog_service.py      # CatalogService (indexação /var/lib/pacman/local, AUR RPC, AppStream)
│   ├── transaction_service.py  # TransactionService (QProcess assíncrono, streaming de logs)
│   └── store_controller.py     # StoreController (fachada StoreBridge registrada no QML)
└── qml/                        # Camada de apresentação declarativa QtQuick/QML
    ├── Main.qml                # Janela principal, roteamento de páginas e modais
    ├── theme/
    │   └── Theme.qml           # Mapeamento reativo dos 49 tokens Material 3 e fontes
    ├── components/
    │   ├── NavigationSidebar.qml   # Barra lateral com indicador de estado e toggle claro/escuro
    │   ├── TopSearchBar.qml        # Barra de pesquisa com debounce e filtros de origem
    │   ├── HeroBanner.qml          # Banner rotativo de aplicativos em destaque
    │   ├── CategoryChipBar.qml     # Seletor horizontal de categorias canônicas
    │   ├── PackageCard.qml         # Cartão de pacote com badge de origem, ícone e botão de ação
    │   ├── PackageDetailDialog.qml # Modal expansivo com descrição completa, dependências e PKGBUILD
    │   └── OperationsLogDrawer.qml # Gaveta recolhível de logs do terminal em tempo real
    └── pages/
        ├── HomePage.qml        # Página inicial com destaques e aplicativos essenciais
        ├── CatalogPage.qml     # Página de catálogo com grade responsiva e filtros combinados
        ├── InstalledPage.qml   # Biblioteca de pacotes instalados com filtro explícito/dependência
        └── UpdatesPage.qml     # Central de atualizações pendentes com ação de "Atualizar Tudo"
```

### 2.1 Módulos do Backend (`backend/`)

- **`models.py`:**
  - `PackageItem`: Dataclass contendo 23 atributos tipados (identificação, versões, repositório, categoria, ícone, tamanho, licença, dependências, votos e proteção). O método `to_dict()` gera mapeamento com chaves canônicas em `snake_case` e aliases `camelCase` para acesso direto no QML.
  - `PackageListModel`: Subclasse de `QAbstractListModel` com **24 roles de dados**. Implementa atualização em bloco via `set_items()`, consultas rápidas `get_by_name()` / `get_dict_by_name()`, e notificação reativa de contagem (`countChanged`).
- **`security.py`:**
  - `validate_package_name(name)` & `ensure_valid_package_name(name)`: Validação contra a regex estrita `^[a-zA-Z0-9][a-zA-Z0-9@._+-]{0,127}$`, rejeitando flags (`-Syu`), injeções de shell e caminhos relativos.
  - `is_protected_package(name)` & `ensure_not_protected(name)`: Bloqueio estrito de remoção para pacotes vitais definidos em `PROTECTED_PACKAGES`.
  - `ensure_non_root_for_aur()`: Garante que comandos do AUR jamais sejam disparados sob root (`EUID 0`).
  - `is_pacman_locked()`: Detecta a presença de `/var/lib/pacman/db.lck` (suporta override de teste via `REDSHIFT_PACMAN_LOCK_PATH`).
  - Builders de comandos: Construtores seguros que forçam separador de argumentos `--` e delegam elevação de privilégios ao Polkit (`/usr/bin/pkexec`).
- **`theme_service.py` (`ThemeService`):**
  - Monitora arquivos de tema gerados pelo sistema em tempo real com `QFileSystemWatcher`.
  - Normaliza paletas de cores gerando todos os 49 tokens do Material 3 Expressive, além de tokens de status funcionais (`success`, `warning`).
  - Permite alternância temporária de pré-visualização (Claro / Escuro) via `togglePreviewMode()` com restauração no segundo clique.
- **`catalog_service.py` (`CatalogService`):**
  - Parser ultrarrápido em C/Python de `/var/lib/pacman/local/` lendo arquivos `desc` diretamente em ~50ms.
  - Busca remota no AUR via RPC v5 com cache em memória (TTL de 120 segundos).
  - Enriquecimento com metadados do AppStream e arquivos `.desktop` locais.
  - Suporte a modo mock offline (`CatalogService(mock_mode=True)`).
- **`transaction_service.py` (`TransactionService`):**
  - Execução assíncrona não bloqueante de `pacman` e `yay` via `QProcess`.
  - Streaming em tempo real linha a linha para a interface e detecção de progresso percentual via regex.
  - Simulação determinística multi-passo em modo mock.
- **`store_controller.py` (`StoreController`):**
  - Fachada unificada registrada no contexto QML como `StoreBridge`.
  - Expõe os 4 modelos reativos: `catalogModel`, `featuredModel`, `installedModel` e `updatesModel`.
  - Expõe propriedades de estado (`operationState`, `isBusy`, `isDbLocked`, `installedCount`, `updatesCount`, `logText`).
  - Expõe slots para pesquisa, filtros, seleção de pacotes, instalação, remoção, atualização e inspeção de PKGBUILDs.

---

## 3. Sincronização Dinâmica Material You

A Redshift Store integra-se perfeitamente à experiência visual adaptativa do Redshift OS:

1. **Monitoramento Reativo de Arquivos:**
   O `ThemeService` monitora os seguintes caminhos por meio do `QFileSystemWatcher`:
   - `~/.local/state/quickshell/user/generated/colors.json` (paleta gerada pelo Matugen a partir do wallpaper no end-4).
   - `~/.local/state/caelestia/scheme.json` (esquema de cores ativo no Caelestia Shell).
   - `~/.local/state/quickshell/ui-switch/current` (modo do frontend ativo: `end4` ou `caelestia`).
2. **Tratamento de Escritas Atômicas e Inodes:**
   Como editores e ferramentas de script comumente recriam arquivos substituindo inodes (escrita atômica), o serviço monitora o diretório pai e executa re-attach automático de watchers quando novos inodes são detectados.
3. **Normalização de 49 Tokens M3:**
   Independentemente da fonte (snake_case do Matugen ou camelCase do Caelestia), todos os tokens são convertidos e expostos com fallback garantido:
   `primary`, `primaryContainer`, `onPrimary`, `surface`, `surfaceContainer`, `outline`, `error`, `success`, `warning`, etc.
4. **Modo de Pré-visualização Instantânea:**
   No canto inferior da barra de navegação lateral, um botão de alternância de tema permite testar a interface entre modo escuro e claro sem alterar as configurações globais do sistema.

---

## 4. Segurança e Guardrails

A Redshift Store opera como interface gráfica sobre ferramentas de gerenciamento de pacotes que afetam todo o sistema. Por essa razão, implementa políticas de segurança defensivas rigorosas:

| Vetor de Risco | Mitigação Implementada |
| :--- | :--- |
| **Injeção de Parâmetros e Flags** | Nomes de pacotes são validados contra `^[a-zA-Z0-9][a-zA-Z0-9@._+-]{0,127}$`. Qualquer string iniciando com hífen (`-Syu`, `--noconfirm`) é terminantemente recusada. Os comandos finais utilizam o delimitador `--` antes da lista de pacotes. |
| **Injeção de Shell / Metacaracteres** | Comandos são executados estritamente via lista de argumentos (`QProcess` com `argv`), dispensando `sh -c` ou interpretação de shell para operações privilegiadas. |
| **Quebra de Sistema por Remoção Acidental** | Pacotes essenciais (`pacman`, `linux`, `glibc`, `systemd`, `hyprland`, `quickshell`, `python-pyqt6`, etc.) constam em `PROTECTED_PACKAGES`. Qualquer solicitação de remoção desses pacotes é bloqueada no backend antes de iniciar qualquer processo. |
| **Execução de AUR sob Root** | O AUR permite execução de scripts arbitrários de compilação (`PKGBUILD`). O método `ensure_non_root_for_aur()` impede que o `yay` seja executado se o `EUID == 0`. A elevação final para instalação do binário é delegada ao Polkit via `--sudo /usr/bin/pkexec`. |
| **Conflitos de Concorrência do Pacman** | O estado do lock (`/var/lib/pacman/db.lck`) é verificado antes de iniciar qualquer transação, notificando o usuário com mensagem informativa caso outra ferramenta (ex.: terminal) esteja operando a base de dados. |
| **Auditoria Visual e Interativa de PKGBUILDs (AUR)** | Ao inspecionar pacotes do AUR, a Redshift Store busca e exibe o código do `PKGBUILD` na aba "Auditoria PKGBUILD" da janela de detalhes. Além disso, durante a instalação/atualização via `yay`, os menus interativos `--cleanmenu` e `--diffmenu` são preservados (com `GIT_PAGER=cat` e `PAGER=cat`), permitindo revisar o diff completo no `OperationsLogDrawer` e responder via botões rápidos (`Nenhum (N)`, `Mostrar Todos / Diff (A)`, `Abortar (Ab)`) ou caixa de entrada manual. |
| **Cancelamento Seguro por Estágio (Sem SIGKILL)** | O cancelamento usa exclusivamente `SIGTERM` nos estágios seguros (`checking_updates`, `authenticating`, `downloading`, `compiling`) e é bloqueado durante modificações críticas do banco (`committing` ou quando `/var/lib/pacman/db.lck` existe). |

---

## 5. Como Usar

### 5.1 Linha de Comando e Launcher
O launcher executável está disponível no PATH do usuário:
```bash
redshift-store [OPÇÕES]
```

### Opções Disponíveis:
- `--page <home|catalog|installed|updates>`: Abre diretamente na página especificada.
  ```bash
  redshift-store --page updates    # Abre diretamente na central de atualizações
  redshift-store --page installed  # Abre na biblioteca de aplicativos instalados
  ```
- `--mock`: Inicia a aplicação em modo de simulação (dados mockados, sem efetuar alterações reais de pacotes no sistema).
- `--self-test`: Executa validação headless de inicialização, verificação de modelos e parsing do QML, encerrando com código `0` em caso de sucesso.
- `--version`: Exibe a versão instalada da Redshift Store.

### 5.2 Lançador de Aplicativos (Menu / Rofi / Fuzzel)
A aplicação instala o arquivo `.desktop` padrão em `~/.local/share/applications/redshift-store.desktop`:
- **Nome:** Redshift Store (Central de Aplicativos)
- **Categorias:** `System;PackageManager;Settings;`
- **Ações Rápidas (Desktop Actions):**
  - *Verificar Atualizações*: dispara `redshift-store --page updates`.
  - *Pacotes Instalados*: dispara `redshift-store --page installed`.

---

## 6. Integração com o Instalador `./setup` e Perfis

A Redshift Store faz parte do núcleo de experiência do Redshift OS e é integrada de forma declarativa:

- **Metapacote Arch:** Definido em `sdata/dist-arch/illogical-impulse-redshift-store/PKGBUILD`, reunindo as dependências de sistema (`python`, `python-pyqt6`, `qt6-base`, `qt6-declarative`, `qt6-svg`, `qt6-5compat`, `pacman-contrib`, `appstream`, `archlinux-appstream-data`, `python-gobject`, `polkit`).
- **Presença nos Perfis Declarativos (`sdata/profiles/`):**
  - **`minimal`**: Inclui a Redshift Store para garantir gerenciamento visual leve no desktop essencial.
  - **`hybrid`** *(Padrão)*: Inclui a Redshift Store com integração total aos dois frontends (`end-4` e `Caelestia`).
  - **`complete`**: Inclui a Redshift Store acompanhada de todas as ferramentas adicionais de terminal e multimídia.
- **Rastreabilidade e Desinstalação Limpa:**
  - Os arquivos copiados são registrados em `$XDG_CONFIG_HOME/illogical-impulse/installed_listfile`.
  - O script `sdata/dist-arch/uninstall-deps.sh` inclui `illogical-impulse-redshift-store` na rotina de remoção via `yay -Rns`.

---

## 7. Testes Automatizados e Qualidade

O projeto conta com suíte de testes automatizados executáveis sem afetar o sistema hospedeiro:

### 7.1 Suíte de Testes Unitários e Integração QML (Python)
Executa **18 baterias completas de testes** cobrindo segurança, modelos, catálogo mock e nativo, sincronização Material You (`colors.json` vs `scheme.json` e proteção WCAG contra baixo contraste), menus interativos do AUR (`--cleanmenu`/`--diffmenu`), tratamento de recusa Polkit (`exit 126/127`), controller e renderização headless de `Main.qml`:
```bash
QT_QPA_PLATFORM=offscreen python3 -m unittest discover -s tests -p "test_redshift_store.py" -v
```

### 7.2 Suíte Global de Regressão do Repositório
A suíte em `tests/run-tests.sh` inclui a **Seção 10** dedicada à Redshift Store (totalizando **180 asserções**):
```bash
bash tests/run-tests.sh
```
A suíte valida sintaxe, permissões, conformidade com os perfis declarativos (`minimal`, `hybrid`, `complete`), coexistência entre `/usr/share` e `~/.local/share` (`REDSHIFT_STORE_SOURCE` e comparação de `mtime`), ciclo de vida completo de instalação e desinstalação em sandbox isolado temporário, garantindo 100% de aprovação.

### 7.3 Diferença entre Verificações Unitárias, Mocks, Renderização Headless, Container Isolado e Validação Operacional

| Nível de Validação | Escopo e Mecanismo | Limitações |
| :--- | :--- | :--- |
| **1. Testes Unitários** | Validam funções puras e invariantes de segurança (`validate_package_name`, `PROTECTED_PACKAGES`, `build_safe_*_cmd`, normalização de tokens M3 e cálculo de luminância/contraste WCAG). | Não instanciam processos externos reais (`pacman`/`yay`) nem janela gráfica. |
| **2. Simulações Mock (`--mock` / `REDSHIFT_STORE_MOCK=1`)** | Simulam determinísticamente o fluxo multi-estágio (`downloading` -> `compiling` -> `committing` -> `success`) via `QTimer` sem tocar no sistema hospedeiro. | Não exercitam pipes reais de `stdout`/`stderr`/`stdin` do `QProcess` nem banco ALPM real. |
| **3. Renderização Headless (`QT_QPA_PLATFORM=offscreen`)** | Carrega a árvore `QQmlApplicationEngine` (`Main.qml`, páginas, diálogos e `XdgIconImageProvider`) em buffer offscreen para CI/CD sem servidor gráfico. | Não valida composição Wayland real no Hyprland nem captura de eventos visuais de janela. |
| **4. Integração Real em Container Arch Isolado (`bwrap` + `makepkg` + `pacman`)** | Compila pacotes `.pkg.tar.zst` reais via `makepkg`, cria repositório local via `repo-add` e executa `TransactionService(mock_mode=False)` com `/usr/bin/pacman` real dentro de namespace isolado (`bubblewrap`), validando instalação (`-S`/`-U`), atualização, remoção (`-R`), prompts `[Y/n]` via `stdin`, `db.lck` e `./setup install-files` nos 3 perfis. | Isola o `RootDir`/`DBPath` para proteger a máquina hospedeira. |
| **5. Validação Operacional Wayland/Hyprland (`QT_QPA_PLATFORM=wayland`)** | Executa a aplicação real na sessão Hyprland (`WAYLAND_DISPLAY=wayland-1`) contra `/var/lib/pacman/local`, `pacman -Si`, `checkupdates`, `yay -Qua`, RPC AUR v5 e `matugen` em tempo real via `QFileSystemWatcher`. | Operações destrutivas no host permanecem protegidas e exigem confirmação explícita do usuário no Polkit/console. |
