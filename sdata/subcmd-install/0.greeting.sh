# This script is meant to be sourced.
# It's not for directly running.

# shellcheck shell=bash

#####################################################################################

printf "${STY_CYAN}[$0]: Hi there! Before we start:${STY_RST}\n"
printf "\n"
printf "${STY_PURPLE}${STY_BOLD}[NEW] illogical-impulse is now powered by Quickshell.${STY_RST}\n"
printf "${STY_PURPLE}"
printf '# NOTE: illogical-impulse on AGS is no longer supported.\n'
printf '# If you were using the old version with AGS and would like to keep it, do not run this script.\n'
printf "\n"
pause
printf "${STY_CYAN}${STY_BOLD}Quick overview about what this script does:${STY_RST}\n"
printf "${STY_CYAN}"
printf "  1. Install dependencies.\n"
printf "  2. Setup permissions/services etc.\n"
printf "  3. Copying config files.${STY_RST}\n"
pause
printf "${STY_CYAN}${STY_BOLD}Tips:${STY_RST}\n"
printf "${STY_CYAN}"
printf "  a) It has been designed to be idempotent which means you can run it multiple times.\n"
printf "  b) Use ${STY_INVERT} --help ${STY_RST}${STY_CYAN} for more options.${STY_RST}\n"
printf "${STY_YELLOW}${STY_BOLD}Note: ${STY_RST}"
printf "${STY_YELLOW}"
printf "It does not handle system-level/hardware stuff like Nvidia drivers. Please do it by yourself.\n"
printf "${STY_RST}"
printf "\n"
pause

case $ask in
  false) true ;;
  *) 
    if [[ "${INSTALL_PROFILE_EXPLICIT:-false}" != "true" ]]; then
      printf "${STY_CYAN}${STY_BOLD}Select installation profile:${STY_RST}\n"
      printf "${STY_CYAN}"
      printf "  1) minimal  = Hyprland + end-4 (illogical-impulse)\n"
      printf "  2) hybrid   = Hyprland + end-4 + Caelestia Hybrid (DEFAULT)\n"
      printf "  3) complete = Hybrid + optional desktop apps & full customizations\n"
      printf "${STY_RST}"
      read -p "===> [1/2/3 (default: 2)]: " prof_choice
      case "$prof_choice" in
        1|minimal) INSTALL_PROFILE="minimal" ;;
        3|complete) INSTALL_PROFILE="complete" ;;
        *) INSTALL_PROFILE="hybrid" ;;
      esac
    fi
    printf "${STY_BLUE}"
    printf "${STY_BOLD}Do you want to confirm every time before a command executes?${STY_RST}\n"
    printf "${STY_BLUE}"
    printf "  y = Yes, ask me before executing each of them. (DEFAULT)\n"
    printf "  n = No, I know everything this script will do, just execute them automatically.\n"
    printf "  a = Abort.\n"
    read -p "===> [Y/n/a]: " p
    case $p in
      n) ask=false ;;
      a) exit 1 ;;
      *) ask=true ;;
    esac
    printf "${STY_RST}"
    ;;
esac
