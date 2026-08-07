#!/usr/bin/env bash
# CS lab: proxy probe + NTP + Cisco repo reachability (no install).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${ROOT}/scripts/lib.sh"
load_lab_proxy
load_rc_env "${ROOT}/rc.env"
cs_lab_prepare_host
log "PASS: CS lab host ready (NTP + proxy + Cisco repo)"
