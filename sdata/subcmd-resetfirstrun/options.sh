# Handle args for subcmd: checkdeps
# shellcheck shell=bash

showhelp(){
echo -e "Syntax: $0 resetfirstrun [OPTIONS]

Reset firstrun state.

Options:
  -h, --help       Show this help message and exit
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
eval set -- "$para"
while true ; do
  case "$1" in
    -h|--help) showhelp;exit;;
    -f|--force) ask=false;shift;;
    -n|--dry-run) DRY_RUN=true;shift;;
    --) shift;break ;;
    *) echo -e "$0: Wrong parameters.";exit 1;;
  esac
done
