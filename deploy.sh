#!/usr/bin/env bash
# Deploy Cisco Secure Access Resource Connector on Ubuntu (Docker).
# Interactive: connector name + provisioning key only.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${ROOT}/scripts/lib.sh"

main() {
  log "Cisco Secure Access Resource Connector deploy"
  log "Repo: https://github.com/Chir0rin/cisco-secure-access-rc-deploy"

  load_lab_proxy
  load_rc_env "${ROOT}/rc.env"
  resolve_rc_name_from_hostname
  preflight_no_existing_connector
  cs_lab_prepare_host

  if [[ -z "${RC_NAME:-}" || -z "${RC_PROVISIONING_KEY:-}" ]]; then
    print_deploy_inputs
  fi

  preflight_host

  local name key
  name="$(prompt_connector_name)"
  key="$(prompt_provisioning_key)"
  confirm_launch_inputs "${name}" "${key}"

  ensure_connector_installed
  ensure_connector_image
  launch_connector "${name}" "${key}"
  print_next_steps
}

main "$@"
