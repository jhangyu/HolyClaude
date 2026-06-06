#!/usr/bin/env bash
# ==============================================================================
# clean.sh — Remove Docker resources associated with HolyClaude.
#
# Usage:
#   scripts/ci/clean.sh                     # safe defaults: dangling images + stopped containers
#   scripts/ci/clean.sh --containers        # remove stopped containers only
#   scripts/ci/clean.sh --images            # remove holyclaude* images (and dangling)
#   scripts/ci/clean.sh --volumes           # remove holyclaude* named volumes (DESTRUCTIVE)
#   scripts/ci/clean.sh --all               # containers + images + volumes
#   ASSUME_YES=1 scripts/ci/clean.sh --all  # non-interactive
#
# Flags:
#   --containers     Remove stopped containers
#   --images         Remove holyclaude* images and dangling images
#   --volumes        Remove holyclaude* volumes (interactive confirm)
#   --all            Equivalent to --containers --images --volumes
#   --dry-run        Print what would be removed, but do not run docker
#   -h, --help       Show this help
# ==============================================================================
set -euo pipefail

CI_SCRIPT_NAME="clean"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PROJECT_ROOT="$(ci_project_root)"

usage() {
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

DO_CONTAINERS=0
DO_IMAGES=0
DO_VOLUMES=0
DRY_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --containers) DO_CONTAINERS=1; shift ;;
        --images)     DO_IMAGES=1; shift ;;
        --volumes)    DO_VOLUMES=1; shift ;;
        --all)        DO_CONTAINERS=1; DO_IMAGES=1; DO_VOLUMES=1; shift ;;
        --dry-run)    DRY_RUN=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        *) die "Unknown argument: $1 (use --help)" ;;
    esac
done

require_cmd docker

# Safe default: at least clean dangling resources.
if [[ "$DO_CONTAINERS" == "0" ]] && [[ "$DO_IMAGES" == "0" ]] && [[ "$DO_VOLUMES" == "0" ]]; then
    log_info "No flags given: defaulting to safe cleanup (stopped containers + dangling images)"
    DO_CONTAINERS=1
    DO_IMAGES_SAFE=1
else
    DO_IMAGES_SAFE=0
fi

run_or_echo() {
    if [[ "$DRY_RUN" == "1" ]]; then
        printf '%s[skip]%s   %s\n' "$_C_DIM" "$_C_RESET" "$*"
    else
        log_info "$*"
        eval "$@"
    fi
}

if [[ "$DO_VOLUMES" == "1" ]]; then
    log_warn "Volume removal is destructive. Persistent data will be lost."
    confirm "Continue and remove holyclaude* volumes?" 0 || {
        log_info "Aborted volume removal"
        DO_VOLUMES=0
    }
fi

log_step "Cleanup plan"
[[ "$DO_CONTAINERS" == "1" ]] && log_dim "  - remove stopped containers"
[[ "$DO_IMAGES"     == "1" || "$DO_IMAGES_SAFE" == "1" ]] && log_dim "  - remove holyclaude* images and dangling images"
[[ "$DO_VOLUMES"    == "1" ]] && log_dim "  - remove holyclaude* volumes"
[[ "$DRY_RUN"       == "1" ]] && log_dim "  - DRY-RUN (no changes will be made)"

# Confirm if anything destructive.
if [[ "$DO_IMAGES" == "1" ]] || [[ "$DO_VOLUMES" == "1" ]]; then
    confirm "Proceed with cleanup?" 0 || { log_info "Aborted"; exit 0; }
fi

# ---------- Containers ----------
if [[ "$DO_CONTAINERS" == "1" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
        run_or_echo "docker ps -a -q --filter 'label=com.docker.compose.project=holyclaude'"
    else
        ids=$(docker ps -a -q --filter 'label=com.docker.compose.project=holyclaude' || true)
        if [[ -n "$ids" ]]; then
            run_or_echo "docker rm $ids"
        else
            log_info "No stopped holyclaude containers"
        fi
    fi
fi

# ---------- Images ----------
if [[ "$DO_IMAGES" == "1" || "$DO_IMAGES_SAFE" == "1" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
        run_or_echo "docker images -q --filter 'reference=holyclaude*'"
        run_or_echo "docker image prune -f"
    else
        imgs=$(docker images -q --filter "reference=holyclaude*" || true)
        if [[ -n "$imgs" ]]; then
            run_or_echo "docker rmi $imgs"
        else
            log_info "No holyclaude* images"
        fi
        run_or_echo "docker image prune -f"
    fi
fi

# ---------- Volumes ----------
if [[ "$DO_VOLUMES" == "1" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
        run_or_echo "docker volume ls -q --filter 'label=com.docker.compose.project=holyclaude'"
    else
        vols=$(docker volume ls -q --filter "label=com.docker.compose.project=holyclaude" || true)
        if [[ -n "$vols" ]]; then
            run_or_echo "docker volume rm $vols"
        else
            log_info "No holyclaude volumes"
        fi
    fi
fi

log_info "Cleanup complete."
