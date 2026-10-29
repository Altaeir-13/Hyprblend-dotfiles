# Redshift Store 2.0 — Documentação Oficial

> **Central de Aplicativos nativa em Qt6/QML e PyQt6 para o Redshift OS, inspirada na ergonomia da Microsoft Store e profundamente integrada ao ecossistema Arch Linux (repositórios oficiais e AUR) com indexação de pacotes em larga escala, catálogo inteligente, descoberta comunitária transparente, recomendações locais privadas e sincronização em tempo real das cores dinâmicas Material You.**

---

## 1. Visão Geral da Versão 2.0

A **Redshift Store 2.0 (Smart Catalog & Safe Arch Linux)** expande a central gráfica de gerenciamento de software do **Redshift OS**, transformando-a de um visualizador de aplicativos instalados em uma loja completa de descoberta de software para o Arch Linux.

Desenvolvida com **PyQt6** no backend e uma interface moderna e declarativa em **Qt6/QML**, a aplicação oferece paridade com centrais de software de sistemas operacionais de ponta, mantendo conformidade estrita com a filosofia e arquitetura do Arch Linux.

### Principais Destaques da Versão 2.0:
- **Indexação Real de Repositórios Oficiais (`/var/lib/pacman/sync/*.db`):** Leitura nativa e ultrarrápida das bases de sincronização do pacman (`core`, `extra`, `multilib`), indexando mais de **15.700 pacotes oficiais reais** sem depender de comandos CLI lentos.
- **Cache Persistente Inteligente com Assinaturas:** Cache JSON estruturado em `~/.cache/redshift-store/sync_index_v2.json` carregado em ~50ms, com verificação de integridade e invalidação automática baseada no `mtime` e `size` de cada banco `.db`.
- **Descoberta Comunitária do AUR em Lote (RPC v5):** Busca agregada de metadados de pacotes comunitários com ordenação por popularidade e votos reais do AUR. Nunca utiliza termos enganosos de outras plataformas (como "downloads"), garantindo transparência ao usuário.
- **Transparência de Procedência e Métricas do `pkgstats`:** Badges e etiquetas claras informando se o software provém de repositório oficial (`core`, `extra`, `multilib`) ou da comunidade (`AUR`), acompanhadas de dados estatísticos da comunidade Arch Linux (`pkgstats`).
- **8 Seções Ricas na Página Início:**
  1. *Banner Rotativo de Destaques (Hero Banner)*
  2. *Recomendados para Você (Personalização Transparente)*
  3. *Populares da Comunidade Arch (Dados do pkgstats)*
  4. *Primeiros Passos (Essenciais para o Redshift OS)*
  5. *Ambiente de Desenvolvimento (IDEs, compiladores e ferramentas)*
  6. *Jogos e Emuladores (Jogos nativos e launchers)*
  7. *Design e Criatividade (Ilustração, modelagem 3D e multimídia)*
  8. *Comunicação e Internet (Navegadores, clientes de chat e rede)*
- **Personalização Local e Privacidade Estrita:** Recomendações locais baseadas no histórico de navegação e favoritos armazenadas exclusivamente em `$XDG_STATE_HOME/redshift-store/user_preferences.json`. Zero telemetria externa, justificativa explícita em cada card recomendado ("Relacionado à sua pesquisa...", "Relacionado a aplicativos que você favoritou"), chave de ativação/desativação e limpeza instantânea de histórico com um clique.
- **Filtros Combináveis e Paginação sob Demanda:** Página Explorar com filtros combináveis de categoria canônica, fonte (`Oficial`, `AUR`), estado (`Todos`, `Instalados`, `Não instalados`), ordenação múltipla (`Relevância`, `Popularidade`, `Nome`, `Mais recentes`) e botão "Carregar Mais" com paginação incremental sem travamentos.
- **Atualização Segura do Sistema (Anti-Partial Upgrade):** Ação "Atualizar Tudo" executa `yay -Syu` completo garantindo consistência binária no Arch Linux. Atualizações de pacotes oficiais individuais redirecionam com segurança para a atualização completa com notificação informativa.
- **Pós-Verificação Real de Transações:** Após a execução do gerenciador de pacotes, a loja re-escaneia as atualizações pendentes para computar o resultado real (`complete`, `partial`, `cancelled`, `failed`), alertando o usuário caso pacotes permaneçam pendentes por dependências quebradas ou bloqueios de espelhos.
- **Sincronização Dinâmica Material You:** Cores extraídas automaticamente do papel de parede do usuário via **Matugen**, compatível com os frontends **end-4 (illogical-impulse)** e **Caelestia Shell**, com 49 tokens Material 3 Expressive e guarda de contraste WCAG.
- **Segurança de Nível de Sistema Operacional:** Proteção rígida contra remoção de pacotes vitais (kernel, glibc, systemd, hyprland, quickshell), sanitização de nomes de pacotes, bloqueio estrito de execução do AUR como root (`EUID != 0`), e elevação de privilégios via agente gráfico **Polkit** (`pkexec`).

---

## 2. Estrutura de Módulos e Componentes

A aplicação reside no repositório sob o caminho gerenciado `dots/.local/share/redshift-os/redshift-store/`, com launcher no PATH (`dots/.local/bin/redshift-store`) e lançador de aplicativo XDG (`dots/.local/share/applications/redshift-store.desktop`).

```
dots/.local/share/redshift-os/redshift-store/
├── main.py                     # Ponto de entrada, configuração Qt6, flags CLI e autoteste
├── backend/                    # Camada de serviços assíncronos, modelos e segurança
│   ├── __init__.py             # Exportações públicas da camada backend
│   ├── models.py               # PackageItem e PackageListModel (34 roles QML)
│   ├── security.py             # Sanitização de entrada, guardrails, comandos seguros e lock
│   ├── theme_service.py        # ThemeService (inotify QFileSystemWatcher, 49 tokens M3)
│   ├── catalog_service.py      # CatalogService (indexação sync *.db, AppStream, AUR RPC v5, pkgstats)
│   ├── transaction_service.py  # TransactionService (QProcess assíncrono, menus interativos AUR)
│   └── store_controller.py     # StoreController (fachada StoreBridge registrada no QML)
└── qml/                        # Camada de apresentação declarativa QtQuick/QML
    ├── Main.qml                # Janela principal, roteamento de páginas, toasts e modais
    ├── theme/
    │   └── Theme.qml           # Mapeamento reativo dos 49 tokens Material 3 e tipografia
    ├── components/
    │   ├── NavigationSidebar.qml   # Barra lateral de navegação estilo Navigation Rail
    │   ├── TopSearchBar.qml        # Barra de pesquisa global com debounce e filtros de origem
    │   ├── HeroBanner.qml          # Banner rotativo de aplicativos em destaque
    │   ├── CategoryChipBar.qml     # Seletor horizontal de categorias canônicas
    │   ├── PackageCard.qml         # Cartão de pacote com elevação M3, badges e botão de ação
    │   ├── PackageDetailDialog.qml # Modal expansivo de detalhes, licença, tamanhos e PKGBUILD
    │   └── OperationsLogDrawer.qml # Drawer expansível de terminal e prompts interativos em tempo real
    └── pages/
        ├── HomePage.qml        # Página inicial com 8 seções de descoberta e status de sincronização
        ├── CatalogPage.qml     # Página de catálogo com grade responsiva, filtros e paginação
        ├── InstalledPage.qml   # Biblioteca de pacotes instalados com filtro explícito/dependência
        └── UpdatesPage.qml     # Central de atualizações pendentes com resultado pós-verificado
```

---

## 3. Catálogo Inteligente e Descoberta de Pacotes

### 3.1 Indexação de Repositórios Oficiais
A Redshift Store não se limita aos pacotes instalados localmente. O `CatalogService` realiza a leitura direta dos arquivos compactados `/var/lib/pacman/sync/*.db` (`core.db`, `extra.db`, `multilib.db`), mapeando:
- Nome e versão mais recente nos repositórios oficiais.
- Resumo e descrição detalhada.
- Tamanho de download e tamanho instalado descompactado.
- Repositório de origem (`core`, `extra`, `multilib`).
- Dependências diretas e opcionais.
- Licença de software e URL oficial upstream.

O índice é persistido em formato JSON comprimido em `~/.cache/redshift-store/sync_index_v2.json`. Ao iniciar, o leitor compara os carimbos de data/hora (`mtime`) e tamanho (`size`) dos bancos locais com o cabeçalho de assinatura do cache. Se idênticos, o carregamento ocorre em **menos de 50 milissegundos**, disponibilizando instantaneamente todo o universo de mais de 15.700 pacotes oficiais.

### 3.2 Descoberta do AUR (Arch User Repository)
A busca por pacotes comunitários é realizada via API RPC v5 do AUR (`https://aur.archlinux.org/rpc/v5/`). Para evitar sobrecarga de rede e requisições repetitivas:
- As buscas são debounced (300ms).
- Consultas idênticas são cacheadas em memória (TTL de 120s) e em disco sob `~/.cache/redshift-store/aur/`.
- Quando o usuário visualiza a seção do AUR sem digitar nenhum termo, a loja apresenta **6 seções temáticas de descoberta comunitária** alimentadas por consultas em lote:
  - *Mais Votados da Comunidade* (`aur_popular`)
  - *Destaques Comunitários* (`aur_community`)
  - *Desenvolvimento & Compiladores* (`aur_dev`)
  - *Jogos & Emulação* (`aur_games`)
  - *Produtividade & Escritório* (`aur_productivity`)
  - *Curadoria Especial da Comunidade* (`aur_curated`)

### 3.3 Transparência Total de Métricas
Ao contrário de lojas que apresentam métricas genéricas de "downloads" para pacotes do Arch Linux (o que não existe nativamente no pacman nem no AUR), a Redshift Store mantém transparência técnica absoluta:
- **Pacotes Oficiais:** Exibem porcentagem de popularidade informada pelo projeto **pkgstats** (baseado na base de usuários reais do Arch Linux), como `69.1% dos usuários Arch (pkgstats)`.
- **Pacotes do AUR:** Exibem votos e pontuação de popularidade do AUR RPC, como `1.240 votos (AUR) • 14.5 popularidade`.
- **Procedência:** Todo pacote apresenta rótulo explicativo claro em seu cartão e na janela de detalhes (ex.: `Repositório Oficial Extra`, `Arch User Repository (AUR)`).

---

## 4. Recomendações Locais e Privacidade

O sistema de recomendações da Redshift Store é **100% executado localmente** no dispositivo do usuário:
- **Armazenamento:** Salvo exclusivamente no arquivo local `$XDG_STATE_HOME/redshift-store/user_preferences.json`.
- **Sinais Coletados:** Categorias navegadas recentemente, termos de busca pesquisados e pacotes marcados como favoritos.
- **Transparência:** Todo item recomendado na página inicial possui uma etiqueta de proveniência (`provenanceLabel`) explicando claramente a razão de sua exibição:
  - `"Relacionado à sua pesquisa de Desenvolvimento"`
  - `"Relacionado a aplicativos que você favoritou"`
  - `"Baseado em categorias exploradas frequentemente"`
- **Controles do Usuário:**
  - O usuário pode desativar a personalização a qualquer momento (`StoreController.setPersonalizationEnabled(false)`). Ao desativar, a loja reverte automaticamente para a curadoria editorial estática.
  - O usuário pode limpar imediatamente todo o histórico local com um clique no botão "Limpar Histórico" (`StoreController.clearPersonalizationHistory()`).

---

## 5. Gerenciamento Seguro de Atualizações

### 5.1 Prevenção de Partial Upgrades no Arch Linux
No ecossistema Arch Linux, atualizar uma única biblioteca oficial de forma isolada (`pacman -Sy foo`) pode quebrar dependências de executáveis já instalados no sistema (cenário de *partial upgrade*). A Redshift Store implementa guardrails rígidos:
1. Ao clicar no botão de atualizar em um pacote oficial individual na página de atualizações, a loja emite uma notificação informativa e redireciona automaticamente para a rotina de **Atualização Completa do Sistema** (`updateAll`).
2. Pacotes comunitários do AUR podem ser atualizados individualmente de forma segura (`updatePackage(pkg_name, "aur")`), uma vez que são compilados contra as versões de bibliotecas já presentes no sistema.
3. A ação **Atualizar Tudo** dispara `yay -Syu --sudo /usr/bin/pkexec`, garantindo que tanto a base oficial quanto os pacotes do AUR sejam sincronizados de ponta a ponta sem descompasso.

### 5.2 Fluxo de Pós-Verificação Real de Transações
Ao concluir a execução do gerenciador de pacotes, a loja não assume cegamente que todas as atualizações foram aplicadas com sucesso:
- O `CatalogService.check_updates()` é reexecutado em segundo plano para inspecionar os pacotes remanescentes.
- O resultado é classificado e exposto via propriedade `lastUpdateOutcome`:
  - `"complete"`: Todas as atualizações pendentes foram aplicadas com sucesso (restam 0 pacotes).
  - `"partial"`: A transação concluiu, mas pacotes continuam pendentes (por exemplo, dependências retidas em `IgnorePkg` ou espelhos desatualizados).
  - `"cancelled"`: A operação foi interrompida pelo usuário antes da escrita no disco.
  - `"failed"`: Ocorreu erro de rede, conflito de arquivos ou interrupção inesperada no gerenciador de pacotes.
- Um toast com mensagem clara informa o resultado exato ao usuário.

---

## 6. Segurança e Guardrails Defensivos

A Redshift Store atua com rígidas proteções contra ações acidentais ou maliciosas:

| Vetor de Risco | Mitigação Implementada |
| :--- | :--- |
| **Injeção de Parâmetros e Flags** | Nomes de pacotes são validados contra `^[a-zA-Z0-9][a-zA-Z0-9@._+-]{0,127}$`. Qualquer string iniciando com hífen (`-Syu`, `--noconfirm`) é terminantemente recusada. Os comandos finais utilizam o delimitador `--` antes da lista de pacotes. |
| **Injeção de Shell / Metacaracteres** | Comandos são executados estritamente via lista de argumentos (`QProcess` com `argv`), dispensando `sh -c` ou interpretação de shell para operações privilegiadas. |
| **Quebra de Sistema por Remoção Acidental** | Pacotes essenciais (`pacman`, `linux`, `glibc`, `systemd`, `hyprland`, `quickshell`, `python-pyqt6`, etc.) constam em `PROTECTED_PACKAGES`. Qualquer solicitação de remoção desses pacotes é bloqueada no backend antes de iniciar qualquer processo. |
| **Execução de AUR sob Root** | O AUR permite execução de scripts arbitrários de compilação (`PKGBUILD`). O método `ensure_non_root_for_aur()` impede que o `yay` seja executado se o `EUID == 0`. A elevação final para instalação do binário é delegada ao Polkit via `--sudo /usr/bin/pkexec`. |
| **Conflitos de Concorrência do Pacman** | O estado do lock (`/var/lib/pacman/db.lck`) é verificado antes de iniciar qualquer transação, notificando o usuário com mensagem informativa caso outra ferramenta (ex.: terminal) esteja operando a base de dados. |
| **Auditoria Visual e Interativa de PKGBUILDs (AUR)** | Ao inspecionar pacotes do AUR, a Redshift Store busca e exibe o código do `PKGBUILD` na aba de auditoria da janela de detalhes. Durante a instalação/atualização via `yay`, os menus interativos `--cleanmenu` e `--diffmenu` são preservados (com `GIT_PAGER=cat` e `PAGER=cat`), permitindo revisar o diff completo no `OperationsLogDrawer` e responder via botões rápidos ou entrada manual. |
| **Cancelamento Seguro por Estágio (Sem SIGKILL)** | O cancelamento usa exclusivamente `SIGTERM` nos estágios seguros (`checking_updates`, `authenticating`, `downloading`, `compiling`) e é bloqueado durante modificações críticas do banco (`committing` ou quando `/var/lib/pacman/db.lck` existe). |

---

## 7. Como Usar

### 7.1 Linha de Comando e Launcher
O launcher executável está disponível no PATH do usuário:
```bash
redshift-store [OPÇÕES]
```

### Opções Disponíveis:
- `--page <home|catalog|installed|updates>`: Abre diretamente na página especificada.
  ```bash
  redshift-store --page updates    # Abre diretamente na central de atualizações
  redshift-store --page catalog    # Abre diretamente na página de catálogo/explorar
  ```
- `--mock`: Inicia a aplicação em modo de simulação (dados mockados, sem efetuar alterações reais de pacotes no sistema).
- `--self-test`: Executa validação headless de inicialização, verificação de modelos e parsing do QML, encerrando com código `0` em caso de sucesso.
- `--version`: Exibe a versão instalada da Redshift Store.

### 7.2 Lançador de Aplicativos (Menu / Rofi / Fuzzel)
A aplicação instala o arquivo `.desktop` padrão em `~/.local/share/applications/redshift-store.desktop`:
- **Nome:** Redshift Store (Central de Aplicativos)
- **Categorias:** `System;PackageManager;Settings;`
- **Ações Rápidas (Desktop Actions):**
  - *Verificar Atualizações*: dispara `redshift-store --page updates`.
  - *Pacotes Instalados*: dispara `redshift-store --page installed`.

---

## 8. Testes Automatizados e Qualidade

O projeto conta com uma abrangente suíte de testes automatizados com mocks rigorosos e isolamento de ambiente:

### 8.1 Suíte de Testes Unitários e Integração QML (Python)
Executa **27 baterias completas de testes** (`tests/test_redshift_store.py`) cobrindo:
- Guardrails de segurança, validação de nomes, bloqueio de pacotes protegidos e cancelamento em estágios seguros.
- Mapeamento e serialização de todos os 34 roles do `PackageListModel` e método incremental `append_items()`.
- Cenários A a G:
  - *Cenário A:* Exibição de dezenas de aplicativos não instalados após instalação limpa do sistema.
  - *Cenário B:* Busca de aplicativo oficial não instalado (`0ad`, `supertuxkart`, `krita`) retornando versão, repositório e detalhes completos do sync DB.
  - *Cenário C:* Filtragem da categoria `games` sem texto exibindo múltiplos jogos não instalados disponíveis nos repositórios.
  - *Cenário D:* Exploração exclusiva da origem `AUR` ativando as 6 seções de descoberta com etiquetas transparentes e métricas de votos (sem termos "downloads").
  - *Cenário E:* Resiliência contra perda de conexão à internet, mantendo operação normal via cache local e reportando status `network_error` para buscas não cacheadas no AUR.
  - *Cenário F:* Cenários de 36 atualizações oficiais, atualizações mistas (oficiais + AUR), fluxo de pós-verificação em dois estágios e redirecionamento seguro anti-partial upgrade.
  - *Cenário G:* Troca ao vivo de wallpaper e geração dinâmica de paleta Material You atualizando os tokens M3 em tempo real sem reinicialização.
- Controles de privacidade e histórico de personalização local.

Comando para execução:
```bash
QT_QPA_PLATFORM=offscreen python3 -m unittest discover -s tests -p "test_redshift_store.py" -v
```

### 8.2 Suíte Global de Regressão do Repositório (`run-tests.sh`)
A suíte completa em `tests/run-tests.sh` cobre **181 testes automatizados**, validando portabilidade de permissões, compatibilidade de distribuição, perfis declarativos (`minimal`, `hybrid`, `complete`), scripts de instalação e desinstalação limpa em sandboxes isolados e autoteste headless:
```bash
bash tests/run-tests.sh
```
