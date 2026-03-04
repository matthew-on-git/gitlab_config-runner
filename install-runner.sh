#!/usr/bin/env bash
# Purpose: Install and register a GitLab Runner with Docker executor on a Debian/Ubuntu VM
# Usage: install-runner.sh [--help]
# Dependencies: apt, systemctl, curl
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
Usage: $(basename "$0") [--help]

Install and register a GitLab Runner with Docker executor.
Prompts for required configuration values interactively.

Must be run as root or with sudo.
EOF
  exit 0
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
fi

# --- Root check ---
if [[ "${EUID}" -ne 0 ]]; then
  die "This script must be run as root (use sudo)"
fi

# --- Prompt helper ---
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

# --- Gather configuration ---
log_info "GitLab Runner installation and registration"
echo ""

GITLAB_URL="$(prompt "GitLab URL" "GitLab instance URL" "${DEFAULT_GITLAB_URL}")"
REGISTRATION_TOKEN="$(prompt "Registration token" "Runner registration token" "" "true")"
RUNNER_NAME="$(prompt "Runner name" "Runner description/name" "${DEFAULT_RUNNER_NAME}")"
RUNNER_TAGS="$(prompt "Runner tags" "Comma-separated tags" "${DEFAULT_RUNNER_TAGS}")"

echo ""
log_info "Configuration summary:"
log_info "  GitLab URL:    ${GITLAB_URL}"
log_info "  Runner name:   ${RUNNER_NAME}"
log_info "  Runner tags:   ${RUNNER_TAGS}"
log_info "  Docker image:  ${DEFAULT_DOCKER_IMAGE}"
echo ""

read -rp "Proceed with installation? [Y/n]: " confirm
if [[ "${confirm}" =~ ^[Nn] ]]; then
  log_warn "Installation cancelled"
  exit 0
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
apt-get update -qq
apt-get install -y -qq gitlab-runner
log_info "GitLab Runner installed"

# --- Step 3: Install Docker ---
log_info "Installing Docker..."
apt-get install -y -qq docker.io docker-compose
log_info "Docker installed"

# --- Step 4: Add gitlab-runner user to docker group ---
log_info "Adding gitlab-runner user to docker group..."
usermod -aG docker gitlab-runner
log_info "gitlab-runner added to docker group"

# --- Step 5: Register the runner ---
if [[ ! -f /etc/gitlab-runner/config.toml ]]; then
  log_info "Registering GitLab Runner..."
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
