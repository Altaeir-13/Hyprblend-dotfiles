# Perfis de Instalação (`sdata/profiles/`)

O instalador `./setup` suporta três perfis declarativos selecionáveis via `--profile <minimal|hybrid|complete>`:

| Perfil | Manifesto | Descrição |
| :--- | :--- | :--- |
| `minimal` | `sdata/profiles/minimal.conf` | Hyprland + frontend `end-4` (`quickshell/ii`) + `rice-lock`. Não instala o frontend nem o plugin nativo do Caelestia e pula configurações periféricas (`--core`). |
| `hybrid` *(padrão)* | `sdata/profiles/hybrid.conf` | Hyprland + `end-4` (`quickshell/ii`) + `caelestia-hybrid` + `ui-switch.sh` + `rice-lock` + `caelestia/shell.json` + plugin nativo `illogical-impulse-caelestia-plugin` (`mpvpaper`, `libcava`, `aubio`, `lm_sensors`, `libqalculate`). |
| `complete` | `sdata/profiles/complete.conf` | Tudo do perfil `hybrid` + aplicativos e integrações opcionais (`easyeffects`, `plasma-browser-integration`, `fish`, `foot`, `kitty`, `starship`) e todas as customizações de aplicativos em `dots/.config/`. |
