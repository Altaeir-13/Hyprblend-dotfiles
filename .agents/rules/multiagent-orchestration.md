# Governança e Orquestração Multiagente do Redshift OS

Este repositório utiliza uma arquitetura multiagente nativa do Google Antigravity 2.0, com agentes especializados definidos em `.agents/agents/`.

## 1. Papéis de Modelos

- **Orquestrador Principal (`Gemini 4 Argon - High`)**:
  - Responsável por análise arquitetural, planejamento de implementação, decomposição de tarefas, definição de contratos/interfaces, revisão de segurança, integração entre módulos, resolução de conflitos e validação final.
  - **Regra**: Não utilize o modelo principal para executar rotineiramente tarefas operacionais (pesquisa de código, leitura extensa de arquivos, implementação de componentes isolados, testes unitários e documentação) que os subagentes Flash executam com qualidade equivalente.
- **Subagentes Executores (`model: flash` → `gemini-3.8-flash-tiered`)**:
  - Invocados via `invoke_subagent` com `Model: "flash"`.
  - Limite máximo de paralelismo simultâneo: **4 subagentes**.
  - Para tarefas paralelas com escrita em arquivos, utilize isolamento de workspace (`Workspace: "share"` ou `"branch"`, equivalente a Git worktree isolado) e nunca atribua o mesmo arquivo a dois subagentes concorrentes.

## 2. Equipe de Subagentes Especializados (`.agents/agents/`)

1. **`redshift-ui-engineer`** ([redshift-ui-engineer.md](file:///home/greyrat/Projetos/dots-hyprland/.agents/agents/redshift-ui-engineer.md)):
   - Interface Qt6/QML, Quickshell, páginas, cards, navegação, layouts responsivos, animações e estados visuais seguindo o design system do Redshift OS.
2. **`package-backend-engineer`** ([package-backend-engineer.md](file:///home/greyrat/Projetos/dots-hyprland/.agents/agents/package-backend-engineer.md)):
   - Serviços Python assíncronos, integração com `pacman`, `yay`, AppStream e AUR RPC, logs em tempo real, locks e contratos de comunicação QML-Python.
3. **`material-you-integration-engineer`** ([material-you-integration-engineer.md](file:///home/greyrat/Projetos/dots-hyprland/.agents/agents/material-you-integration-engineer.md)):
   - Infraestrutura de cores Material You / Matugen, tokens semânticos, sincronização de temas claro/escuro e monitoramento de paleta nos modos end-4 e Caelestia Shell.
4. **`quality-and-installer-engineer`** ([quality-and-installer-engineer.md](file:///home/greyrat/Projetos/dots-hyprland/.agents/agents/quality-and-installer-engineer.md)):
   - Testes automatizados (unitários, integração, segurança em sandbox/mocks), `PKGBUILD`, integração no `./setup` (perfis `minimal`, `hybrid` e `complete`), arquivos `.desktop`/launchers e documentação.

## 3. Regras de Segurança e Qualidade

- Operações privilegiadas, manipulação de banco do `pacman`, scripts do AUR e autenticação exigem revisão direta do orquestrador Argon.
- Subagentes não têm autorização para executar operações destrutivas reais na máquina principal nem aprovar sozinhos a qualidade final de suas entregas.
- Nunca executar `yay` ou `makepkg` como `root`, nunca armazenar credenciais e nunca suprimir prompts de segurança.
