# This script is meant to be sourced.
# It's not for directly running.
printf "${STY_CYAN}[$0]: 3. Copying config files\n${STY_RST}"

# shellcheck shell=bash

function warning_overwrite(){
  printf "${STY_YELLOW}"
  printf "The command below overwrites the destination.\n"
  printf "${STY_RST}"
}
function auto_backup_configs(){
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    echo -e "${STY_YELLOW}[DRY-RUN] Would check/backup clashing configs to \"${BACKUP_DIR}\"${STY_RST}"
    return 0
  fi
  local backup=false
  local effective_backup_dir="$BACKUP_DIR"
  case $ask in
    false)
      local backup=true
      ;;
    *)
      printf "${STY_RED}"
      printf "Would you like to backup clashing dirs/files to \"$BACKUP_DIR\"?\n"
      printf "${STY_RST}"
      while true;do
        echo "  y = Yes, backup"
        echo "  n/s = No, skip to next"
        local p; read -p "====> " p
        case $p in
          [yY]) echo -e "${STY_BLUE}OK, doing backup...${STY_RST}"
            local backup=true;break ;;
          [nNsS]) echo -e "${STY_BLUE}Alright, skipping...${STY_RST}"
            local backup=false;break ;;
          *) echo -e "${STY_RED}Please enter [y/n/s].${STY_RST}";;
        esac
      done
      ;;
  esac
  if $backup;then
    if [[ -e "$effective_backup_dir" || -L "$effective_backup_dir" ]]; then
      local base_backup="${BACKUP_DIR}-$(date +%Y%m%d-%H%M%S)"
      effective_backup_dir="$base_backup"
      local count=1
      while [[ -e "$effective_backup_dir" || -L "$effective_backup_dir" ]]; do
        effective_backup_dir="${base_backup}-${count}"
        (( count++ ))
      done
    fi
    mkdir -p "$effective_backup_dir"
    export ACTIVE_BACKUP_DIR="$effective_backup_dir"
    mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/illogical-impulse" 2>/dev/null || true
    printf '%s\n' "$effective_backup_dir" > "${XDG_STATE_HOME:-$HOME/.local/state}/illogical-impulse/latest_backup_dir" 2>/dev/null || true
    log_event "Backup directory initialized: ${effective_backup_dir}"
    backup_clashing_targets dots/.config $XDG_CONFIG_HOME "${effective_backup_dir}/.config"
    backup_clashing_targets dots/.local/share $XDG_DATA_HOME "${effective_backup_dir}/.local/share"
    backup_clashing_targets dots/.local/bin $XDG_BIN_HOME "${effective_backup_dir}/.local/bin"
    printf "${STY_BLUE}Backup into \"${effective_backup_dir}\" finished.${STY_RST}\n"
  fi
}
function gen_firstrun(){
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    echo -e "${STY_YELLOW}[DRY-RUN] Would generate firstrun marker: ${FIRSTRUN_FILE}${STY_RST}"
    return 0
  fi
  x mkdir -p "$(dirname "${FIRSTRUN_FILE}")"
  x touch "${FIRSTRUN_FILE}"
  x mkdir -p "$(dirname "${INSTALLED_LISTFILE}")"
  realpath -se "${FIRSTRUN_FILE}" >> "${INSTALLED_LISTFILE}"
}
_run_rsync_and_record(){
  local dest="$1"
  shift
  local tmp_out
  tmp_out="$(mktemp)"
  if ! rsync --out-format='%i %n' "$@" > "$tmp_out"; then
    rm -f "$tmp_out"
    return 1
  fi
  touch "${INSTALLED_LISTFILE}"
  awk -v d="$dest" '$1 ~ /^>/{ sub(/^[^ ]+ /,""); printf d "/" $0 "\n" }' "$tmp_out" >> "${INSTALLED_LISTFILE}"
  rm -f "$tmp_out"
  return 0
}
cp_file(){
  # NOTE: This function is only for using in other functions
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    echo -e "${STY_YELLOW}[DRY-RUN] cp_file: $1 -> $2${STY_RST}"
    return 0
  fi
  x mkdir -p "$(dirname "$2")"
  x cp -pf "$1" "$2"
  x mkdir -p "$(dirname "${INSTALLED_LISTFILE}")"
  realpath -se "$2" >> "${INSTALLED_LISTFILE}"
}
rsync_dir(){
  # NOTE: This function is only for using in other functions
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    echo -e "${STY_YELLOW}[DRY-RUN] rsync_dir: $1/ -> $2/${STY_RST}"
    return 0
  fi
  x mkdir -p "$2"
  local dest="$(realpath -se "$2")"
  x mkdir -p "$(dirname "${INSTALLED_LISTFILE}")"
  x _run_rsync_and_record "$dest" -a "$1"/ "$2"/
}
rsync_dir__ignore_existing(){
  # NOTE: This function is only for using in other functions
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    echo -e "${STY_YELLOW}[DRY-RUN] rsync_dir__ignore_existing: $1/ -> $2/${STY_RST}"
    return 0
  fi
  x mkdir -p "$2"
  local dest="$(realpath -se "$2")"
  x mkdir -p "$(dirname "${INSTALLED_LISTFILE}")"
  x _run_rsync_and_record "$dest" -a --ignore-existing "$1"/ "$2"/
}
rsync_dir__sync(){
  # NOTE: This function is only for using in other functions
  # `--delete' for rsync to make sure that
  # original dotfiles and new ones in the SAME DIRECTORY
  # (eg. in ~/.config/hypr/hyprland) won't be mixed together
  local src="$1"
  local dest_dir="$2"
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    echo -e "${STY_YELLOW}[DRY-RUN] rsync_dir__sync: $src/ -> $dest_dir/${STY_RST}"
    return 0
  fi
  x mkdir -p "$dest_dir"
  local dest="$(realpath -se "$dest_dir")"
  x mkdir -p "$(dirname "${INSTALLED_LISTFILE}")"

  local backup_dest_root="${ACTIVE_BACKUP_DIR:-${BACKUP_DIR}}"
  if [[ ! -d "$backup_dest_root" ]]; then
    local base_sync_backup="${BACKUP_DIR}-sync-backup-$(date +%Y%m%d-%H%M%S)"
    backup_dest_root="$base_sync_backup"
    local count=1
    while [[ -e "$backup_dest_root" || -L "$backup_dest_root" ]]; do
      backup_dest_root="${base_sync_backup}-${count}"
      (( count++ ))
    done
    mkdir -p "$backup_dest_root"
  fi
  local component_name="$(basename "$dest_dir")"
  local sync_backup_dir="${backup_dest_root}/sync-deleted/${component_name}"
  mkdir -p "$sync_backup_dir"

  x _run_rsync_and_record "$dest" -a --delete --backup --backup-dir="$sync_backup_dir" "$src"/ "$dest_dir"/

  if [[ -d "$sync_backup_dir" && -n "$(ls -A "$sync_backup_dir" 2>/dev/null)" ]]; then
    echo -e "${STY_YELLOW}[$0]: NOTICE: Unmanaged/modified files in '$dest_dir' were safely backed up to '${sync_backup_dir}' before synchronization.${STY_RST}"
    log_event "Sync backup saved: component=${component_name} dir=${sync_backup_dir}"
  else
    rmdir "$sync_backup_dir" 2>/dev/null || true
  fi
}
rsync_dir__sync_exclude(){
  # NOTE: This function is only for using in other functions
  # Same as rsync_dir__sync but with exclude patterns support
  # Usage: rsync_dir__sync_exclude <src> <dest> <exclude_pattern1> [<exclude_pattern2> ...]
  local src="$1"
  local dest_dir="$2"
  shift 2
  local excludes=()
  for pattern in "$@"; do
    excludes+=(--exclude "$pattern")
  done
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    echo -e "${STY_YELLOW}[DRY-RUN] rsync_dir__sync_exclude (${excludes[*]}): $src/ -> $dest_dir/${STY_RST}"
    return 0
  fi
  x mkdir -p "$dest_dir"
  local dest="$(realpath -se "$dest_dir")"
  x mkdir -p "$(dirname "${INSTALLED_LISTFILE}")"

  local backup_dest_root="${ACTIVE_BACKUP_DIR:-${BACKUP_DIR}}"
  if [[ ! -d "$backup_dest_root" ]]; then
    local base_sync_backup="${BACKUP_DIR}-sync-backup-$(date +%Y%m%d-%H%M%S)"
    backup_dest_root="$base_sync_backup"
    local count=1
    while [[ -e "$backup_dest_root" || -L "$backup_dest_root" ]]; do
      backup_dest_root="${base_sync_backup}-${count}"
      (( count++ ))
    done
    mkdir -p "$backup_dest_root"
  fi
  local component_name="$(basename "$dest_dir")"
  local sync_backup_dir="${backup_dest_root}/sync-deleted/${component_name}"
  mkdir -p "$sync_backup_dir"

  x _run_rsync_and_record "$dest" -a --delete --backup --backup-dir="$sync_backup_dir" "${excludes[@]}" "$src"/ "$dest_dir"/

  if [[ -d "$sync_backup_dir" && -n "$(ls -A "$sync_backup_dir" 2>/dev/null)" ]]; then
    echo -e "${STY_YELLOW}[$0]: NOTICE: Unmanaged/modified files in '$dest_dir' were backed up to '${sync_backup_dir}' before synchronization.${STY_RST}"
    log_event "Sync backup saved: component=${component_name} dir=${sync_backup_dir}"
  else
    rmdir "$sync_backup_dir" 2>/dev/null || true
  fi
}
function install_file(){
  # NOTE: Do not add prefix `v` or `x` when using this function
  local s=$1
  local t=$2
  if [ -f $t ];then
    warning_overwrite
  fi
  v cp_file $s $t
}
function install_file__auto_backup(){
  # NOTE: Do not add prefix `v` or `x` when using this function
  local s=$1
  local t=$2
  if [ -f $t ];then
    echo -e "${STY_YELLOW}[$0]: \"$t\" already exists.${STY_RST}"
    if ${INSTALL_FIRSTRUN};then
      echo -e "${STY_BLUE}[$0]: It seems to be the firstrun.${STY_RST}"
      v mv $t $t.old
      v cp_file $s $t
    else
      echo -e "${STY_BLUE}[$0]: It seems not a firstrun.${STY_RST}"
      v cp_file $s $t.new
    fi
  else
    echo -e "${STY_GREEN}[$0]: \"$t\" does not exist yet.${STY_RST}"
    v cp_file $s $t
  fi
}
function install_dir(){
  # NOTE: Do not add prefix `v` or `x` when using this function
  local s=$1
  local t=$2
  if [ -d $t ];then
    warning_overwrite
  fi
  v rsync_dir $s $t
}
function install_dir__sync(){
  # NOTE: Do not add prefix `v` or `x` when using this function
  local s=$1
  local t=$2
  if [ -d $t ];then
    warning_overwrite
  fi
  v rsync_dir__sync $s $t
}
function install_dir__skip_ifexist(){
  # NOTE: Do not add prefix `v` or `x` when using this function
  local s=$1
  local t=$2
  if [ -d $t ];then
    echo -e "${STY_BLUE}[$0]: \"$t\" already exists, will not do anything.${STY_RST}"
  else
    echo -e "${STY_YELLOW}[$0]: \"$t\" does not exist yet.${STY_RST}"
    v rsync_dir $s $t
  fi
}
function install_dir__ignore_existing(){
  # NOTE: Do not add prefix `v` or `x` when using this function
  local s=$1
  local t=$2
  v rsync_dir__ignore_existing $s $t
}
function install_dir__sync_exclude(){
  # NOTE: Do not add prefix `v` or `x` when using this function
  # Sync directory with exclude patterns
  # Usage: install_dir__sync_exclude <src> <dest> <exclude_pattern1> [<exclude_pattern2> ...]
  local s=$1
  local t=$2
  shift 2
  if [ -d $t ];then
    warning_overwrite
  fi
  v rsync_dir__sync_exclude $s $t "$@"
}
function install_google_sans_flex(){
  local font_name="Google Sans Flex"
  local src_name="google-sans-flex"
  local src_url="https://github.com/end-4/google-sans-flex"
  local src_dir="$REPO_ROOT/cache/$src_name"
  local target_dir="${XDG_DATA_HOME}/fonts/illogical-impulse-$src_name"
  if fc-list | grep -qi "$font_name"; then return; fi
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    echo -e "${STY_YELLOW}[DRY-RUN] Would clone and install font ${font_name} to ${target_dir}${STY_RST}"
    return 0
  fi
  x mkdir -p $src_dir
  x cd $src_dir
  try git init -b main
  try git remote add origin $src_url
  x git pull origin main 
  x git submodule update --init --recursive
  warning_overwrite
  rsync_dir "$src_dir" "$target_dir" 
  x fc-cache -fv
  x cd $REPO_ROOT
  x mkdir -p "$(dirname ${INSTALLED_LISTFILE})"
  realpath -se "$target_dir" >> "${INSTALLED_LISTFILE}"
}

#####################################################################################
# In case some dirs does not exists
for i in "$XDG_BIN_HOME" "$XDG_CACHE_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"; do
  if ! test -e "$i"; then
    v mkdir -p "$i"
  fi
done
case "${INSTALL_FIRSTRUN}" in
  # When specify --firstrun
  true) sleep 0 ;;
  # When not specify --firstrun
  *)
    if test -f "${FIRSTRUN_FILE}"; then
      INSTALL_FIRSTRUN=false
    else
      INSTALL_FIRSTRUN=true
    fi
    ;;
esac


showfun auto_update_git_submodule
v auto_update_git_submodule

# Backup
if [[ ! "${SKIP_BACKUP}" == true ]]; then auto_backup_configs; fi

case "${EXPERIMENTAL_FILES_SCRIPT}" in
  true)source sdata/subcmd-install/3.files-exp.sh;;
  *)source sdata/subcmd-install/3.files-legacy.sh;;
esac

if [[ ! "$OS_GROUP_ID" == "fedora" ]] && [[ "${SKIP_FONTCONFIG:-false}" != "true" ]]; then
  showfun install_google_sans_flex
  v install_google_sans_flex
fi

#####################################################################################

if [[ "${DRY_RUN:-false}" != "true" ]]; then
  mkdir -p "${XDG_STATE_HOME}/quickshell/ui-switch"
  if [[ "${INSTALL_CAELESTIA_HYBRID:-true}" != "true" ]] || [[ ! -f "${XDG_STATE_HOME}/quickshell/ui-switch/current" ]]; then
    printf 'end4\n' > "${XDG_STATE_HOME}/quickshell/ui-switch/current"
  fi
fi

v gen_firstrun
v dedup_and_sort_listfile "${INSTALLED_LISTFILE}" "${INSTALLED_LISTFILE}"

# Prevent hyprland from not fully loaded
if [[ "${DRY_RUN:-false}" != "true" ]]; then
  sleep 1
fi
try hyprctl reload

#####################################################################################
printf "\n"
printf "\n"
printf "\n"
printf "${STY_CYAN}[$0]: Finished${STY_RST}\n"
printf "\n"
printf "${STY_CYAN}When starting Hyprland from your display manager (login screen) ${STY_RED} DO NOT SELECT UWSM ${STY_RST}\n"
printf "\n"
printf "${STY_CYAN}If you are already running Hyprland,${STY_RST}\n"
printf "${STY_CYAN}Press ${STY_INVERT} Ctrl+Super+T ${STY_RST}${STY_CYAN} to select a wallpaper${STY_RST}\n"
printf "${STY_CYAN}Press ${STY_INVERT} Super+/ ${STY_RST}${STY_CYAN} for a list of keybinds${STY_RST}\n"
printf "\n"
printf "${STY_CYAN}For suggestions/hints after installation:${STY_RST}\n"
printf "${STY_CYAN}${STY_UNDERLINE} https://ii.clsty.link/en/ii-qs/01setup/#post-installation ${STY_RST}\n"
printf "\n"

if [[ -z "${ILLOGICAL_IMPULSE_VIRTUAL_ENV}" ]]; then
  printf "\n${STY_RED}[$0]: \!! Important \!! : Please ensure environment variable ${STY_RST} \$ILLOGICAL_IMPULSE_VIRTUAL_ENV ${STY_RED} is set to proper value (by default \"~/.local/state/quickshell/.venv\"), or Quickshell config will not work. We have already provided this configuration in ~/.config/hypr/hyprland/env.conf, but you need to ensure it is included in hyprland.conf, and also a restart is needed for applying it.${STY_RST}\n"
fi
