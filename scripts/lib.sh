#!/usr/bin/env bash
# Shared helpers for cisco-secure-access-rc-deploy

set -euo pipefail

RC_CONNECTOR_SH="/opt/connector/install/connector.sh"
RC_SETUP_URL_DEFAULT="https://us.repo.acgw.sse.cisco.com/scripts/latest/setup_connector.sh"
# CS lab SharePoint: tyoidc5-dmz-wsa-* faster than proxy.esl for 192.168.2.x egress
CS_LAB_PROXY_DEFAULT="http://tyoidc5-dmz-wsa-1.cisco.com:80"
CS_LAB_NO_PROXY="localhost,127.0.0.1,192.168.2.0/24,10.70.91.0/24,.esl.cisco.com"
CS_LAB_PROXY_CANDIDATES=(
  "http://tyoidc5-dmz-wsa-1.cisco.com:80"
  "http://tyoidc5-dmz-wsa-2.cisco.com:80"
  "http://proxy.esl.cisco.com:80"
)

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
}

# Same curl path as patched setup_connector.sh (sudo curl -x proxy).
probe_cisco_repo_via_proxy() {
  local proxy="$1"
  local url="${RC_SETUP_URL:-${RC_SETUP_URL_DEFAULT}}"
  run_as_root env -u no_proxy -u NO_PROXY \
    http_proxy="${proxy}" https_proxy="${proxy}" \
    curl -x "${proxy}" -fsSL -o /dev/null -w '%{http_code}' \
    --connect-timeout 10 --max-time 45 "${url}" 2>/dev/null || echo 000
}

write_cs_lab_proxy_files() {
  local proxy="$1"
  run_as_root tee /etc/profile.d/proxy.sh >/dev/null <<EOF
export http_proxy="${proxy}"
export https_proxy="${proxy}"
export no_proxy="${CS_LAB_NO_PROXY}"
EOF
  run_as_root tee /etc/apt/apt.conf.d/95proxies >/dev/null <<EOF
Acquire::http::Proxy "${proxy}";
Acquire::https::Proxy "${proxy}";
EOF
  local curlrc_body
  curlrc_body="proxy = \"${proxy}\"
noproxy = \"${CS_LAB_NO_PROXY}\""
  run_as_root tee /etc/curlrc >/dev/null <<<"${curlrc_body}"
  run_as_root tee /root/.curlrc >/dev/null <<<"${curlrc_body}"
  if [[ -f /etc/environment ]] && grep -qE '^https?_proxy=' /etc/environment; then
    run_as_root sed -i "s|^http_proxy=.*|http_proxy=\"${proxy}\"|" /etc/environment
    run_as_root sed -i "s|^https_proxy=.*|https_proxy=\"${proxy}\"|" /etc/environment
    run_as_root sed -i -E 's/,\?\.cisco\.com//g' /etc/environment
    run_as_root sed -i -E 's|^no_proxy=.*|no_proxy=\"${CS_LAB_NO_PROXY}\"|' /etc/environment
  fi
  export http_proxy="${proxy}" https_proxy="${proxy}" no_proxy="${CS_LAB_NO_PROXY}"
  export RC_HTTP_PROXY="${proxy}"
}

# Probe SharePoint-listed proxies; write config only for the one that works.
select_and_apply_cs_lab_proxy() {
  local -a ordered=() seen="" proxy status
  local url="${RC_SETUP_URL:-${RC_SETUP_URL_DEFAULT}}"

  if [[ -n "${RC_HTTP_PROXY:-}" ]]; then
    ordered+=("${RC_HTTP_PROXY}")
    seen=" ${RC_HTTP_PROXY} "
  fi
  local candidate
  for candidate in "${CS_LAB_PROXY_CANDIDATES[@]}"; do
    [[ "${seen}" == *" ${candidate} "* ]] && continue
    ordered+=("${candidate}")
    seen+=" ${candidate} "
  done

  log "Selecting CS lab proxy (GET ${url})"
  for proxy in "${ordered[@]}"; do
    log "  probe ${proxy}"
    status="$(probe_cisco_repo_via_proxy "${proxy}")"
    log "  → HTTP ${status}"
    if [[ "${status}" == "200" ]]; then
      write_cs_lab_proxy_files "${proxy}"
      log "Using proxy ${proxy}"
      return 0
    fi
  done
  die "No proxy reached Cisco repo. Tried:${seen}
Set RC_HTTP_PROXY in rc.env to force one, or retry when lab network is stable."
}

# CS lab host prep: NTP (GPG) then proxy (egress). Single entry for deploy + check.
cs_lab_prepare_host() {
  ensure_cs_lab_ntp
  select_and_apply_cs_lab_proxy
}

ensure_cs_lab_ntp() {
  local conf_dir="/etc/systemd/timesyncd.conf.d"
  local conf_file="${conf_dir}/cisco.conf"

  if [[ ! -f "${conf_file}" ]] || ! grep -q '10.64.58.50' "${conf_file}"; then
    log "Configuring CS lab NTP (10.64.58.50) — needed for cosign GPG verify"
    run_as_root mkdir -p "${conf_dir}"
    run_as_root tee "${conf_file}" >/dev/null <<'EOF'
[Time]
NTP=10.64.58.50 ntp.esl.cisco.com
FallbackNTP=pool.ntp.org
EOF
    run_as_root timedatectl set-ntp true
    run_as_root systemctl restart systemd-timesyncd
    sleep 3
  fi

  if command -v timedatectl >/dev/null 2>&1; then
    local synced
    synced="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo unknown)"
    log "Clock: $(date -u +'%Y-%m-%d %H:%M:%S UTC') · NTP synchronized: ${synced}"
    if [[ "${synced}" != "yes" ]]; then
      die "NTP not synchronized — cosign GPG verify will fail. Wait 30s and retry, or: timedatectl timesync-status"
    fi
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
  local env_proxy="${RC_HTTP_PROXY:-}"
  # shellcheck source=/dev/null
  source "${file}"
  [[ -n "${env_name}" ]] && RC_NAME="${env_name}"
  [[ -n "${env_key}" ]] && RC_PROVISIONING_KEY="${env_key}"
  [[ -n "${env_yes}" ]] && RC_YES="${env_yes}"
  [[ -n "${env_proxy}" ]] && RC_HTTP_PROXY="${env_proxy}"

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

# rc.env is shared across RC VMs and now targets rc02. Refuse to launch on a
# host that already runs a connector (e.g. the rc01 VM) — a second launch there
# would enroll a duplicate under the wrong name.
preflight_no_existing_connector() {
  if systemctl is-active --quiet connector_svc 2>/dev/null; then
    die "connector_svc is already active — this host already runs a connector.
rc.env targets '${RC_NAME:-unset}'; launching here would enroll a duplicate.

  This host's connector : sudo systemctl status connector_svc --no-pager
  To really redeploy    : sudo ${RC_CONNECTOR_SH} stop --destroy  (revoke in dashboard first)"
  fi
}

preflight_system_clock() {
  local year
  year="$(date -u +%Y)"
  if (( year < 2025 )); then
    die "System clock looks wrong (UTC year=${year}). GPG cosign verify will fail.

Fix NTP then retry:
  timedatectl status
  sudo timedatectl set-ntp true
  sudo systemctl restart systemd-timesyncd
  # CS lab: /etc/systemd/timesyncd.conf.d/cisco.conf → NTP=10.64.58.50 ntp.esl.cisco.com"
  fi
  if command -v timedatectl >/dev/null 2>&1; then
    if timedatectl show -p NTPSynchronized --value 2>/dev/null | grep -q '^no$'; then
      log "WARNING: NTP not synchronized. Run: sudo timedatectl set-ntp true && sudo systemctl restart systemd-timesyncd"
    fi
  fi
}

preflight_host() {
  log "Running preflight checks..."
  preflight_system_clock

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

# Cisco setup_connector.sh calls bare "sudo curl" — ignores our shell proxy and
# no_proxy=.cisco.com makes it bypass proxy. Patch the script after download.
patch_setup_connector_for_proxy() {
  local setup="$1"
  local proxy="${2:-}"
  [[ -n "${proxy}" ]] || return 0
  [[ -f "${setup}" ]] || return 0

  if grep -q 'RC_DEPLOY_PROXY_PATCHED' "${setup}"; then
    return 0
  fi

  log "Patching setup_connector.sh: force proxy on sudo curl (CS lab egress)"
  local esc="${proxy//\\/\\\\}"
  esc="${esc//|/\\|}"
  esc="${esc//&/\\&}"

  sed -i \
    -e "s|sudo curl|sudo env -u no_proxy -u NO_PROXY http_proxy=${esc} https_proxy=${esc} curl -x ${esc}|g" \
    -e 's| -s -L | --connect-timeout 30 --max-time 900 -L --progress-bar |g' \
    "${setup}"

  printf '\n# RC_DEPLOY_PROXY_PATCHED=1\n' >>"${setup}"
}

ensure_connector_installed() {
  if [[ -x "${RC_CONNECTOR_SH}" ]]; then
    log "Connector install already present at ${RC_CONNECTOR_SH}; skipping setup_connector.sh"
    return 0
  fi

  if [[ -d /opt/connector/install ]]; then
    log "Cleaning partial install artifacts (failed cosign verify, etc.)"
    run_as_root rm -f /opt/connector/install/cosign-linux-amd64* \
      /opt/connector/install/*.sig /opt/connector/install/*.asc 2>/dev/null || true
  fi

  local workdir
  workdir="$(mktemp -d)"
  trap 'rm -rf "${workdir}"' RETURN

  local setup="${workdir}/setup_connector.sh"
  download_setup_script "${setup}"

  local proxy="${https_proxy:-${HTTPS_PROXY:-${http_proxy:-${HTTP_PROXY:-}}}}"
  patch_setup_connector_for_proxy "${setup}" "${proxy}"

  log "Running Cisco setup_connector.sh (installs Docker + /opt/connector)..."
  log "Note: cosign is ~110MB via proxy — 3-6 min at this line is normal (progress bar on next run)."
  if [[ -n "${proxy}" ]]; then
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
