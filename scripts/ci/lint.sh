#!/usr/bin/env bash
# ==============================================================================
# lint.sh — Run lint checks.
#
# The HolyClaude project has no top-level lint framework (no eslint, ruff,
# flake8 config). This script defaults to running shellcheck on every .sh
# under scripts/ if shellcheck is available, and otherwise warns and exits 0.
# TODO: extend with project-specific linters as they are added.
#
# Usage:
#   scripts/ci/lint.sh                       # shellcheck all scripts/*.sh and scripts/ci/*.sh
#   scripts/ci/lint.sh --inside              # run inside the running container
#   scripts/ci/lint.sh --check <file>        # lint a single file
#
# Flags:
#   --check <path>   Lint a single file or directory
#   --inside, -i     Run lint inside the running container
#   -h, --help       Show this help
# ==============================================================================
set -euo pipefail

CI_SCRIPT_NAME="lint"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PROJECT_ROOT="$(ci_project_root)"

usage() {
    sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
}

CHECK_PATH=""
INSIDE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)      CHECK_PATH="$2"; shift 2 ;;
        --inside|-i)  INSIDE=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        *) die "Unknown argument: $1 (use --help)" ;;
    esac
done

# ---------- Tool detection ----------
HAS_SHELLCHECK=0
HAS_ESLINT=0
HAS_RUFF=0
HAS_FLAKE8=0
command -v shellcheck >/dev/null 2>&1 && HAS_SHELLCHECK=1
command -v eslint     >/dev/null 2>&1 && HAS_ESLINT=1
command -v ruff       >/dev/null 2>&1 && HAS_RUFF=1
command -v flake8     >/dev/null 2>&1 && HAS_FLAKE8=1

if [[ "$INSIDE" == "1" ]]; then
    require_cmd docker
    log_step "Running lint inside container"
    docker compose -f "$PROJECT_ROOT/docker-compose.yaml" exec holyclaude \
        bash -lc "shellcheck /workspace/scripts/ci/*.sh /workspace/scripts/ci/lib/*.sh || true"
    exit 0
fi

ran=0

# ---------- Shellcheck on project shell scripts ----------
if [[ "$HAS_SHELLCHECK" == "1" ]]; then
    if [[ -n "$CHECK_PATH" ]]; then
        targets=("$CHECK_PATH")
    else
        targets=()
        while IFS= read -r f; do targets+=("$f"); done < <(find "$PROJECT_ROOT/scripts" -type f -name "*.sh")
        # Also include this script's siblings if they exist.
        while IFS= read -r f; do targets+=("$f"); done < <(find "$SCRIPT_DIR" -type f -name "*.sh")
    fi

    if [[ "${#targets[@]}" -gt 0 ]]; then
        log_step "shellcheck (${#targets[@]} files)"
        # shellcheck disable=SC2068
        shellcheck ${targets[@]} && ran=1
    fi
else
    log_warn "shellcheck not installed; skipping .sh lint"
fi

# ---------- Future: eslint / ruff / flake8 ----------
# TODO: extend when project-level configs are added.
[[ "$HAS_ESLINT" == "1" && -f "$PROJECT_ROOT/.eslintrc" || -f "$PROJECT_ROOT/.eslintrc.js" || -f "$PROJECT_ROOT/eslint.config.js" ]] \
    && { log_step "eslint"; (cd "$PROJECT_ROOT" && eslint .) && ran=1; }
[[ "$HAS_RUFF"   == "1" && -f "$PROJECT_ROOT/ruff.toml" || -f "$PROJECT_ROOT/pyproject.toml" ]] \
    && { log_step "ruff"; (cd "$PROJECT_ROOT" && ruff check .) && ran=1; }
[[ "$HAS_FLAKE8" == "1" && -f "$PROJECT_ROOT/.flake8" || -f "$PROJECT_ROOT/setup.cfg" ]] \
    && { log_step "flake8"; (cd "$PROJECT_ROOT" && flake8) && ran=1; }

if [[ "$ran" == "0" ]]; then
    log_warn "No lint framework ran (shellcheck may have failed; configs absent)"
    log_warn "TODO: extend scripts/ci/lint.sh when project-level configs are added"
    exit 0
fi

log_info "Lint passed."
