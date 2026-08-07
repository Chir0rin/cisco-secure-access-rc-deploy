#!/usr/bin/env bash
# CS lab: ./check.sh — A/B preflight only (no install). Same as deploy.sh start.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
source "${ROOT}/scripts/lib.sh"
load_lab_proxy
load_rc_env "${ROOT}/rc.env"
apply_cs_lab_proxy
fix_lab_proxy_config
preflight_sudo_curl_cisco_repo
log "PASS: Cisco repo reachable"
