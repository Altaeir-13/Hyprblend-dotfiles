# Fase 4 — Procedimento de teste em VM (Arch Linux descartável)

> **Status: NÃO EXECUTADO.** O host não possui QEMU/OVMF/devtools (ver "Bloqueio").
> Nada abaixo foi rodado. Os scripts em `tests/vm/` foram testados apenas quanto a
> sintaxe, determinismo do bundle e recusa de execução fora de VM.

## 0. Bloqueio e autorização necessária

Inventário do host (somente leitura, 2026-10-23):

| Item | Estado |
|---|---|
| CPU / VT-x | i5-1335U, 12 threads, `vmx` presente |
| `/dev/kvm` | existe, `crw-rw-rw-` (nenhuma mudança de grupo necessária) |
| RAM | 11 GiB total, ~7 GiB disponíveis com a sessão atual |
| Disco | 318 GB livres em `/` (`/tmp` é tmpfs de 5,7 GB: **não** usar para imagens) |
| GPU | Intel Iris Xe, `/dev/dri/renderD128` acessível (rende virgl no host) |
| qemu, libvirt, virt-manager, OVMF, swtpm | **ausentes** |
| devtools (`pkgctl`), namcap, archiso | **ausentes** |
| ISO/imagem Arch | **ausente** |
| `makepkg`, `systemd-nspawn`, `bsdtar`, `python3`, `rsync`, `jq`, `yq` | presentes |

Pacotes mínimos a instalar **no host**, se autorizado (nenhum serviço, daemon ou grupo):

```bash
sudo pacman -S --needed qemu-desktop edk2-ovmf
```

Sem libvirt: o QEMU roda como processo comum do usuário. `devtools`/`namcap` **não** são
instalados no host; a compilação limpa ocorre dentro da VM (seção 3).

## 1. Pacote rastreável do repositório (já funciona, sem push)

```bash
tests/vm/bundle.sh create  <out>             # no host, somente leitura
tests/vm/bundle.sh verify  <out> <workdir>   # no host ou na VM
```

Gera `repo.bundle` (histórico git completo), `overlay.tar.gz` (modificados + não rastreados,
339 arquivos, tar determinístico), `OVERLAY.sha256`, `BASE_REVISION`, `SHA256SUMS`.
Recusa incluir `.env`, chaves, `*.so`, `build*/`, `cache/`, logs e pacotes.

Resultado de 2026-10-23 (base `2f2a376f…`, branch `feature/hybrid-rice-installer`):

```
a282c9801f4236614d5cc5397dd632554b6d8667f3013d86be5b6435bb5f502d  overlay.tar.gz
5e0d7034353448f829fd718dc36f3fa6bea4a14d1a316a3be71f63af2d57ba78  OVERLAY.sha256
```

Duas execuções consecutivas produziram hashes idênticos. O submódulo `shapes` não é
empacotado; o instalador o busca no gitlink fixado, o que exige rede na VM.

## 2. Criar a VM (comandos a executar após autorização)

Resumo: imagem cloud oficial do Arch + cloud-init `NoCloud` via HTTP local, sem instalar
`cloud-localds`/`xorriso`. **Não verificado:** o comportamento exato da imagem; confirmar
na primeira execução.

```bash
W=~/vm-hybrid-rice && mkdir -p $W && cd $W
# imagem + checksum oficiais: https://geo.mirror.pkgbuild.com/images/latest/
#   Arch-Linux-x86_64-cloudimg.qcow2 e .SHA256  → conferir com sha256sum -c
qemu-img create -f qcow2 -F qcow2 -b Arch-Linux-x86_64-cloudimg.qcow2 base.qcow2 40G
cp /usr/share/edk2/x64/OVMF_VARS.4m.fd .      # caminho a confirmar após instalar edk2-ovmf
```

Cada perfil usa um overlay descartável sobre `base.qcow2` já provisionada (seção 3), de modo que
os três testes partem do mesmo estado limpo e independentes:

```bash
qemu-img create -f qcow2 -F qcow2 -b base.qcow2 run-minimal.qcow2
qemu-system-x86_64 -enable-kvm -cpu host -smp 4 -m 4096 \
  -machine q35 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/x64/OVMF_CODE.4m.fd \
  -drive if=pflash,format=raw,file=OVMF_VARS.4m.fd \
  -drive file=run-minimal.qcow2,if=virtio \
  -nic user,model=virtio-net-pci,hostfwd=tcp::2222-:22 \
  -device virtio-vga-gl -display gtk,gl=on
```

Recursos sugeridos: 4 vCPU, 4 GiB (a sessão atual do host usa ~4,3 GiB), disco thin de 40 GB.

## 3. Compilar o plugin (dentro da VM)

Usuário não-root na VM:

```bash
sudo pacman -Syu --needed base-devel devtools git namcap
# libcava e mpvpaper são AUR (ver achado F-01): construir ANTES, em repositório local
pkgctl build   # em sdata/dist-arch/illogical-impulse-caelestia-plugin
namcap  *.pkg.tar.zst
tests/vm/check-plugin-package.sh *.pkg.tar.zst
```

Critérios de aceite: `qmldir` em `usr/lib/qt6/qml/Caelestia/`, **zero** FAIL no
`check-plugin-package.sh`, nenhum RUNPATH fora de `/usr`/`$ORIGIN`, `namcap` sem erros, e
dlopen isolado de cada `lib*plugin.so` com sucesso (`guest-verify.sh`).

## 4. Matriz de testes de instalação

Em cada overlay, com o repo verificado em `~/dots-hyprland`:

```bash
tests/vm/guest-seed.sh                                   # arquivos de usuário pré-existentes
./setup install -p <perfil> -f --log-file ~/install-<perfil>.log ; echo "exit=$?"
tests/vm/guest-verify.sh <perfil> --seeded
```

| # | Cenário | Esperado |
|---|---|---|
| 1 | minimal limpo | sem caelestia; `ui-switch/current=end4` |
| 2 | hybrid limpo | plugin + `caelestia-hybrid` instalados |
| 3 | complete limpo | + easyeffects, fish, foot, kitty, starship |
| 4 | minimal → hybrid → complete | transição sem perda; backup original intacto |
| 5 | reexecução do mesmo perfil | `.new`, sem sobrescrever `ii-original-dots-backup` |
| 6 | `--exp-files` vs legacy | mesma árvore final (comparar com `diff -r`) |
| 7 | interrupção (`kill -INT` no meio) + reexecução | `installed_true` ausente até o fim; reexecução completa |
| 8 | `--dry-run` | zero mudanças em `$HOME` |

**Sobre "rollback":** o instalador **não** restaura o estado anterior. Ele cria backups e
`.old`/`.new`. Cada cenário deve registrar isso como "backup preservado", não "rollback".
Só `ui-switch.sh` faz rollback real (de frontend).

## 5. Sessão gráfica

Rodar `Hyprland` na VM, validar end-4, Caelestia, `ui-switch.sh toggle`, StatusCenter, atalhos,
`rice-lock`, wallpapers (png/gif/mp4), sincronia de cores, reinício de sessão. Medir
`ps -o rss`, contagem de `qs`/`mpvpaper` duplicados e logs (`/tmp/quickshell-ii.log`,
`/tmp/caelestia-hybrid.log`). **Não verificado:** se virgl em `virtio-vga-gl` sustenta
Hyprland + Qt Quick RHI. Em falha, distinguir limitação da GPU virtual (ex.: crash em
`eglInitialize`/shader) de erro do instalador (arquivo ausente, QML import error).
