#!/usr/bin/env bash
# ==============================================================================
# deploy.sh — Deploy HolyClaude to a target environment.
#
# By default this is a DRY-RUN that prints the planned actions.
# Pass --prod / --execute to actually perform the deployment.
#
# Configuration is read from the project .env file:
#   DEPLOY_TARGET   local | compose | <custom>   (default: local)
#   DEPLOY_IMAGE    image:tag to deploy           (default: holyclaude:local)
#   DEPLOY_COMPOSE  compose file path             (default: picked from target)
#
# Usage:
#   scripts/ci/deploy.sh                          # dry-run, target=local
#   scripts/ci/deploy.sh --prod                   # actually run
#   scripts/ci/deploy.sh --target compose --prod  # target the override compose file
#   scripts/ci/deploy.sh --image ghcr.io/me/hc:1.0 --prod
#
# Flags:
#   --target <name>        Deployment target (overrides DEPLOY_TARGET)
#   --image <image:tag>    Image to deploy (overrides DEPLOY_IMAGE)
#   --compose-file <path>  Compose file (overrides DEPLOY_COMPOSE / target default)
#   --prod, --execute      Actually perform the deployment (default: dry-run)
#   -h, --help             Show this help
# ==============================================================================
set -euo pipefail

CI_SCRIPT_NAME="deploy"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PROJECT_ROOT="$(ci_project_root)"
load_env "$PROJECT_ROOT/.env"

usage() {
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

TARGET="${DEPLOY_TARGET:-local}"
IMAGE="${DEPLOY_IMAGE:-holyclaude:local}"
COMPOSE_FILE="${DEPLOY_COMPOSE:-}"
EXECUTE=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target)       TARGET="$2"; shift 2 ;;
        --image)        IMAGE="$2"; shift 2 ;;
        --compose-file) COMPOSE_FILE="$2"; shift 2 ;;
        --prod)         EXECUTE=1; shift ;;
        --execute)      EXECUTE=1; shift ;;
        -h|--help)      usage; exit 0 ;;
        *) die "Unknown argument: $1 (use --help)" ;;
    esac
done

# ---------- Resolve compose file ----------
resolve_compose() {
    if [[ -n "$COMPOSE_FILE" ]]; then
        echo "$COMPOSE_FILE"
        return
    fi
    case "$TARGET" in
        local)         echo "$PROJECT_ROOT/docker-compose.yaml" ;;
        compose|full)
            # Auto-provision override file from template if missing
            local override="$PROJECT_ROOT/docker-compose.override.yaml"
            if [[ ! -f "$override" ]]; then
                local example="$PROJECT_ROOT/docker-compose.override.yaml.example"
                if [[ -f "$example" ]]; then
                    log_info "Copying override template: $example -> $override"
                    cp "$example" "$override"
                else
                    die "Override template not found: $example"
                fi
            fi
            # For override targets, we merge base + override on the command line.
            # But resolve_compose can only return a single path for logging,
            # so callers should use the resolve_compose_args helper.
            echo "$override"
            ;;
        *)             echo "$PROJECT_ROOT/docker-compose.yaml" ;;
    esac
}

# Return all -f args the deploy command should use, accounting for override targets.
resolve_compose_args() {
    case "$TARGET" in
        compose|full)
            [[ -n "$COMPOSE_FILE" ]] && { echo "-f $COMPOSE_FILE"; return; }
            echo "-f $PROJECT_ROOT/docker-compose.yaml -f $(resolve_compose)"
            ;;
        *)
            echo "-f $(resolve_compose)"
            ;;
    esac
}

COMPOSE_FILE="$(resolve_compose)"
[[ -f "$COMPOSE_FILE" ]] || die "Compose file not found: $COMPOSE_FILE"
COMPOSE_ARGS="$(resolve_compose_args)"

# ---------- Plan ----------
log_step "Deployment plan"
log_dim  "  target:      $TARGET"
log_dim  "  image:       $IMAGE"
log_dim  "  compose:     $COMPOSE_FILE"
log_dim  "  mode:        $([[ $EXECUTE -eq 1 ]] && echo EXECUTE || echo DRY-RUN)"

# Compose-level overrides: if image differs from compose file's image, warn.
if [[ "$IMAGE" != "holyclaude:local" ]]; then
    log_warn "Custom image '$IMAGE' will not be applied to the compose file automatically."
    log_warn "If the compose file pins a registry image, edit it or use --compose-file."
fi

# ---------- Build commands ----------
# shellcheck disable=SC2206
PULL_CMD=(docker compose $COMPOSE_ARGS pull)
# shellcheck disable=SC2206
UP_CMD=(docker compose $COMPOSE_ARGS up -d)

log_dim ""
log_dim "Commands that would be executed:"
log_dim "  1) ${PULL_CMD[*]}"
log_dim "  2) ${UP_CMD[*]}"

if [[ "$EXECUTE" -ne 1 ]]; then
    log_warn "Dry-run only. Re-run with --prod to execute."
    exit 0
fi

# ---------- Execute ----------
require_cmd docker
docker compose version >/dev/null 2>&1 || die "'docker compose' is required"

log_step "Executing deployment"
log_info "1/2) ${PULL_CMD[*]}"
"${PULL_CMD[@]}"
log_info "2/2) ${UP_CMD[*]}"
"${UP_CMD[@]}"
log_info "Deployment complete. Image=$IMAGE Target=$TARGET"
