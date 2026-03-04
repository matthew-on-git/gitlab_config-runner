#!/usr/bin/env bash
# Purpose: Install and register a GitLab Runner with Docker executor on a Debian/Ubuntu VM
# Usage: install-runner.sh [-u URL] [-t TOKEN] [-n NAME] [-T TAGS] [-d] [-y] [-h]
# Dependencies: apt, systemctl, curl, gpg
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/log.sh
source "${SCRIPT_DIR}/lib/log.sh"

# --- Defaults ---
readonly DEFAULT_GITLAB_URL="https://gitlab.example.com"
readonly DEFAULT_RUNNER_TAGS="docker"
DEFAULT_RUNNER_NAME="$(hostname)-runner"
readonly DEFAULT_RUNNER_NAME
readonly DEFAULT_DOCKER_IMAGE="alpine:latest"

# --- Help ---
usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Install and register a GitLab Runner with Docker executor.
Options not provided via flags will be prompted interactively.

Options:
  -u, --url URL        GitLab instance URL (default: ${DEFAULT_GITLAB_URL})
  -t, --token TOKEN    Runner registration token (required)
  -n, --name NAME      Runner description/name (default: ${DEFAULT_RUNNER_NAME})
  -T, --tags TAGS      Comma-separated runner tags (default: ${DEFAULT_RUNNER_TAGS})
  -d, --debug          Enable debug/verbose output
  -y, --yes            Skip confirmation prompt
  -h, --help           Show this help message

Examples:
  sudo ./$(basename "$0")
  sudo ./$(basename "$0") -u https://gitlab.example.com -t glrt-xxxxxxxxxxxx
  sudo ./$(basename "$0") -u https://gitlab.example.com -t glrt-xxxxxxxxxxxx -n my-runner -T docker,deploy -y
EOF
  exit 0
}

# --- Parse flags ---
GITLAB_URL=""
REGISTRATION_TOKEN=""
RUNNER_NAME=""
RUNNER_TAGS=""
DEBUG=0
SKIP_CONFIRM=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  -u | --url)
    GITLAB_URL="$2"
    shift 2
    ;;
  -t | --token)
    REGISTRATION_TOKEN="$2"
    shift 2
    ;;
  -n | --name)
    RUNNER_NAME="$2"
    shift 2
    ;;
  -T | --tags)
    RUNNER_TAGS="$2"
    shift 2
    ;;
  -d | --debug)
    DEBUG=1
    shift
    ;;
  -y | --yes)
    SKIP_CONFIRM=1
    shift
    ;;
  -h | --help)
    usage
    ;;
  *)
    log_error "Unknown option: $1"
    usage
    ;;
  esac
done

# Enable debug logging if requested
if [[ "${DEBUG}" -eq 1 ]]; then
  export DEVRAIL_DEBUG=1
  # Re-source to pick up the debug flag
  source "${SCRIPT_DIR}/lib/log.sh"
  log_debug "Debug output enabled"
fi

# --- Root check ---
if [[ "${EUID}" -ne 0 ]]; then
  die "This script must be run as root (use sudo)"
fi

# --- Prompt helper (only prompts if value is empty) ---
prompt() {
  local var_name="$1"
  local prompt_text="$2"
  local default="${3:-}"
  local secret="${4:-false}"
  local value

  if [[ -n "${default}" ]]; then
    prompt_text="${prompt_text} [${default}]"
  fi

  if [[ "${secret}" == "true" ]]; then
    read -rsp "${prompt_text}: " value
    echo >&2
  else
    read -rp "${prompt_text}: " value
  fi

  value="${value:-${default}}"

  if [[ -z "${value}" ]]; then
    die "${var_name} is required"
  fi

  printf '%s' "${value}"
}

# --- Gather configuration (prompt for anything not set via flags) ---
log_info "GitLab Runner installation and registration"
echo ""

if [[ -z "${GITLAB_URL}" ]]; then
  GITLAB_URL="$(prompt "GitLab URL" "GitLab instance URL" "${DEFAULT_GITLAB_URL}")"
fi

if [[ -z "${REGISTRATION_TOKEN}" ]]; then
  REGISTRATION_TOKEN="$(prompt "Registration token" "Runner registration token" "" "true")"
fi

if [[ -z "${RUNNER_NAME}" ]]; then
  RUNNER_NAME="$(prompt "Runner name" "Runner description/name" "${DEFAULT_RUNNER_NAME}")"
fi

if [[ -z "${RUNNER_TAGS}" ]]; then
  RUNNER_TAGS="$(prompt "Runner tags" "Comma-separated tags" "${DEFAULT_RUNNER_TAGS}")"
fi

echo ""
log_info "Configuration summary:"
log_info "  GitLab URL:    ${GITLAB_URL}"
log_info "  Runner name:   ${RUNNER_NAME}"
log_info "  Runner tags:   ${RUNNER_TAGS}"
log_info "  Docker image:  ${DEFAULT_DOCKER_IMAGE}"
echo ""

if [[ "${SKIP_CONFIRM}" -eq 0 ]]; then
  read -rp "Proceed with installation? [Y/n]: " confirm
  if [[ "${confirm}" =~ ^[Nn] ]]; then
    log_warn "Installation cancelled"
    exit 0
  fi
fi

# --- Cleanup on failure ---
cleanup() {
  local exit_code=$?
  if [[ ${exit_code} -ne 0 ]]; then
    log_error "Installation failed (exit code: ${exit_code})"
  fi
}
trap cleanup EXIT

# --- Step 1: Add GitLab Runner repository ---
log_info "Adding GitLab Runner repository..."
if [[ ! -f /etc/apt/sources.list.d/runner_gitlab-runner.list ]]; then
  log_debug "Downloading GitLab Runner repo setup script"
  curl -fsSL https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh -o /tmp/gitlab-runner-repo.sh
  chmod 0755 /tmp/gitlab-runner-repo.sh
  /tmp/gitlab-runner-repo.sh
  rm -f /tmp/gitlab-runner-repo.sh
  log_info "GitLab Runner repository added"
else
  log_info "GitLab Runner repository already configured, skipping"
fi

# --- Step 2: Install GitLab Runner ---
log_info "Installing GitLab Runner..."
log_debug "Running apt-get update"
apt-get update -qq
log_debug "Installing gitlab-runner package"
apt-get install -y -qq gitlab-runner
log_info "GitLab Runner installed"

# --- Step 3: Install Docker from official repository ---
log_info "Installing Docker..."
if ! command -v docker &>/dev/null; then
  log_debug "Adding Docker GPG key and apt repository"
  apt-get install -y -qq ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  # Detect distro for the apt source (VERSION_CODENAME and ID come from os-release)
  # shellcheck source=/dev/null
  . /etc/os-release
  local_codename="${VERSION_CODENAME:-}"
  local_id="${ID:-}"
  log_debug "Detected distro: ${local_id} ${local_codename}"

  if [[ ! -f /etc/apt/sources.list.d/docker.list ]]; then
    local_arch="$(dpkg --print-architecture)"
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/%s %s stable\n' \
      "${local_arch}" \
      "${local_id}" \
      "${local_codename}" \
      >/etc/apt/sources.list.d/docker.list
  fi

  log_debug "Running apt-get update for Docker repo"
  apt-get update -qq
  log_debug "Installing Docker packages"
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
  log_info "Docker installed from official repository"
else
  log_info "Docker already installed, skipping"
  docker_ver="$(docker --version)" || true
  log_debug "Docker version: ${docker_ver}"
fi

# --- Step 4: Add gitlab-runner user to docker group ---
log_info "Adding gitlab-runner user to docker group..."
usermod -aG docker gitlab-runner
log_info "gitlab-runner added to docker group"

# --- Step 5: Register the runner ---
if [[ ! -f /etc/gitlab-runner/config.toml ]]; then
  log_info "Registering GitLab Runner..."
  log_debug "Registration URL: ${GITLAB_URL}"
  log_debug "Runner name: ${RUNNER_NAME}"
  log_debug "Runner tags: ${RUNNER_TAGS}"
  gitlab-runner register \
    --non-interactive \
    --url "${GITLAB_URL}" \
    --registration-token "${REGISTRATION_TOKEN}" \
    --executor "docker" \
    --docker-image "${DEFAULT_DOCKER_IMAGE}" \
    --description "${RUNNER_NAME}" \
    --tag-list "${RUNNER_TAGS}" \
    --run-untagged="false" \
    --locked="false" \
    --docker-privileged="true" \
    --docker-volumes "/var/run/docker.sock:/var/run/docker.sock"
  log_info "GitLab Runner registered"
else
  log_info "Runner already registered (/etc/gitlab-runner/config.toml exists), skipping"
fi

# --- Step 6: Start and enable the service ---
log_info "Starting GitLab Runner service..."
systemctl daemon-reload
systemctl enable gitlab-runner
systemctl start gitlab-runner
log_info "GitLab Runner service started and enabled"

# --- Step 7: Verify ---
log_info "Verifying runner status..."
gitlab-runner verify

log_info "Installation complete"
