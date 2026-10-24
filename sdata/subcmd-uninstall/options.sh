# Handle args for subcmd: uninstall
# shellcheck shell=bash

showhelp(){
echo -e "Syntax: $0 uninstall [OPTIONS]...

Unintall dots.

Options:
  -h, --help       Show this help message
  -f, --force      Force non-interactive mode
  -n, --dry-run    Show what would be done without making changes
"
}
# `man getopt` to see more
para=$(getopt \
  -o hfn \
  -l help,force,dry-run \
  -n "$0" -- "$@")
[ $? != 0 ] && echo "$0: Error when getopt, please recheck parameters." && exit 1
#####################################################################################
## getopt Phase 1
# ignore parameter's order, execute options below first
eval set -- "$para"
while true ; do
  case "$1" in
    -h|--help) showhelp;exit;;
    -f|--force) ask=false;shift;;
    -n|--dry-run) DRY_RUN=true;shift;;
    --) break ;;
    *) shift ;;
  esac
done
