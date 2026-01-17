#!/usr/bin/env bash
set -euo pipefail

# Build Docker image(s) for Minecraft server(s)
# Usage: ./scripts/build.sh <server-name> [options]
#        ./scripts/build.sh --all [options]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Defaults
SERVER_NAME=""
TAG="${TAG:-latest}"
PUSH="${PUSH:-false}"
BUILD_ALL="${BUILD_ALL:-false}"
NO_CACHE="${NO_CACHE:-false}"

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

Build Docker images for Minecraft servers.

Arguments:
  server-name         Name of the server to build (e.g., dj-server)

Options:
  --all               Build all servers in servers/ directory
  --tag <tag>         Docker image tag (default: latest)
  --push              Push image to registry after building
  --no-cache          Build without Docker cache
  -h, --help          Show this help message

Environment Variables:
  TAG                 Alternative way to set image tag
  PUSH                Set to 'true' to push after build
  PACKWIZ_BASE_URL    Override base URL for packwiz (default: https://curtbushko.github.io/minecraft-servers)

Examples:
  $0 dj-server                    # Build dj-server with 'latest' tag
  $0 dj-server --tag v1.0.0       # Build with specific tag
  $0 dj-server --push             # Build and push to registry
  $0 --all --tag v1.0.0 --push    # Build and push all servers
EOF
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

build_server() {
    local server="$1"
    local server_dir="$REPO_ROOT/servers/$server"

    if [[ ! -d "$server_dir" ]]; then
        log_error "Server directory not found: $server_dir"
        return 1
    fi

    if [[ ! -f "$server_dir/Dockerfile" ]]; then
        log_error "Dockerfile not found in $server_dir"
        return 1
    fi

    # Source server config if it exists
    local image_name="ghcr.io/curtbushko/minecraft-servers/$server"
    local packwiz_base_url="${PACKWIZ_BASE_URL:-https://curtbushko.github.io/minecraft-servers}"

    if [[ -f "$server_dir/server.env" ]]; then
        # shellcheck source=/dev/null
        source "$server_dir/server.env"
        image_name="${IMAGE_NAME:-$image_name}"
        packwiz_base_url="${PACKWIZ_BASE_URL:-$packwiz_base_url}"
    fi

    local packwiz_url="$packwiz_base_url/$server/pack.toml"

    log_info "Building $server..."
    echo "  Image:       $image_name:$TAG"
    echo "  Packwiz URL: $packwiz_url"
    echo ""

    local cache_arg=""
    if [[ "$NO_CACHE" == "true" ]]; then
        cache_arg="--no-cache"
    fi

    docker build \
        $cache_arg \
        --build-arg PACKWIZ_URL="$packwiz_url" \
        --tag "$image_name:$TAG" \
        --file "$server_dir/Dockerfile" \
        "$server_dir"

    # Also tag as latest if not already
    if [[ "$TAG" != "latest" ]]; then
        docker tag "$image_name:$TAG" "$image_name:latest"
    fi

    log_success "Built $image_name:$TAG"

    if [[ "$PUSH" == "true" ]]; then
        log_info "Pushing $image_name:$TAG..."
        docker push "$image_name:$TAG"
        if [[ "$TAG" != "latest" ]]; then
            docker push "$image_name:latest"
        fi
        log_success "Pushed $image_name:$TAG"
    fi

    echo ""
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --tag)
            TAG="$2"
            shift 2
            ;;
        --push)
            PUSH=true
            shift
            ;;
        --all)
            BUILD_ALL=true
            shift
            ;;
        --no-cache)
            NO_CACHE=true
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
if [[ "$BUILD_ALL" == "true" ]]; then
    log_info "Building all servers..."
    echo ""

    found_servers=0
    for server_dir in "$REPO_ROOT/servers"/*/; do
        if [[ -d "$server_dir" ]]; then
            server=$(basename "$server_dir")
            build_server "$server"
            ((found_servers++))
        fi
    done

    if [[ $found_servers -eq 0 ]]; then
        log_warn "No servers found in $REPO_ROOT/servers/"
        exit 1
    fi

    log_success "Built $found_servers server(s)"

elif [[ -n "$SERVER_NAME" ]]; then
    build_server "$SERVER_NAME"
else
    log_error "No server specified"
    echo ""
    usage
    exit 1
fi
