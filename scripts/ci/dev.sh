#!/usr/bin/env bash
# ==============================================================================
# dev.sh — Start HolyClaude locally via docker compose.
#
# Usage:
#   scripts/ci/dev.sh                # simple compose (jhangyu/holyclaude:latest)
#   scripts/ci/dev.sh --full         # full override compose (jhangyu/holyclaude:latest + .env)
#   scripts/ci/dev.sh --build        # rebuild image before starting
#   scripts/ci/dev.sh --no-detach    # run in foreground
#
# Flags:
#   --full             Use docker-compose.override.yaml (auto-copies from .example)
#   --build            Build images before starting
#   --no-detach        Run in foreground (default: detached)
#   --pull             Pull the latest image before starting
#   -h, --help         Show this help
# ==============================================================================
set -euo pipefail

CI_SCRIPT_NAME="dev"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PROJECT_ROOT="$(ci_project_root)"

usage() {
    sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
}

COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yaml"
OVERRIDE_FILE=""
DETACH=1
DO_BUILD=0
DO_PULL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --full)
            OVERRIDE_FILE="$PROJECT_ROOT/docker-compose.override.yaml"
            shift
            ;;
        --build)     DO_BUILD=1; shift ;;
        --no-detach) DETACH=0; shift ;;
        --pull)      DO_PULL=1; shift ;;
        -h|--help)   usage; exit 0 ;;
        *) die "Unknown argument: $1 (use --help)" ;;
    esac
done

require_cmd docker
docker compose version >/dev/null 2>&1 || die "'docker compose' is required"
[[ -f "$COMPOSE_FILE" ]] || die "Compose file not found: $COMPOSE_FILE"

# Auto-provision the override file from the example template if --full was passed
# and the live override doesn't exist yet.
if [[ -n "$OVERRIDE_FILE" ]]; then
    if [[ ! -f "$OVERRIDE_FILE" ]]; then
        EXAMPLE="$PROJECT_ROOT/docker-compose.override.yaml.example"
        if [[ -f "$EXAMPLE" ]]; then
            log_info "Copying override template: $EXAMPLE -> $OVERRIDE_FILE"
            cp "$EXAMPLE" "$OVERRIDE_FILE"
        else
            die "Override template not found: $EXAMPLE"
        fi
    fi
    # Full compose relies on host .env (HOLYCLAUDE_HOST_PORT etc.).
    load_env "$PROJECT_ROOT/.env"
fi

CMD=(docker compose -f "$COMPOSE_FILE")
[[ -n "$OVERRIDE_FILE" ]] && CMD+=(-f "$OVERRIDE_FILE")
[[ "$DO_PULL"  == "1" ]] && CMD+=(pull)
CMD+=(up)
[[ "$DETACH"   == "1" ]] && CMD+=(-d)
[[ "$DO_BUILD" == "1" ]] && CMD+=(--build)

log_step "Starting services"
if [[ -n "$OVERRIDE_FILE" ]]; then
    log_dim  "compose: $COMPOSE_FILE + $OVERRIDE_FILE"
else
    log_dim  "compose: $COMPOSE_FILE"
fi
log_info  "Command: ${CMD[*]}"
"${CMD[@]}"

if [[ "$DETACH" == "1" ]]; then
    log_info "Services started. Run scripts/ci/logs.sh to follow logs."
    log_info "Web UI: http://localhost:${HOLYCLAUDE_HOST_PORT:-3001}"
fi
