# This script is meant to be sourced.
# It's not for directly running.

# shellcheck shell=bash

if [[ "${DRY_RUN:-false}" == "true" ]]; then
  echo -e "${STY_YELLOW}[DRY-RUN] Would remove firstrun state file: ${FIRSTRUN_FILE}${STY_RST}"
else
  try rm "${FIRSTRUN_FILE}"
fi
