# This script is meant to be sourced.
# It's not for directly running.
function print_os_group_id(){
    printf "${STY_CYAN}"
    printf "===INFO===\n"
    printf "Detected OS_DISTRO_ID: ${OS_DISTRO_ID}\n"
    printf "Detected OS_DISTRO_ID_LIKE: ${OS_DISTRO_ID_LIKE}\n"
    printf "Determined OS_GROUP_ID: ${OS_GROUP_ID}\n"
    printf "==========\n\n"
    printf "${STY_RST}"
}
function print_os_group_id_alike(){
    printf "${STY_YELLOW}"
    printf "===WARNING===\n"
    printf "Your OS_GROUP_ID has been determined by \"alike\" match.\n"
    printf "Ideally, it should also work for your distro.\n"
    printf "Still, there is a chance that it not works as expected or even fails.\n"
    printf "Proceed only at your own risk.\n"
    printf "=============\n\n"
    printf "${STY_RST}"
}
function print_os_group_id_unofficial(){
    printf "${STY_PURPLE}"
    printf "===NOTICE===\n"
    printf "The support for your distro is provided by the community.\n"
    printf "It is not officially supported by github:end-4/dots-hyprland .\n"
    printf "${STY_BOLD}"
    printf "If you find out any problems about it, PR is welcomed if you are able to address it.\n"
    printf "Or, create a discussion about it, but please do not submit issue, \n"
    printf "because the developers do not use this distro, therefore they cannot help.${STY_RST}\n"
    printf "${STY_PURPLE}"
    printf "Proceed only at your own risk.\n"
    printf "============\n\n"
    printf "${STY_RST}"
}
function print_os_group_id_unsupported(){
    printf "${STY_RED}"
    printf "===CAUTION===\n"
    printf "\"--via-nix\" is forcely specified \n"
    printf "as the only way to try to install on your distro.\n"
    printf "It is still experimental.\n"
    printf "Some functionalities are missing.\n"
    printf "It may also behave unexpectedly.\n"
    printf "Proceed only at your own risk.\n"
    printf "=============\n\n"
    printf "${STY_RST}"
    sleep 3
}
function print_os_group_id_fallback(){
    printf "${STY_RED}"
    printf "===CAUTION===\n"
    printf "Distro not recognized, determined as fallback.\n"
    printf "=============\n\n"
    printf "${STY_RST}"
}
function print_os_group_id_architecture(){
    printf "${STY_RED}"
    printf "===CAUTION===\n"
    printf "Detected machine architecture: ${MACHINE_ARCH}\n"
    printf "This script only supports x86_64.\n"
    printf "It is very likely to fail when installing dependencies on your machine.\n"
    printf "=============\n\n"
    printf "${STY_RST}"
}

# Hyprland Hybrid Rice: official support is Arch Linux only.
# The dist-fedora/dist-gentoo/dist-nix code paths below are kept as inherited from
# upstream end-4/dots-hyprland, but they know nothing about the Caelestia Hybrid
# frontend (no caelestia plugin / libcava / qt6-m3shapes dependencies) and have not
# been validated for this project. This function is a no-op on Arch Linux.
#
# Behavior (only when OS_GROUP_ID != arch, or --via-nix was requested):
#   - always prints a warning;
#   - for subcommands that install packages (install, install-deps), refuses to continue
#     without explicit consent: an interactive [y/N] prompt (default: No), or, in
#     non-interactive mode (-f/--force), HYBRID_ALLOW_UNSUPPORTED_DISTRO=true;
#   - --dry-run never aborts (it does not change the system).
function print_os_group_id_hybrid_unsupported(){
    if [[ "${OS_GROUP_ID}" == "arch" && "${INSTALL_VIA_NIX:-false}" != "true" ]]; then
        return 0
    fi
    printf "${STY_RED}${STY_BOLD}"
    printf "===UNSUPPORTED DISTRO / INSTALL PATH===\n"
    printf "${STY_RST}${STY_RED}"
    printf "Hyprland Hybrid Rice officially supports Arch Linux only.\n"
    printf "The installation path for your system (OS_GROUP_ID=${OS_GROUP_ID}%s) is inherited\n" "$([[ "${INSTALL_VIA_NIX:-false}" == "true" ]] && echo ", --via-nix")"
    printf "from upstream end-4/dots-hyprland and has NOT been validated with the Caelestia\n"
    printf "Hybrid integration (Caelestia plugin, libcava, qt6-m3shapes, ui-switch, color bridges).\n"
    printf "Packages may be missing, or the hybrid frontend may not work.\n"
    printf "The end-4 (ii) frontend alone (--profile minimal) is the closest to upstream behavior,\n"
    printf "but it is still not covered by this project's tests or support.\n"
    printf "=======================================\n\n"
    printf "${STY_RST}"

    # Subcommands that alter system packages, services, permissions or user configs require consent.
    case "${SUBCMD_NAME:-}" in
        install|install-deps|install-setups|install-files|exp-update|exp-merge|uninstall|resetfirstrun) ;;
        *) return 0;;
    esac
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        printf "${STY_YELLOW}[DRY-RUN] No changes will be made, continuing.${STY_RST}\n"
        return 0
    fi
    if [[ "${HYBRID_ALLOW_UNSUPPORTED_DISTRO:-false}" == "true" ]]; then
        printf "${STY_YELLOW}HYBRID_ALLOW_UNSUPPORTED_DISTRO=true: proceeding at your own risk.${STY_RST}\n"
        return 0
    fi
    if [[ "${ask:-true}" == "false" ]]; then
        printf "${STY_RED}Aborting before making any change (non-interactive mode).${STY_RST}\n"
        printf "To proceed anyway, at your own risk: HYBRID_ALLOW_UNSUPPORTED_DISTRO=true ./setup ${SUBCMD_NAME} ...\n"
        exit 1
    fi
    local p
    read -p "Proceed anyway, at your own risk? [y/N]: " p || p=""
    case "$p" in
        [yY]) true;;
        *) echo "Aborting..."; exit 1;;
    esac
}
#####################################################################################

####################
# Detect distro
# Helpful link(s):
# http://stackoverflow.com/questions/29581754
# https://github.com/which-distro/os-release
OS_RELEASE_FILE_CUSTOM="${OS_RELEASE_FILE:-${REPO_ROOT}/os-release}"
if test -f "${OS_RELEASE_FILE_CUSTOM}"; then
  printf "${STY_YELLOW}Warning: using custom os-release file \"${OS_RELEASE_FILE_CUSTOM}\".${STY_RST}\n"
  OS_RELEASE_FILE="${OS_RELEASE_FILE_CUSTOM}"
elif test -f /etc/os-release; then
  OS_RELEASE_FILE=/etc/os-release
else
  printf "${STY_RED}/etc/os-release does not exist, aborting...${STY_RST}\n" ; exit 1
fi
export OS_DISTRO_ID=$(awk -F'=' '/^ID=/ { gsub(/["\x27]/,"",$2); print tolower($2) }' ${OS_RELEASE_FILE} 2> /dev/null)
export OS_DISTRO_ID_LIKE=$(awk -F'=' '/^ID_LIKE=/ { gsub(/["\x27]/,"",$2); print tolower($2) }' ${OS_RELEASE_FILE} 2> /dev/null)


####################
# Determine distro ID

if [[ "$OS_DISTRO_ID" =~ ^(arch|endeavouros|cachyos)$ ]]; then
  OS_GROUP_ID="arch"
  print_os_group_id_functions=(print_os_group_id)
elif [[ "$OS_DISTRO_ID_LIKE" == "arch" ]]; then
  OS_GROUP_ID="arch"
  print_os_group_id_functions=(print_os_group_id{,_alike})
elif [[ "$OS_DISTRO_ID" == "gentoo" ]]; then
  OS_GROUP_ID="gentoo"
  print_os_group_id_functions=(print_os_group_id{,_unofficial})
elif [[ "$OS_DISTRO_ID_LIKE" == "gentoo" ]]; then
  OS_GROUP_ID="gentoo"
  print_os_group_id_functions=(print_os_group_id{,_alike,_unofficial})
elif [[ "$OS_DISTRO_ID" == "fedora" ]]; then
  OS_GROUP_ID="fedora"
  print_os_group_id_functions=(print_os_group_id{,_unofficial})
elif [[ "$OS_DISTRO_ID_LIKE" == "fedora" ]]; then
  OS_GROUP_ID="fedora"
  print_os_group_id_functions=(print_os_group_id{,_alike,_unofficial})
elif [[ "$OS_DISTRO_ID" =~ ^(opensuse-leap|opensuse-tumbleweed)$ ]] || [[ "$OS_DISTRO_ID_LIKE" =~ ^(opensuse|suse)(\ (opensuse|suse))?$ ]]; then
  OS_GROUP_ID="suse"
  INSTALL_VIA_NIX=true
  print_os_group_id_functions=(print_os_group_id{,_unsupported})
elif [[ "$OS_DISTRO_ID" == "debian" || "$OS_DISTRO_ID_LIKE" == "debian" ]]; then
  OS_GROUP_ID="debian"
  INSTALL_VIA_NIX=true
  print_os_group_id_functions=(print_os_group_id{,_unsupported})
else
  OS_GROUP_ID="fallback"
  INSTALL_VIA_NIX=true
  print_os_group_id_functions=(print_os_group_id{,_fallback,_unsupported})
fi

####################
# Detect architecture
# Helpful link(s):
# http://stackoverflow.com/questions/45125516
export MACHINE_ARCH=$(uname -m)
case "${MACHINE_ARCH}" in
  "x86_64") true;;
  *) print_os_group_id_functions+=(print_os_group_id_architecture);;
esac

####################
# Hybrid Rice support notice/consent (no-op on Arch Linux without --via-nix).
# Kept last so it runs after the informational messages above.
print_os_group_id_functions+=(print_os_group_id_hybrid_unsupported)
