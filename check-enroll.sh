#!/usr/bin/env bash
# Probe SSE enrollment egress (host + RC container). Dashboard Confirm Connectors.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -d "${ROOT}/.git" && "${RC_DEPLOY_NO_SYNC:-}" != "1" ]]; then
  (
    cd "${ROOT}"
    git checkout -- rc.env 2>/dev/null || true
    before="$(git rev-parse HEAD)"
    if git pull --ff-only >/dev/null 2>&1 && [[ "$(git rev-parse HEAD)" != "${before}" ]]; then
      export RC_DEPLOY_NO_SYNC=1
      exec bash "${ROOT}/check-enroll.sh" "$@"
    fi
  )
fi

# shellcheck source=scripts/lib.sh
source "${ROOT}/scripts/lib.sh"
load_lab_proxy
load_rc_env "${ROOT}/rc.env"
resolve_rc_name_from_hostname

log "RC enrollment egress check (himorish-cslab-rcg / Confirm Connectors)"
check_rc_sse_egress
