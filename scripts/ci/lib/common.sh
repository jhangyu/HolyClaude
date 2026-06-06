#!/usr/bin/env bash
# ==============================================================================
# HolyClaude — CI/CD shared library
# Provides colored logging, .env loading, command checks, and confirmation.
# Source this from sibling scripts:
#   source "${BASH_SOURCE%/*}/../lib/common.sh"
# ==============================================================================

# ---------- Color support ----------
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    _C_RESET=$'\033[0m'
    _C_INFO=$'\033[1;34m'    # bold blue
    _C_WARN=$'\033[1;33m'    # bold yellow
    _C_ERROR=$'\033[1;31m'   # bold red
    _C_STEP=$'\033[1;36m'    # bold cyan
    _C_DIM=$'\033[2m'
else
    _C_RESET=""
    _C_INFO=""
    _C_WARN=""
    _C_ERROR=""
    _C_STEP=""
    _C_DIM=""
fi

# ---------- Script helpers ----------
# Absolute directory containing the calling script (not common.sh itself).
ci_script_dir() {
    local src="${BASH_SOURCE[1]:-$0}"
    cd "$(dirname "$src")" && pwd
}

# Absolute path to the project root (one level above scripts/ci/).
ci_project_root() {
    local src="${BASH_SOURCE[1]:-$0}"
    cd "$(dirname "$src")/../.." && pwd
}

# ---------- Logging ----------
log_info()  { printf '%s[info]%s  %s\n'  "$_C_INFO"  "$_C_RESET" "$*"; }
log_warn()  { printf '%s[warn]%s  %s\n'  "$_C_WARN"  "$_C_RESET" "$*" >&2; }
log_error() { printf '%s[error]%s %s\n'  "$_C_ERROR" "$_C_RESET" "$*" >&2; }
log_step()  { printf '%s[%s]%s %s\n' "$_C_STEP" "${CI_SCRIPT_NAME:-step}" "$_C_RESET" "$*"; }
log_dim()   { printf '%s%s%s\n' "$_C_DIM" "$*" "$_C_RESET"; }

# ---------- Env loading ----------
# Load KEY=VALUE pairs from a file. Existing env vars are not overwritten
# unless `override=1` is passed.
load_env() {
    local file="${1:-}"
    if [[ -z "$file" ]] || [[ ! -f "$file" ]]; then
        return 0
    fi
    log_dim "Loading env from $file"
    set -a
    # shellcheck disable=SC1090
    source "$file"
    set +a
}

# ---------- Command checks ----------
require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Required command not found: $cmd"
        return 127
    fi
}

# ---------- Confirmation ----------
# confirm <prompt> [default_yes]
#   default_yes=1  -> empty answer = yes
#   default_yes=0  -> empty answer = no
#   ASSUME_YES=1   -> always yes (non-interactive)
#   ASSUME_NO=1    -> always no  (non-interactive)
# Returns 0 for yes, 1 for no.
confirm() {
    local prompt="$1"
    local default_yes="${2:-0}"
    if [[ "${ASSUME_YES:-0}" == "1" ]]; then return 0; fi
    if [[ "${ASSUME_NO:-0}" == "1" ]]; then return 1; fi
    if [[ ! -t 0 ]]; then
        log_warn "Non-interactive shell: defaulting to no"
        return 1
    fi
    local suffix
    if [[ "$default_yes" == "1" ]]; then suffix="[Y/n]"; else suffix="[y/N]"; fi
    local reply
    read -r -p "$(printf '%s %s: ' "$prompt" "$suffix")" reply
    reply="${reply:-}"
    case "${reply,,}" in
        y|yes) return 0 ;;
        n|no)  return 1 ;;
        "")
            [[ "$default_yes" == "1" ]] && return 0 || return 1
            ;;
        *) return 1 ;;
    esac
}

# ---------- Trap-based cleanup ----------
# Register a cleanup hook. Runs on EXIT (success or failure).
ci_cleanup_register() {
    ci_cleanup_hooks+=("$*")
}

ci_cleanup_run() {
    local hook
    for hook in "${ci_cleanup_hooks[@]:-}"; do
        eval "$hook" || true
    done
}
ci_cleanup_hooks=()
trap ci_cleanup_run EXIT

# ---------- die ----------
die() {
    log_error "$*"
    exit 1
}
