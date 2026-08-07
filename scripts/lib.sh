#!/usr/bin/env bash
# Shared helpers for cisco-secure-access-rc-deploy

set -euo pipefail

RC_CONNECTOR_SH="/opt/connector/install/connector.sh"
RC_SETUP_URL_DEFAULT="https://us.repo.acgw.sse.cisco.com/scripts/latest/setup_connector.sh"

# stderr, so log lines never leak into command substitutions (e.g. captured keys)
log() {
  printf '[rc-deploy] %s\n' "$*" >&2
}

die() {
  printf '[rc-deploy] ERROR: %s\n' "$*" >&2
  exit 1
}

require_root_or_sudo() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    SUDO=""
    return
  fi
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
    return
  fi
  die "Run as root or install sudo."
}

run_as_root() {
  require_root_or_sudo
  if [[ -n "${SUDO}" ]]; then
    # Preserve http_proxy/https_proxy for setup_connector.sh (apt, curl inside).
    "${SUDO}" -E "$@"
  else
    "$@"
  fi
}

# CS lab / corporate: load /etc/profile.d/proxy.sh if env not already set.
load_lab_proxy() {
  local proxy_file="/etc/profile.d/proxy.sh"
  [[ -f "${proxy_file}" ]] || return 0
  if [[ -z "${http_proxy:-}" && -z "${HTTP_PROXY:-}" ]]; then
    # shellcheck source=/dev/null
    source "${proxy_file}"
    log "Loaded proxy from ${proxy_file}"
  fi
  if [[ "${no_proxy:-}${NO_PROXY:-}" == *cisco.com* ]]; then
    log "WARNING: no_proxy includes .cisco.com — RC setup may fail. Remove it from ${proxy_file}"
  fi
}

validate_connector_name() {
  local name="$1"
  if [[ ! "${name}" =~ ^[A-Za-z0-9_-]{1,40}$ ]]; then
    die "Invalid connector name '${name}'. Use 1-40 chars: letters, digits, hyphen, underscore."
  fi
}

trim_whitespace() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

validate_provisioning_key() {
  local key
  key="$(trim_whitespace "$1")"
  if [[ -z "${key}" ]]; then
    die "Provisioning key is empty."
  fi
  if [[ "${#key}" -lt 20 ]]; then
    die "Provisioning key looks too short. Copy it from View Provisioning Key in the dashboard."
  fi
  printf '%s' "${key}"
}

mask_provisioning_key() {
  local key="$1"
  local len=${#key}
  local edge=6

  if (( len == 0 )); then
    printf '(empty)'
    return
  fi
  if (( len <= edge * 2 )); then
    printf 'start=%s end=%s (len=%d)' "${key:0:edge}" "${key: -edge}" "${len}"
    return
  fi
  printf 'start=%s … end=%s (len=%d)' "${key:0:edge}" "${key: -edge}" "${len}"
}

print_key_preview() {
  log "Provisioning key captured: $(mask_provisioning_key "$1")"
}

# Load RC_NAME / RC_PROVISIONING_KEY from an optional rc.env file.
# Values already set in the environment win; placeholder values are ignored.
load_rc_env() {
  local file="$1"
  [[ -f "${file}" ]] || return 0

  local env_name="${RC_NAME:-}" env_key="${RC_PROVISIONING_KEY:-}" env_yes="${RC_YES:-}"
  # shellcheck source=/dev/null
  source "${file}"
  [[ -n "${env_name}" ]] && RC_NAME="${env_name}"
  [[ -n "${env_key}" ]] && RC_PROVISIONING_KEY="${env_key}"
  [[ -n "${env_yes}" ]] && RC_YES="${env_yes}"

  case "${RC_PROVISIONING_KEY:-}" in
    '' | *REPLACE_ME* | *PASTE_* ) RC_PROVISIONING_KEY="" ;;
  esac
  case "${RC_NAME:-}" in
    '' | *REPLACE_ME* ) RC_NAME="" ;;
  esac

  if [[ -n "${RC_NAME:-}" || -n "${RC_PROVISIONING_KEY:-}" ]]; then
    log "Loaded deploy inputs from ${file}"
  fi
}

confirm_launch_inputs() {
  local name="$1"
  local key="$2"

  cat <<EOF

Review before launch:
  Connector name   : ${name}
  Provisioning key : $(mask_provisioning_key "${key}")

  Compare start/end with the dashboard key before continuing.
EOF
  if [[ "${RC_YES:-}" == "1" ]]; then
    log "RC_YES=1 set; skipping confirmation."
    return 0
  fi
  local answer
  read -r -p "Proceed with launch? [y/N]: " answer
  case "${answer}" in
    [yY] | [yY][eE][sS]) return 0 ;;
    *) die "Aborted." ;;
  esac
}

print_deploy_inputs() {
  cat <<'EOF'

This script needs two values (prepare the key in Secure Access first):

  1. Connector name     — your label for this host (e.g. rc-01)
  2. Provisioning key   — connector group → View Provisioning Key

EOF
}

prompt_connector_name() {
  if [[ -n "${RC_NAME:-}" ]]; then
    validate_connector_name "${RC_NAME}"
    printf '%s' "${RC_NAME}"
    return
  fi
  local name
  while true; do
    read -r -p "Connector name (1-40 chars, e.g. rc-01): " name
    if [[ "${name}" =~ ^[A-Za-z0-9_-]{1,40}$ ]]; then
      printf '%s' "${name}"
      return
    fi
    printf 'Invalid name. Use 1-40 characters: letters, digits, hyphen, underscore.\n' >&2
  done
}

prompt_provisioning_key() {
  local key
  if [[ -n "${RC_PROVISIONING_KEY:-}" ]]; then
    key="$(validate_provisioning_key "${RC_PROVISIONING_KEY}")"
    print_key_preview "${key}"
    printf '%s' "${key}"
    return
  fi
  read -r -s -p "Provisioning key (from connector group → View Provisioning Key): " key
  echo >&2
  key="$(validate_provisioning_key "${key}")"
  print_key_preview "${key}"
  printf '%s' "${key}"
}

preflight_host() {
  log "Running preflight checks..."

  if [[ -f /etc/os-release ]]; then
    # shellcheck source=/dev/null
    source /etc/os-release
    if [[ "${ID:-}" != "ubuntu" ]]; then
      log "WARNING: Expected Ubuntu; detected ID=${ID:-unknown}."
    fi
    if [[ "${VERSION_ID:-}" != "22.04" ]]; then
      log "WARNING: Cisco documents Ubuntu 22.04 LTS; this host is ${VERSION_ID:-unknown}."
    fi
  fi

  if command -v snap >/dev/null 2>&1 && snap list docker 2>/dev/null | grep -q docker; then
    log "WARNING: Snap Docker detected. Remove it before continuing (Cisco recommends apt-based Docker via setup_connector.sh)."
  fi

  if command -v dpkg >/dev/null 2>&1; then
    local broken
    broken="$(dpkg -l 2>/dev/null | awk '/^..r/{print $2}' | head -5 || true)"
    if [[ -n "${broken}" ]]; then
      log "WARNING: dpkg reports packages needing configuration. Run: sudo dpkg --configure -a"
    fi
  fi

  if [[ ! -x "${RC_CONNECTOR_SH}" ]]; then
    if ! command -v curl >/dev/null 2>&1; then
      log "Installing curl..."
      run_as_root apt-get update -qq
      run_as_root apt-get install -y -qq curl ca-certificates
    fi
  fi
}

download_setup_script() {
  local dest="$1"
  local url="${RC_SETUP_URL:-${RC_SETUP_URL_DEFAULT}}"
  local proxy="${https_proxy:-${HTTPS_PROXY:-${http_proxy:-${HTTP_PROXY:-}}}}"
  log "Downloading setup_connector.sh from ${url}"
  if [[ -n "${proxy}" ]]; then
    log "Using proxy ${proxy}"
    # no_proxy often lists .cisco.com; that bypasses proxy for us.repo.acgw.sse.cisco.com
    # and times out on CS lab segments. Force proxy for this download only.
    env -u no_proxy -u NO_PROXY curl -fsSL --connect-timeout 30 --max-time 600 \
      -x "${proxy}" -o "${dest}" "${url}"
  else
    curl -fsSL --connect-timeout 30 --max-time 600 -o "${dest}" "${url}"
  fi
  chmod +x "${dest}"
}

ensure_connector_installed() {
  if [[ -x "${RC_CONNECTOR_SH}" ]]; then
    log "Connector install already present at ${RC_CONNECTOR_SH}; skipping setup_connector.sh"
    return 0
  fi

  local workdir
  workdir="$(mktemp -d)"
  trap 'rm -rf "${workdir}"' RETURN

  local setup="${workdir}/setup_connector.sh"
  download_setup_script "${setup}"

  log "Running Cisco setup_connector.sh (installs Docker + /opt/connector)..."
  local proxy="${https_proxy:-${HTTPS_PROXY:-${http_proxy:-${HTTP_PROXY:-}}}}"
  if [[ -n "${proxy}" ]]; then
    # setup_connector.sh downloads from *.cisco.com; no_proxy must not bypass proxy on CS lab.
    run_as_root env -u no_proxy -u NO_PROXY \
      http_proxy="${proxy}" https_proxy="${proxy}" \
      HTTP_PROXY="${proxy}" HTTPS_PROXY="${proxy}" \
      bash "${setup}"
  else
    run_as_root bash "${setup}"
  fi

  trap - RETURN
  rm -rf "${workdir}"

  [[ -x "${RC_CONNECTOR_SH}" ]] || die "setup_connector.sh finished but ${RC_CONNECTOR_SH} is missing."
}

launch_connector() {
  local name="$1"
  local key="$2"
  log "Launching connector '${name}'..."
  run_as_root "${RC_CONNECTOR_SH}" launch --name "${name}" --key "${key}"
}

print_next_steps() {
  cat <<'EOF'

Deployment script finished.

Next steps in Cisco Secure Access:
  1. Connect → Network Connections → Connector Groups
  2. Open the connector group that matches your provisioning key
  3. Connectors tab → Confirm the new connector
  4. Enable the connector

Enrollment can take 30–90 seconds after connector_svc starts.
If Confirm stays empty, check host logs before retrying launch.

Verify on the host:
  sudo docker ps
  sudo systemctl status connector_svc --no-pager
  sudo tail -50 /opt/connector/data/logs/*.log 2>/dev/null

Docs: https://docs.sse.cisco.com/sse-user-guide/docs/deploy-a-resource-connector-in-docker

EOF
}
