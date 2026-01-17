#!/usr/bin/env bash
set -euo pipefail

# Push Docker image(s) for Minecraft server(s) to registry
# Usage: ./scripts/push.sh <server-name> [options]
#        ./scripts/push.sh --all [options]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Defaults
SERVER_NAME=""
TAG="${TAG:-latest}"
PUSH_ALL="${PUSH_ALL:-false}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    cat << EOF
Usage: $0 <server-name> [options]
       $0 --all [options]

Push Docker images for Minecraft servers to ghcr.io.

Arguments:
  server-name         Name of the server to push (e.g., dj-server)

Options:
  --all               Push all servers in servers/ directory
  --tag <tag>         Docker image tag to push (default: latest)
  -h, --help          Show this help message

Prerequisites:
  - Docker must be logged into ghcr.io:
    echo \$GITHUB_TOKEN | docker login ghcr.io -u \$GITHUB_USER --password-stdin

Examples:
  $0 dj-server                    # Push dj-server:latest
  $0 dj-server --tag v1.0.0       # Push specific tag
  $0 --all                        # Push all servers
EOF
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

push_server() {
    local server="$1"
    local server_dir="$REPO_ROOT/servers/$server"

    if [[ ! -d "$server_dir" ]]; then
        log_error "Server directory not found: $server_dir"
        return 1
    fi

    # Source server config if it exists
    local image_name="ghcr.io/curtbushko/minecraft-servers/$server"

    if [[ -f "$server_dir/server.env" ]]; then
        # shellcheck source=/dev/null
        source "$server_dir/server.env"
        image_name="${IMAGE_NAME:-$image_name}"
    fi

    log_info "Pushing $image_name:$TAG..."

    # Check if image exists locally
    if ! docker image inspect "$image_name:$TAG" &>/dev/null; then
        log_error "Image $image_name:$TAG not found locally. Run build.sh first."
        return 1
    fi

    docker push "$image_name:$TAG"

    # Also push latest if pushing a versioned tag
    if [[ "$TAG" != "latest" ]]; then
        if docker image inspect "$image_name:latest" &>/dev/null; then
            docker push "$image_name:latest"
        fi
    fi

    log_success "Pushed $image_name:$TAG"
    echo ""
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --tag)
            TAG="$2"
            shift 2
            ;;
        --all)
            PUSH_ALL=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
        *)
            if [[ -z "$SERVER_NAME" ]]; then
                SERVER_NAME="$1"
            else
                log_error "Unexpected argument: $1"
                usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Main execution
if [[ "$PUSH_ALL" == "true" ]]; then
    log_info "Pushing all servers..."
    echo ""

    for server_dir in "$REPO_ROOT/servers"/*/; do
        if [[ -d "$server_dir" ]]; then
            server=$(basename "$server_dir")
            push_server "$server" || true
        fi
    done

    log_success "Push complete"

elif [[ -n "$SERVER_NAME" ]]; then
    push_server "$SERVER_NAME"
else
    log_error "No server specified"
    echo ""
    usage
    exit 1
fi
