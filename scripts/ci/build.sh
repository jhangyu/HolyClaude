#!/usr/bin/env bash
# ==============================================================================
# build.sh — Build the HolyClaude Docker image locally.
#
# Usage:
#   scripts/ci/build.sh                     # default: holyclaude:local, variant=full
#   scripts/ci/build.sh --tag hc:dev --variant slim
#   scripts/ci/build.sh --no-cache --push --platform linux/amd64,linux/arm64
#
# Flags:
#   --tag <name>          Image tag (default: holyclaude:local)
#   --variant <name>      full | slim (default: full, passed as VARIANT build-arg)
#   --dockerfile <path>   Dockerfile path (default: <project_root>/Dockerfile)
#   --context <path>      Build context (default: project root)
#   --no-cache            Disable Docker build cache
#   --platform <list>     Target platforms (e.g. linux/amd64,linux/arm64)
#   --push                Use buildx and push to registry (implies buildx)
#   --load                Use buildx and load into local docker (default for buildx)
#   -h, --help            Show this help
# ==============================================================================
set -euo pipefail

CI_SCRIPT_NAME="build"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PROJECT_ROOT="$(ci_project_root)"

usage() {
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

TAG="holyclaude:local"
VARIANT="full"
DOCKERFILE="$PROJECT_ROOT/Dockerfile"
CONTEXT="$PROJECT_ROOT"
NO_CACHE=0
PLATFORM=""
PUSH=0
USE_BUILDX=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag)        TAG="$2"; shift 2 ;;
        --variant)    VARIANT="$2"; shift 2 ;;
        --dockerfile) DOCKERFILE="$2"; shift 2 ;;
        --context)    CONTEXT="$2"; shift 2 ;;
        --no-cache)   NO_CACHE=1; shift ;;
        --platform)   PLATFORM="$2"; USE_BUILDX=1; shift 2 ;;
        --push)       PUSH=1; USE_BUILDX=1; shift ;;
        --load)       USE_BUILDX=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        *) die "Unknown argument: $1 (use --help)" ;;
    esac
done

# Auto-enable buildx when --push is requested.
[[ "$PUSH" == "1" ]] && USE_BUILDX=1

require_cmd docker

case "$VARIANT" in
    full|slim) ;;
    *) die "Invalid --variant '$VARIANT' (expected: full | slim)" ;;
esac

[[ -f "$DOCKERFILE" ]] || die "Dockerfile not found: $DOCKERFILE"
[[ -d "$CONTEXT" ]]   || die "Build context not found: $CONTEXT"

# Build command assembly.
CMD=(docker)
if [[ "$USE_BUILDX" == "1" ]]; then
    CMD+=(buildx build)
    [[ -n "$PLATFORM" ]] && CMD+=(--platform "$PLATFORM")
    if [[ "$PUSH" == "1" ]]; then
        CMD+=(--push)
    else
        CMD+=(--load)
    fi
else
    CMD+=(build)
fi

CMD+=(-f "$DOCKERFILE")
CMD+=(-t "$TAG")
CMD+=(--build-arg "VARIANT=$VARIANT")
[[ "$NO_CACHE" == "1" ]] && CMD+=(--no-cache)
CMD+=("$CONTEXT")

log_step "Building image"
log_dim  "tag:      $TAG"
log_dim  "variant:  $VARIANT"
log_dim  "context:  $CONTEXT"
log_dim  "docker:   $DOCKERFILE"
[[ -n "$PLATFORM" ]] && log_dim "platform: $PLATFORM"
[[ "$NO_CACHE" == "1" ]] && log_dim "no-cache: enabled"
[[ "$PUSH" == "1" ]] && log_dim "push:     enabled"

log_info "Command: ${CMD[*]}"

"${CMD[@]}"
log_info "Build complete: $TAG"
