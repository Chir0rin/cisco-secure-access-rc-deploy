#!/usr/bin/env bash
# Deploy Cisco Secure Access Resource Connector on Ubuntu (Docker).
# Interactive: connector name + provisioning key only.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# VM console cannot paste keys — rc.env comes from git. Reset local rc.env edits and pull.
if [[ -d "${ROOT}/.git" && "${RC_DEPLOY_NO_SYNC:-}" != "1" ]]; then
  (
    cd "${ROOT}"
    git checkout -- rc.env 2>/dev/null || true
    before="$(git rev-parse HEAD)"
    if git pull --ff-only >/dev/null 2>&1; then
      after="$(git rev-parse HEAD)"
      if [[ "${before}" != "${after}" ]]; then
        printf '[rc-deploy] Updated %s → %s; restarting deploy.sh\n' "${before:0:7}" "${after:0:7}" >&2
        export RC_DEPLOY_NO_SYNC=1
        exec bash "${ROOT}/deploy.sh" "$@"
      fi
    else
      printf '[rc-deploy] WARNING: git pull failed — fix with: git checkout rc.env && git pull\n' >&2
    fi
  )
fi

# shellcheck source=scripts/lib.sh
source "${ROOT}/scripts/lib.sh"

main() {
  log "Cisco Secure Access Resource Connector deploy"
  log "Repo: https://github.com/Chir0rin/cisco-secure-access-rc-deploy"
  if [[ -d "${ROOT}/.git" ]]; then
    log "Git: $(git -C "${ROOT}" rev-parse --short HEAD) ($(git -C "${ROOT}" log -1 --format='%s' 2>/dev/null || true))"
  fi

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
  ensure_connector_images
  launch_connector "${name}" "${key}"
  print_next_steps
}

main "$@"
