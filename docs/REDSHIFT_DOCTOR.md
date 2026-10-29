# Redshift Doctor & Sistema de Resiliência do Redshift OS

O **Redshift Doctor** (`redshift-doctor`) é o utilitário oficial de diagnóstico, auditoria de integridade e auto-recuperação do Redshift OS. Ele foi concebido para proteger o ambiente gráfico, detectar descompassos de ABI decorrentes de atualizações do Arch Linux (Qt6 e Quickshell) e fornecer mecanismos determinísticos de reparo sem exigir intervenção manual ou riscos de quebra de sessão.

---

## 1. Arquitetura e Contrato de Execução

### Princípios de Design
- **Read-Only por Padrão:** Os comandos de checagem (`--check`, `--report`, `--json`) nunca alteram arquivos, nunca modificam pacotes e **não requerem privilégios de root (`sudo`)**.
- **Códigos de Saída Semânticos:**
  - `0`: Sistema íntegro (OK).
  - `1`: Erro crítico ou incompatibilidade identificada (ERROR).
  - `2`: Alerta não-bloqueante ou manutenção necessária (WARN).
- **Formatação Dual:** Apresenta saída visual limpa com tags ANSI coloridas (`[OK]`, `[WARN]`, `[ERROR]`) no terminal interativo e formato JSON estruturado com `--json` para integração com a **Redshift Store** e automações.
- **Auto-Recuperação Controlada (`--repair`):** Ações de modificação (recompilação, reparo em espaço de usuário, reinstalação de pacotes) exigem confirmação explícita do usuário (`[s/N]`), com suporte a `-y`/`--yes` para automações headless.

---

## 2. Comandos CLI Suportados

```bash
# Diagnóstico completo de todos os subsistemas
redshift-doctor --check

# Diagnósticos focados em componentes específicos
redshift-doctor --check caelestia    # Frontend Caelestia, plugin nativo e compatibilidade Qt6
redshift-doctor --check quickshell   # Binário quickshell, estado de execução e IPC
redshift-doctor --check packages     # Metapacotes, pacman e bibliotecas compartilhadas

# Relatórios estruturados
redshift-doctor --report             # Relatório legível completo
redshift-doctor --json               # Relatório estruturado em formato JSON (parseável via jq)

# Recuperação assistida
redshift-doctor --repair caelestia   # Reparo interativo guiado do plugin nativo Caelestia
```

---

## 3. Verificação em Três Níveis no `ui-switch.sh`

O script de alternância de frontends (`ui-switch.sh`) implementa um protocolo rigoroso de verificação em 3 níveis antes de transicionar a interface:

1. **Nível 1 — Instalação:**
   - Valida a presença e permissão de leitura de `Caelestia/qmldir` e bibliotecas nativas `.so` (`libcaelestia-coreplugin.so` ou `lib/libcaelestia-core.so`).
   - Busca nos caminhos padrão do Qt6 (`/usr/lib/qt6/qml`, `/usr/local/lib/qt6/qml`), caminhos de usuário (`$HOME/.local/lib/qt6/qml`, `$XDG_DATA_HOME/quickshell/qml`) ou override via `$CAELESTIA_QML_PATH`.
   - Mensagem de falha acionável: *"Instalação incompleta ou ausente: plugin nativo Caelestia não encontrado. Execute 'redshift-doctor --check caelestia'."*

2. **Nível 2 — Compatibilidade:**
   - Executa inspeção dinâmica rápida via `ldd -r` nas bibliotecas nativas encontradas para detectar símbolos não resolvidos (`undefined symbol`) ou bibliotecas dinâmicas ausentes (`not found`) após upgrades do Qt6.
   - Mensagem de falha acionável: *"Incompatibilidade detectada entre Caelestia e Qt6/Quickshell. Execute 'redshift-doctor --repair caelestia'."*

3. **Nível 3 — Operacionalidade e Rollback Seguro:**
   - Inicia o processo com os caminhos corretos exportados em `QML_IMPORT_PATH` e `QML2_IMPORT_PATH`.
   - Monitora a estabilidade do processo após o startup (`UI_SWITCH_STABILITY_SLEEP`) para capturar eventuais falhas logo após `Configuration Loaded`.
   - Em caso de falha de inicialização ou recusa de reload do Hyprland, aciona automaticamente `restore_end4`, restaurando a interface `end-4` e notificando o usuário. **O usuário nunca fica sem ambiente gráfico.**

---

## 4. Prevenção de Regressões Pós-Atualização (Hook do Pacman)

O Redshift OS inclui um hook ALPM/Pacman preventivo:
- **Arquivo:** `sdata/dist-arch/redshift-doctor-check.hook` (instalado em `/usr/share/libalpm/hooks/redshift-doctor-check.hook`).
- **Gatilhos:** Upgrades ou instalações de `qt6-base`, `qt6-declarative`, `quickshell*`, `illogical-impulse-quickshell-git` e `illogical-impulse-caelestia-plugin`.
- **Garantias de Segurança:**
  - Executa em `PostTransaction`.
  - **NÃO** executa makepkg ou compilações como root.
  - **NÃO** bloqueia nem aborta transações completas do sistema (`pacman -Syu`).
  - Cria um marcador volátil em `/tmp/.redshift-needs-doctor` e no estado do usuário `${XDG_STATE_HOME}/redshift-os/needs-health-check`.
  - O autostart do compositor (`execs.lua`) e a **Redshift Store** detectam o marcador e orientam o usuário a executar o diagnóstico sem surpresas.

---

## 5. Integração com a Redshift Store

A **Redshift Store** integra verificação reativa de saúde através de:
- **Backend:** `MaintenanceService` (`maintenance_service.py`), que consulta o `redshift-doctor` e executa verificações de integridade de plugins e linkagem sem criar dependência circular.
- **Frontend QML:** Componentes `MaintenanceBanner.qml` e `MaintenanceDetailDialog.qml`.
- **Ações Disponíveis na UI:**
  - *Ver detalhes:* Exibe a causa raiz real detectada em formato monospace (evitando mensagens genéricas de "instale o pacote" quando o pacote já está presente).
  - *Executar diagnóstico:* Aciona o `redshift-doctor --check`.
  - *Reparar componente:* Dispara o reparo assíncrono controlado.

---

## 6. Integração com o Instalador `./setup`

Nos perfis `hybrid` e `complete`, o instalador `./setup`:
1. Valida a presença e linkagem do plugin Caelestia pós-instalação (`verify_post_install_caelestia`).
2. Registra o resultado no log oficial de instalação.
3. Informa claramente ao usuário o status de prontidão do Caelestia.
4. Em caso de ausência ou falha, mantém a instalação íntegra forçando o fallback seguro para `end-4`, sem quebrar a idempotência do sistema.
5. Preserva integralmente o perfil `minimal` (que opera estritamente com `end-4`).
