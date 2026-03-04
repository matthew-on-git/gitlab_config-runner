#!/usr/bin/env bash
# Purpose: Shared logging library for consistent output formatting
# Usage: source lib/log.sh
# Dependencies: bash 4+
set -euo pipefail

LOG_FORMAT="${DEVRAIL_LOG_FORMAT:-human}"
LOG_QUIET="${DEVRAIL_QUIET:-0}"
LOG_DEBUG_ENABLED="${DEVRAIL_DEBUG:-0}"

_log() {
  local level="$1"
  shift
  local msg="$*"

  if [[ "${LOG_QUIET}" == "1" && "${level}" != "error" ]]; then
    return
  fi

  if [[ "${LOG_FORMAT}" == "json" ]]; then
    local ts
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '{"level":"%s","msg":"%s","ts":"%s"}\n' "${level}" "${msg}" "${ts}" >&2
  else
    local prefix
    case "${level}" in
    info) prefix="[INFO]" ;;
    warn) prefix="[WARN]" ;;
    error) prefix="[ERROR]" ;;
    debug) prefix="[DEBUG]" ;;
    *) prefix="[${level^^}]" ;;
    esac
    printf '%s  %s\n' "${prefix}" "${msg}" >&2
  fi
}

log_info() { _log "info" "$@"; }
log_warn() { _log "warn" "$@"; }
log_error() { _log "error" "$@"; }

log_debug() {
  if [[ "${LOG_DEBUG_ENABLED}" == "1" ]]; then
    _log "debug" "$@"
  fi
}

die() {
  log_error "$@"
  exit 1
}
