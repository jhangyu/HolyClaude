#!/usr/bin/env bash
# ==============================================================================
# logs.sh — Tail logs from running HolyClaude services.
#
# Usage:
#   scripts/ci/logs.sh                       # follow all services, tail 100
#   scripts/ci/logs.sh --no-follow --tail 500
#   scripts/ci/logs.sh --service holyclaude
#   scripts/ci/logs.sh --full                # override compose
#
# Flags:
#   --follow, -f        Follow log output (default)
#   --no-follow         Print and exit
#   --tail <N>          Number of lines to show (default: 100)
#   --service <name>    Show logs for a single service (default: all)
#   --timestamps, -t    Show timestamps
#   --full              Use docker-compose.override.yaml
#   -h, --help          Show this help
# ==============================================================================
set -euo pipefail

CI_SCRIPT_NAME="logs"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PROJECT_ROOT="$(ci_project_root)"

usage() {
    sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
}

COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yaml"
OVERRIDE_FILE=""
FOLLOW=1
TAIL=100
SERVICE=""
TIMESTAMPS=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --follow|-f)    FOLLOW=1; shift ;;
        --no-follow)    FOLLOW=0; shift ;;
        --tail)         TAIL="$2"; shift 2 ;;
        --service)      SERVICE="$2"; shift 2 ;;
        --timestamps|-t) TIMESTAMPS=1; shift ;;
        --full)         OVERRIDE_FILE="$PROJECT_ROOT/docker-compose.override.yaml"; shift ;;
        -h|--help)      usage; exit 0 ;;
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
CMD+=(logs)
[[ "$FOLLOW"    == "1" ]] && CMD+=(--follow)
[[ "$TIMESTAMPS" == "1" ]] && CMD+=(--timestamps)
CMD+=(--tail "$TAIL")
[[ -n "$SERVICE" ]] && CMD+=("$SERVICE")

log_step "Tailing logs"
if [[ -n "$OVERRIDE_FILE" ]]; then
    log_dim  "compose: $COMPOSE_FILE + $OVERRIDE_FILE"
else
    log_dim  "compose: $COMPOSE_FILE"
fi
[[ -n "$SERVICE" ]] && log_dim "service: $SERVICE" || log_dim "service: (all)"
log_dim  "tail:    $TAIL"
log_info  "Command: ${CMD[*]}"
"${CMD[@]}"
