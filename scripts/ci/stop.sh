#!/usr/bin/env bash
# ==============================================================================
# stop.sh — Stop HolyClaude services via docker compose.
#
# Usage:
#   scripts/ci/stop.sh            # simple compose
#   scripts/ci/stop.sh --full     # override compose
#   scripts/ci/stop.sh --volumes  # also remove volumes (destructive!)
#
# Flags:
#   --full             Use docker-compose.override.yaml
#   --volumes, -v      Remove named volumes
#   --remove-orphans   Also remove orphaned containers
#   -h, --help         Show this help
# ==============================================================================
set -euo pipefail

CI_SCRIPT_NAME="stop"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PROJECT_ROOT="$(ci_project_root)"

usage() {
    sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
}

COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yaml"
OVERRIDE_FILE=""
REMOVE_VOLUMES=0
REMOVE_ORPHANS=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --full)           OVERRIDE_FILE="$PROJECT_ROOT/docker-compose.override.yaml"; shift ;;
        --volumes|-v)     REMOVE_VOLUMES=1; shift ;;
        --remove-orphans) REMOVE_ORPHANS=1; shift ;;
        -h|--help)        usage; exit 0 ;;
        *) die "Unknown argument: $1 (use --help)" ;;
    esac
done

require_cmd docker
docker compose version >/dev/null 2>&1 || die "'docker compose' is required"
[[ -f "$COMPOSE_FILE" ]] || die "Compose file not found: $COMPOSE_FILE"

CMD=(docker compose -f "$COMPOSE_FILE")
[[ -n "$OVERRIDE_FILE" ]] && {
    [[ -f "$OVERRIDE_FILE" ]] || die "Override file not found: $OVERRIDE_FILE (run dev.sh --full once to provision)"
    CMD+=(-f "$OVERRIDE_FILE")
}
CMD+=(down)
[[ "$REMOVE_ORPHANS" == "1" ]] && CMD+=(--remove-orphans)
[[ "$REMOVE_VOLUMES"  == "1" ]] && {
    log_warn "--volumes will delete persistent data; confirming"
    confirm "Remove named volumes?" 0 || { log_info "Aborted"; exit 0; }
    CMD+=(-v)
}

log_step "Stopping services"
if [[ -n "$OVERRIDE_FILE" ]]; then
    log_dim  "compose: $COMPOSE_FILE + $OVERRIDE_FILE"
else
    log_dim  "compose: $COMPOSE_FILE"
fi
log_info  "Command: ${CMD[*]}"
"${CMD[@]}"
log_info "Services stopped."
