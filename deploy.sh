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

  if [[ -z "${RC_NAME:-}" || -z "${RC_PROVISIONING_KEY:-}" ]]; then
    print_deploy_inputs
  fi

  preflight_host

  local name key
  name="$(prompt_connector_name)"
  key="$(prompt_provisioning_key)"

  ensure_connector_installed
  launch_connector "${name}" "${key}"
  print_next_steps
}

main "$@"
