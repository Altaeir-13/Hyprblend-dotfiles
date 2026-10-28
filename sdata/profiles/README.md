# Perfis de Instalação (`sdata/profiles/`)

O instalador `./setup` suporta três perfis declarativos selecionáveis via `--profile <minimal|hybrid|complete>`:

| Perfil | Manifesto | Descrição |
| :--- | :--- | :--- |
| `minimal` | `sdata/profiles/minimal.conf` | Hyprland + frontend `end-4` (`quickshell/ii`) + `rice-lock` + `redshift-store` (`illogical-impulse-redshift-store`). Não instala o frontend nem o plugin nativo do Caelestia e pula configurações periféricas (`--core`). |
| `hybrid` *(padrão)* | `sdata/profiles/hybrid.conf` | Hyprland + `end-4` (`quickshell/ii`) + `caelestia-hybrid` + `ui-switch.sh` + `rice-lock` + `redshift-store` + `caelestia/shell.json` + plugin nativo `illogical-impulse-caelestia-plugin` (`mpvpaper`, `libcava`, `aubio`, `lm_sensors`, `libqalculate`). |
| `complete` | `sdata/profiles/complete.conf` | Tudo do perfil `hybrid` + aplicativos e integrações opcionais (`easyeffects`, `plasma-browser-integration`, `fish`, `foot`, `kitty`, `starship`) e todas as customizações de aplicativos em `dots/.config/`. |

### Metapacotes e Alvos Gerenciados da Redshift Store
Todos os três perfis declarativos incluem o metapacote `illogical-impulse-redshift-store` e gerenciam os seguintes alvos em `MANAGED_CONFIG_TARGETS`:
- `$XDG_BIN_HOME/redshift-store` (launcher executável)
- `$XDG_DATA_HOME/applications/redshift-store.desktop` (lançador de aplicativo XDG)
- `$XDG_DATA_HOME/redshift-os` (código-fonte, assets e metadados da aplicação em `redshift-os/redshift-store`)

