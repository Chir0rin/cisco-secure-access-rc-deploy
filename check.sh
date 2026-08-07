#!/usr/bin/env bash
# CS lab: proxy probe + NTP + Cisco repo reachability (no install).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -d "${ROOT}/.git" && "${RC_DEPLOY_NO_SYNC:-}" != "1" ]]; then
  (
    cd "${ROOT}"
    git checkout -- rc.env 2>/dev/null || true
    before="$(git rev-parse HEAD)"
    if git pull --ff-only >/dev/null 2>&1 && [[ "$(git rev-parse HEAD)" != "${before}" ]]; then
      export RC_DEPLOY_NO_SYNC=1
      exec bash "${ROOT}/check.sh" "$@"
    fi
  )
fi

# shellcheck source=scripts/lib.sh
source "${ROOT}/scripts/lib.sh"
load_lab_proxy
load_rc_env "${ROOT}/rc.env"
resolve_rc_name_from_hostname
cs_lab_prepare_host
check_package_manager
if [[ -d "${ROOT}/.git" ]]; then
  log "Git: $(git -C "${ROOT}" rev-parse --short HEAD)"
fi
log "PASS: CS lab host ready (NTP + proxy + Cisco repo + package manager)"
