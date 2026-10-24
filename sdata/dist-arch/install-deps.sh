# This script is meant to be sourced.
# It's not for directly running.

install-yay(){
  if $ask; then
    x sudo pacman -S --needed base-devel git
  else
    x sudo pacman -S --needed --noconfirm base-devel git
  fi
  x rm -rf /tmp/buildyay
  x git clone https://aur.archlinux.org/yay-bin.git /tmp/buildyay
  x cd /tmp/buildyay
  if $ask; then
    x makepkg -si
  else
    x makepkg -si --noconfirm
  fi
  x cd ${REPO_ROOT}
  x rm -rf /tmp/buildyay
}

remove_deprecated_dependencies(){
  local list=()
  list+=(illogical-impulse-{microtex,pymyc-aur,oneui4-icons-git})
  list+=(hyprland-qtutils)
  list+=({quickshell,hyprutils,hyprpicker,hyprlang,hypridle,hyprland-qt-support,hyprland-qtutils,hyprlock,xdg-desktop-portal-hyprland,hyprcursor,hyprwayland-scanner,hyprland}-git)
  list+=(matugen-bin)

  local found=()
  local pkg
  for pkg in "${list[@]}"; do
    if pacman -Qq "$pkg" >/dev/null 2>&1; then
      found+=("$pkg")
    fi
  done

  if (( ${#found[@]} == 0 )); then
    return 0
  fi

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    echo -e "${STY_YELLOW}[DRY-RUN] Detected installed deprecated packages: ${found[*]}. Would request safe removal via 'pacman -R'.${STY_RST}"
    return 0
  fi

  echo -e "${STY_YELLOW}[$0]: Detected deprecated packages from previous rice versions:${STY_RST}"
  for pkg in "${found[@]}"; do
    echo -e "  - ${STY_CYAN}${pkg}${STY_RST}"
  done
  echo -e "${STY_YELLOW}These legacy packages may conflict with current release dependencies.${STY_RST}"
  echo -e "${STY_YELLOW}Policy: The installer will NEVER use destructive forced cascade removal. Only safe removal ('pacman -R') is permitted.${STY_RST}"

  local do_remove=false
  if $ask; then
    echo -e "${STY_BLUE}Would you like to safely remove these deprecated packages using 'pacman -R'? [y/N]${STY_RST}"
    local p
    read -p "====> " p
    case $p in
      [yY]*) do_remove=true ;;
      *) echo -e "${STY_BLUE}[$0]: Skipping removal of deprecated packages.${STY_RST}" ;;
    esac
  else
    # Force/unattended mode: attempt safe removal without bypassing dependency checks
    echo -e "${STY_YELLOW}[$0]: Non-interactive mode: Attempting safe removal with standard dependency verification...${STY_RST}"
    do_remove=true
  fi

  if [[ "$do_remove" == true ]]; then
    if $ask; then
      if ! sudo pacman -R "${found[@]}"; then
        echo -e "${STY_YELLOW}[$0]: WARNING: Some deprecated packages could not be removed due to reverse dependencies. Continuing safely.${STY_RST}"
      fi
    else
      if ! sudo pacman -R --noconfirm "${found[@]}"; then
        echo -e "${STY_YELLOW}[$0]: WARNING: Some deprecated packages could not be removed due to reverse dependencies. Continuing safely.${STY_RST}"
      fi
    fi
  fi
}
# NOTE: `implicitize_old_dependencies()` was for the old days when we just switch from dependencies.conf to local PKGBUILDs.
# However, let's just keep it as references for other distros writing their `sdata/dist-<OS_GROUP_ID>/install-deps.sh`, if they need it.
implicitize_old_dependencies(){
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    echo -e "${STY_YELLOW}[DRY-RUN] Would convert previously explicit dependencies to implicit.${STY_RST}"
    return 0
  fi
# Convert old dependencies to non explicit dependencies so that they can be orphaned if not in meta packages
  remove_bashcomments_emptylines ./sdata/dist-arch/previous_dependencies.conf ./cache/old_deps_stripped.conf
  readarray -t old_deps_list < ./cache/old_deps_stripped.conf
  pacman -Qeq > ./cache/pacman_explicit_packages
  readarray -t explicitly_installed < ./cache/pacman_explicit_packages

  echo "Attempting to set previously explicitly installed deps as implicit..."
  for i in "${explicitly_installed[@]}"; do for j in "${old_deps_list[@]}"; do
    [ "$i" = "$j" ] && yay -D --asdeps "$i"
  done; done

  return 0
}

#####################################################################################
if ! command -v pacman >/dev/null 2>&1; then
  printf "${STY_RED}[$0]: pacman not found, it seems that the system is not ArchLinux or Arch-based distros. Aborting...${STY_RST}\n"
  exit 1
fi

# Keep makepkg from resetting sudo credentials
if [[ -z "${PACMAN_AUTH:-}" ]]; then
  export PACMAN_AUTH="sudo"
fi

showfun remove_deprecated_dependencies
v remove_deprecated_dependencies

# Issue #363
case $SKIP_SYSUPDATE in
  true) true;;
  *)
    if $ask; then
      v sudo pacman -Syu
    else
      v sudo pacman -Syu --noconfirm
    fi
    ;;
esac

# Use yay. Because paru does not support cleanbuild.
# Also see https://wiki.hyprland.org/FAQ/#how-do-i-update
if ! command -v yay >/dev/null 2>&1;then
  echo -e "${STY_YELLOW}[$0]: \"yay\" not found.${STY_RST}"
  showfun install-yay
  v install-yay
fi

showfun implicitize_old_dependencies
v implicitize_old_dependencies

# https://github.com/end-4/dots-hyprland/issues/581
# yay -Bi is kinda hit or miss, instead cd into the relevant directory and manually source and install deps
install-local-pkgbuild() {
  local location=$1
  local installflags=$2

  x pushd $location

  source ./PKGBUILD
  local -a all_deps=()
  if [[ -n "${depends[*]:-}" ]]; then
    all_deps+=("${depends[@]}")
  fi
  if [[ -n "${makedepends[*]:-}" ]]; then
    all_deps+=("${makedepends[@]}")
  fi
  if (( ${#all_deps[@]} > 0 )); then
    local -a yay_cmd=(yay -S --sudoloop)
    if [[ "$installflags" == *"--noconfirm"* ]]; then
      yay_cmd+=(--answerclean None --answerdiff None --answeredit None --answerupgrade None)
    fi
    x "${yay_cmd[@]}" $installflags --asdeps "${all_deps[@]}"
  fi
  # man makepkg:
  # -A, --ignorearch: Ignore a missing or incomplete arch field in the build script.
  # -s, --syncdeps: Install missing dependencies using pacman. When build-time or run-time dependencies are not found, pacman will try to resolve them.
  # -f, --force: build a package even if it already exists in the PKGDEST
  # -i, --install: Install or upgrade the package after a successful build using pacman(8).
  local -a makepkg_cmd=(makepkg -Afsi)
  if [[ "$installflags" == *"--noconfirm"* ]]; then
    makepkg_cmd+=(--noconfirm)
  fi
  x "${makepkg_cmd[@]}"
  x popd
}

# Install dependencies from the profile manifest (or fallback to default hybrid list)
if [[ ${#ARCH_METAPKGS[@]} -gt 0 ]]; then
  metapkgs=("${ARCH_METAPKGS[@]}")
else
  metapkgs=(./sdata/dist-arch/illogical-impulse-{audio,backlight,basic,fonts-themes,kde,portal,python,screencapture,toolkit,widgets})
  metapkgs+=(./sdata/dist-arch/illogical-impulse-hyprland)
  metapkgs+=(./sdata/dist-arch/illogical-impulse-microtex-git)
  metapkgs+=(./sdata/dist-arch/illogical-impulse-quickshell-git)
  metapkgs+=(./sdata/dist-arch/illogical-impulse-bibata-modern-classic-bin)
  if [[ "${INSTALL_CAELESTIA_HYBRID:-true}" == "true" ]]; then
    metapkgs+=(./sdata/dist-arch/illogical-impulse-caelestia-plugin)
  fi
fi

for i in "${metapkgs[@]}"; do
  if [[ "${INSTALL_CAELESTIA_HYBRID:-true}" != "true" ]] && [[ "$i" == *"caelestia-plugin"* ]]; then
    continue
  fi
  metainstallflags="--needed"
  $ask && showfun install-local-pkgbuild || metainstallflags="$metainstallflags --noconfirm"
  v install-local-pkgbuild "$i" "$metainstallflags"
done

if [[ ${#ARCH_EXTRA_PKGS[@]} -gt 0 ]]; then
  printf "${STY_CYAN}[$0]: Installing profile extra packages (${INSTALL_PROFILE}): ${ARCH_EXTRA_PKGS[*]}${STY_RST}\n"
  if $ask; then
    v sudo pacman -S --needed "${ARCH_EXTRA_PKGS[@]}"
  else
    v sudo pacman -S --needed --noconfirm "${ARCH_EXTRA_PKGS[@]}"
  fi
fi

install-dinit-service-packages(){
  local -a pkgs=()
  local pkg

  if ! command -v dinitctl >/dev/null 2>&1; then
    return 0
  fi

  for pkg in userspawn-dinit bluez-dinit networkmanager-dinit pipewire-dinit pipewire-pulse-dinit wireplumber-dinit power-profiles-daemon-dinit; do
    if pacman -Si "$pkg" >/dev/null 2>&1; then
      pkgs+=("$pkg")
    fi
  done

  if (( ${#pkgs[@]} > 0 )); then
    printf "${STY_YELLOW}[$0]: Detected dinit init system, installing service packages: ${pkgs[*]}${STY_RST}\n"
    if $ask; then
      x sudo pacman -S --needed "${pkgs[@]}"
    else
      x sudo pacman -S --needed --noconfirm "${pkgs[@]}"
    fi
  fi
}
showfun install-dinit-service-packages
v install-dinit-service-packages

## Optional dependencies
if pacman -Qs ^plasma-browser-integration$ ;then SKIP_PLASMAINTG=true;fi
case $SKIP_PLASMAINTG in
  true) true;;
  *)
    if $ask;then
      echo -e "${STY_YELLOW}[$0]: NOTE: The size of \"plasma-browser-integration\" is ~600 KiB, but if you don't yet have KDE on your system it'll pull an extra ~600MiB of packages.${STY_RST}"
      echo -e "${STY_YELLOW}It is needed if you want playtime of media in Firefox to be shown on the music controls widget.${STY_RST}"
      echo -e "${STY_YELLOW}Install it? [y/N]${STY_RST}"
      read -p "====> " p
    else
      p=y
    fi
    case $p in
      y) x sudo pacman -S --needed --noconfirm plasma-browser-integration ;;
      *) echo "Ok, won't install"
    esac
    ;;
esac
