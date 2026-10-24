# This script is meant to be sourced.
# It's not for directly running.

# shellcheck shell=bash

#####################################################################################
# MISC (For dots/.config/* but not quickshell, not caelestia, not fish, not Hyprland, not fontconfig)
case "${SKIP_MISCCONF}" in
  true) true;;
  *)
    for i in $(find dots/.config/ -mindepth 1 -maxdepth 1 ! -name 'quickshell' ! -name 'caelestia' ! -name 'fish' ! -name 'hypr' ! -name 'fontconfig' -exec basename {} \;); do
#      i="dots/.config/$i"
      echo "[$0]: Found target: dots/.config/$i"
      if [ -d "dots/.config/$i" ];then install_dir__sync "dots/.config/$i" "$XDG_CONFIG_HOME/$i"
      elif [ -f "dots/.config/$i" ];then install_file "dots/.config/$i" "$XDG_CONFIG_HOME/$i"
      fi
    done
    install_dir "dots/.local/share/konsole" "${XDG_DATA_HOME}"/konsole
    ;;
esac

case "${SKIP_QUICKSHELL}" in
  true) true;;
  *)
    # Explicit per-component sync: never run destructive rsync --delete on the root ~/.config/quickshell
    install_dir__sync dots/.config/quickshell/ii "$XDG_CONFIG_HOME"/quickshell/ii
    install_file dots/.config/quickshell/ui-switch.sh "$XDG_CONFIG_HOME"/quickshell/ui-switch.sh
    install_file dots/.config/quickshell/ui-switch.sh "$XDG_BIN_HOME"/ui-switch.sh
    if [[ "${INSTALL_CAELESTIA_HYBRID:-true}" == "true" ]]; then
      install_dir__sync dots/.config/quickshell/caelestia-hybrid "$XDG_CONFIG_HOME"/quickshell/caelestia-hybrid
      # Preserve hardware-specific ~/.config/caelestia/monitors/* by only managing shell.json
      install_file__auto_backup dots/.config/caelestia/shell.json "$XDG_CONFIG_HOME"/caelestia/shell.json
    fi
    ;;
esac

case "${SKIP_FISH}" in
  true) true;;
  *)
    install_dir__sync_exclude dots/.config/fish "$XDG_CONFIG_HOME"/fish "conf.d"
    ;;
esac

case "${SKIP_FONTCONFIG}" in
  true) true;;
  *)
    case "$FONTSET_DIR_NAME" in
      "") install_dir__sync dots/.config/fontconfig "$XDG_CONFIG_HOME"/fontconfig ;;
      *) install_dir__sync dots-extra/fontsets/$FONTSET_DIR_NAME "$XDG_CONFIG_HOME"/fontconfig ;;
    esac;;
esac

# For Hyprland
case "${SKIP_HYPRLAND}" in
  true) true;;
  *)
    install_dir__sync dots/.config/hypr/hyprland "$XDG_CONFIG_HOME"/hypr/hyprland
    install_dir__sync dots/.config/hypr/hyprlock "$XDG_CONFIG_HOME"/hypr/hyprlock
    if [ -f "${XDG_CONFIG_HOME}/hypr/hyprland.conf" ]; then
      v mv "${XDG_CONFIG_HOME}/hypr/hyprland.conf" "${XDG_CONFIG_HOME}/hypr/hyprland.conf.old" # disable old config
      echo 'hyprland.conf has been renamed to hyprland.conf.old. This is to allow the new lua config to load.'
    fi
    for i in hyprlock.conf ; do
      install_file__auto_backup "dots/.config/hypr/$i" "${XDG_CONFIG_HOME}/hypr/$i"
    done
    for i in hyprland.lua ; do
      case "${SKIP_HYPRLAND_ENTRY}" in
        true) true;;
        *) install_file "dots/.config/hypr/$i" "${XDG_CONFIG_HOME}/hypr/$i" ;;
      esac
    done
    for i in hypridle.conf ; do
      if [[ "${INSTALL_VIA_NIX}" == true ]]; then
        install_file__auto_backup "dots-extra/via-nix/$i" "${XDG_CONFIG_HOME}/hypr/$i"
      else
        install_file__auto_backup "dots/.config/hypr/$i" "${XDG_CONFIG_HOME}/hypr/$i"
      fi
    done
    if [ "$OS_GROUP_ID" = "fedora" ];then
      v bash -c "printf \"# For fedora to setup polkit\nexec-once = /usr/libexec/kf6/polkit-kde-authentication-agent-1\n\" >> ${XDG_CONFIG_HOME}/hypr/hyprland/execs.conf"
    fi

    install_dir__ignore_existing "dots/.config/hypr/custom" "${XDG_CONFIG_HOME}/hypr/custom"
    ;;
esac

install_file "dots/.local/share/icons/illogical-impulse.svg" "${XDG_DATA_HOME}"/icons/illogical-impulse.svg
install_file "dots/.local/bin/rice-lock" "${XDG_BIN_HOME}"/rice-lock
