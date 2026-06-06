#!/usr/bin/env bash
# ==============================================================================
# test.sh — Run project tests.
#
# TODO: no test framework detected in this project. This script currently
# only acts as a placeholder — see the README for how to extend it.
# The HolyClaude image is a runtime container image; there is no test suite
# at the project root (no Makefile, no package.json, no pytest/go test/cargo
# test configuration).
#
# Usage:
#   scripts/ci/test.sh                  # placeholder; warns and exits 0
#   scripts/ci/test.sh --inside         # run inside the running container
#
# Flags:
#   --inside, -i     Run a (future) test command inside the running container
#   --cmd <string>   Override the test command (default: echo placeholder)
#   -h, --help       Show this help
# ==============================================================================
set -euo pipefail

CI_SCRIPT_NAME="test"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PROJECT_ROOT="$(ci_project_root)"

usage() {
    sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
}

INSIDE=0
TEST_CMD=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --inside|-i)  INSIDE=1; shift ;;
        --cmd)        TEST_CMD="$2"; shift 2 ;;
        -h|--help)    usage; exit 0 ;;
        *) die "Unknown argument: $1 (use --help)" ;;
    esac
done

# ---------- Test framework detection ----------
HAS_MAKEFILE=0
HAS_PKG_JSON=0
HAS_PYTEST=0
HAS_GO=0
HAS_CARGO=0
[[ -f "$PROJECT_ROOT/Makefile" ]]      && HAS_MAKEFILE=1
[[ -f "$PROJECT_ROOT/package.json" ]]  && HAS_PYTEST=0 && HAS_PKG_JSON=1
[[ -f "$PROJECT_ROOT/pytest.ini" || -f "$PROJECT_ROOT/pyproject.toml" || -f "$PROJECT_ROOT/setup.py" ]] && HAS_PYTEST=1
[[ -f "$PROJECT_ROOT/go.mod" ]]        && HAS_GO=1
[[ -f "$PROJECT_ROOT/Cargo.toml" ]]    && HAS_CARGO=1

DETECTED=0
[[ "$HAS_MAKEFILE" == "1" ]] && DETECTED=1
[[ "$HAS_PKG_JSON"  == "1" ]] && DETECTED=1
[[ "$HAS_PYTEST"    == "1" ]] && DETECTED=1
[[ "$HAS_GO"        == "1" ]] && DETECTED=1
[[ "$HAS_CARGO"     == "1" ]] && DETECTED=1

if [[ "$DETECTED" == "0" ]]; then
    # TODO: no test framework detected in this project.
    log_warn "No test framework detected in $PROJECT_ROOT"
    log_warn "HolyClaude is a runtime container image; tests live inside the image."
    log_warn "Placeholder exit 0."
    exit 0
fi

# ---------- Run detected framework ----------
if [[ "$INSIDE" == "1" ]]; then
    require_cmd docker
    log_step "Running tests inside container"
    if [[ -n "$TEST_CMD" ]]; then
        docker compose -f "$PROJECT_ROOT/docker-compose.yaml" exec holyclaude bash -c "$TEST_CMD"
    elif [[ "$HAS_MAKEFILE" == "1" ]]; then
        docker compose -f "$PROJECT_ROOT/docker-compose.yaml" exec holyclaude make test
    else
        die "--inside requested but no --cmd and no Makefile"
    fi
else
    if [[ -n "$TEST_CMD" ]]; then
        log_step "Running: $TEST_CMD"
        eval "$TEST_CMD"
    elif [[ "$HAS_MAKEFILE" == "1" ]]; then
        log_step "Running: make test"
        make -C "$PROJECT_ROOT" test
    elif [[ "$HAS_PYTEST" == "1" ]]; then
        require_cmd pytest
        log_step "Running: pytest"
        pytest "$PROJECT_ROOT"
    elif [[ "$HAS_GO" == "1" ]]; then
        require_cmd go
        log_step "Running: go test ./..."
        (cd "$PROJECT_ROOT" && go test ./...)
    elif [[ "$HAS_CARGO" == "1" ]]; then
        require_cmd cargo
        log_step "Running: cargo test"
        (cd "$PROJECT_ROOT" && cargo test)
    elif [[ "$HAS_PKG_JSON" == "1" ]]; then
        require_cmd npm
        log_step "Running: npm test"
        (cd "$PROJECT_ROOT" && npm test)
    fi
fi
