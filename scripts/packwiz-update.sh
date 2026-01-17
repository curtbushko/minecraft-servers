#!/usr/bin/env bash
# Update all packwiz mods in a server modpack to latest versions
# Checks both exact version (e.g., "1.21.1") and wildcard version (e.g., "1.21.x") on Modrinth
# This handles cases where mods are tagged with either format on Modrinth
#
# Usage: ./scripts/packwiz-update.sh <server-name> [options]
#        ./scripts/packwiz-update.sh --all [options]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Configuration
SERVER_NAME=""
DELAY_SECONDS="${DELAY_SECONDS:-2}"  # Delay between updates to avoid rate limiting
DRY_RUN="${DRY_RUN:-false}"
UPDATE_ALL="${UPDATE_ALL:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

usage() {
    cat << EOF
Usage: $0 <server-name> [options]
       $0 --all [options]

Update all packwiz mods in a server modpack to their latest compatible versions.
Queries Modrinth API to find versions matching both exact (e.g., 1.21.1) and
wildcard (e.g., 1.21.x) Minecraft version tags.

Arguments:
  server-name         Name of the server to update (e.g., dj-server)

Options:
  --all               Update all servers in servers/ directory
  --dry-run           Preview changes without making them
  --delay <seconds>   Delay between updates (default: 2, to avoid rate limits)
  -h, --help          Show this help message

Environment Variables:
  DELAY_SECONDS       Alternative way to set delay (default: 2)
  DRY_RUN             Set to 'true' for dry run mode

Examples:
  $0 dj-server                    # Update all mods in dj-server
  $0 dj-server --dry-run          # Preview changes without making them
  $0 --all --delay 5              # Update all servers with 5s delay
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

# Check dependencies
check_dependencies() {
    local missing=0

    if ! command -v packwiz &> /dev/null; then
        log_error "packwiz is not installed"
        echo "Install it with: go install github.com/packwiz/packwiz@latest" >&2
        missing=1
    fi

    if ! command -v curl &> /dev/null; then
        log_error "curl is not installed"
        missing=1
    fi

    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed (needed for Modrinth API queries)"
        missing=1
    fi

    if [ $missing -ne 0 ]; then
        exit 1
    fi
}

# Function to get the latest version for a mod checking both exact and wildcard MC versions
get_latest_mod_version() {
    local mod_id="$1"
    local exact_version="$2"
    local wildcard_version="$3"
    local loader="$4"

    # Query Modrinth API for all versions of this mod
    local api_response=$(curl -s "https://api.modrinth.com/v2/project/${mod_id}/version")

    # Find the latest version that matches our criteria
    # Check for versions supporting either exact version OR wildcard version
    local latest=$(echo "$api_response" | jq -r --arg exact "$exact_version" --arg wildcard "$wildcard_version" --arg loader "$loader" '
        [.[] |
         select(.loaders[] | contains($loader)) |
         select(.game_versions[] | (. == $exact or . == $wildcard)) |
         {
           id: .id,
           version_number: .version_number,
           date_published: .date_published,
           filename: .files[0].filename,
           game_versions: .game_versions
         }
        ] |
        sort_by(.date_published) |
        last')

    if [ "$latest" != "null" ] && [ -n "$latest" ]; then
        echo "$latest"
        return 0
    else
        return 1
    fi
}

update_server() {
    local server="$1"
    local server_dir="$REPO_ROOT/servers/$server"

    if [[ ! -d "$server_dir" ]]; then
        log_error "Server directory not found: $server_dir"
        return 1
    fi

    if [[ ! -f "$server_dir/pack.toml" ]]; then
        log_error "pack.toml not found in $server_dir"
        return 1
    fi

    cd "$server_dir"

    # Get Minecraft version from pack.toml and derive wildcard version
    local MC_VERSION=$(grep '^minecraft = ' pack.toml | cut -d'"' -f2)
    # Convert 1.21.1 to 1.21.x by replacing the patch version with 'x'
    local MC_VERSION_WILDCARD=$(echo "$MC_VERSION" | sed -E 's/\.[0-9]+$/\.x/')

    echo -e "${BLUE}=====================================${NC}"
    echo -e "${BLUE}Updating: $server${NC}"
    echo -e "${BLUE}=====================================${NC}"
    echo -e "Path: $server_dir"
    echo -e "${BLUE}Minecraft version: ${YELLOW}$MC_VERSION${NC}"
    echo -e "${BLUE}Also checking for: ${YELLOW}$MC_VERSION_WILDCARD${NC}"
    echo ""

    # Get loader type
    local LOADER="neoforge"
    if ! grep -q '^neoforge = ' pack.toml; then
        if grep -q '^fabric = ' pack.toml; then
            LOADER="fabric"
        elif grep -q '^forge = ' pack.toml; then
            LOADER="forge"
        elif grep -q '^quilt = ' pack.toml; then
            LOADER="quilt"
        fi
    fi
    echo -e "${BLUE}Mod loader: ${YELLOW}$LOADER${NC}"
    echo ""

    # Refresh packwiz index to pick up any pack.toml changes
    log_info "Refreshing packwiz index..."
    if ! packwiz refresh 2>&1 | grep -v "^$"; then
        log_warn "packwiz refresh had issues, but continuing..."
    fi
    echo ""

    # Get all .pw.toml files
    if [[ ! -d "mods" ]]; then
        log_warn "No mods directory found in $server_dir"
        return 0
    fi

    local mod_files=$(find mods -name "*.pw.toml" -type f | sort)
    local total_mods=$(echo "$mod_files" | wc -l)

    echo -e "Total mods to update: $total_mods"
    echo -e "Delay between updates: ${DELAY_SECONDS}s"
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "${YELLOW}DRY RUN MODE - No changes will be made${NC}"
    fi
    echo ""

    # Counters
    local success_count=0
    local error_count=0
    local skip_count=0
    local old_version_count=0
    local current=0

    # Track mods stuck on old versions
    declare -a old_version_mods

    # Update each mod
    for mod_file in $mod_files; do
        current=$((current + 1))
        local mod_name=$(basename "$mod_file" .pw.toml)

        echo -e "${BLUE}[$current/$total_mods]${NC} Updating ${YELLOW}$mod_name${NC}..."

        if [ "$DRY_RUN" = "true" ]; then
            echo -e "  ${YELLOW}[DRY RUN]${NC} Would run: packwiz update $mod_name"
            skip_count=$((skip_count + 1))
        else
            # Get current version before update
            local old_version=""
            local current_version_id=""
            local mod_id=""
            if [ -f "$mod_file" ]; then
                old_version=$(grep '^filename = ' "$mod_file" | cut -d'"' -f2 | head -1)
                # Extract Modrinth mod ID from [update.modrinth] section
                mod_id=$(grep -A 2 '^\[update\.modrinth\]' "$mod_file" | grep '^mod-id = ' | cut -d'"' -f2)
                current_version_id=$(grep -A 2 '^\[update\.modrinth\]' "$mod_file" | grep '^version = ' | cut -d'"' -f2)
            fi

            # Try to find latest version using Modrinth API (checking both exact and wildcard versions)
            local latest_version_info=""
            if [ -n "$mod_id" ]; then
                latest_version_info=$(get_latest_mod_version "$mod_id" "$MC_VERSION" "$MC_VERSION_WILDCARD" "$LOADER" 2>/dev/null || echo "")
            fi

            # Determine which update method to use
            local update_cmd="packwiz update \"$mod_name\""
            local use_api_version=false
            if [ -n "$latest_version_info" ]; then
                local latest_version_id=$(echo "$latest_version_info" | jq -r '.id')
                local latest_filename=$(echo "$latest_version_info" | jq -r '.filename')

                # Only use specific version if it's different from current
                if [ -n "$latest_version_id" ] && [ "$latest_version_id" != "null" ] && [ "$latest_version_id" != "$current_version_id" ]; then
                    update_cmd="packwiz modrinth install --project-id \"$mod_id\" --version-id \"$latest_version_id\" -y"
                    use_api_version=true
                    echo -e "  ${BLUE}→${NC} Found newer version via API: $latest_filename"
                fi
            fi

            # Run packwiz update and capture output
            if output=$(eval "$update_cmd" 2>&1); then
                # Get new version after update
                local new_version=""
                if [ -f "$mod_file" ]; then
                    new_version=$(grep '^filename = ' "$mod_file" | cut -d'"' -f2 | head -1)
                fi

                # Check if version changed
                if [ "$old_version" = "$new_version" ]; then
                    # Check if it's still on an old Minecraft version (before target version)
                    local mc_major_minor=$(echo "$MC_VERSION" | cut -d'.' -f1,2)
                    if echo "$new_version" | grep -qE "1\.($(seq -s '|' 0 $((${mc_major_minor#*.} - 1)))|$(echo $mc_major_minor | cut -d'.' -f1)\.([0-9]|1[0-9]))"; then
                        echo -e "  ${YELLOW}⚠${NC}  No $MC_VERSION version available - still on ${BLUE}($new_version)${NC}"
                        old_version_mods+=("$mod_name: $new_version")
                        old_version_count=$((old_version_count + 1))
                    else
                        echo -e "  ${GREEN}✓${NC} Already up to date ${BLUE}($new_version)${NC}"
                    fi
                    success_count=$((success_count + 1))
                else
                    echo -e "  ${GREEN}✓${NC} Updated successfully"
                    echo -e "    ${YELLOW}Old:${NC} $old_version"
                    echo -e "    ${GREEN}New:${NC} $new_version"
                    success_count=$((success_count + 1))
                fi
            else
                echo -e "  ${RED}✗${NC} Error updating $mod_name"
                echo -e "  ${RED}Error:${NC} $output"
                error_count=$((error_count + 1))
            fi

            # Delay to avoid rate limiting (except for last mod)
            if [ $current -lt $total_mods ]; then
                sleep "$DELAY_SECONDS"
            fi
        fi
    done

    # Summary
    echo ""
    echo -e "${BLUE}=====================================${NC}"
    echo -e "${BLUE}Update Summary for $server${NC}"
    echo -e "${BLUE}=====================================${NC}"
    echo -e "Total mods: $total_mods"
    if [ "$DRY_RUN" = "true" ]; then
        echo -e "${YELLOW}Dry run - no changes made${NC}"
    else
        echo -e "${GREEN}Successful: $success_count${NC}"
        echo -e "${RED}Failed: $error_count${NC}"
        if [ "$old_version_count" -gt 0 ]; then
            echo -e "${YELLOW}Stuck on old MC versions: $old_version_count${NC}"
        fi
    fi
    echo ""

    if [ "$old_version_count" -gt 0 ]; then
        echo -e "${YELLOW}=====================================${NC}"
        echo -e "${YELLOW}Mods Not Yet Updated to $MC_VERSION${NC}"
        echo -e "${YELLOW}=====================================${NC}"
        for mod_info in "${old_version_mods[@]}"; do
            echo -e "  ${YELLOW}⚠${NC}  $mod_info"
        done
        echo ""
        echo -e "${YELLOW}These mods may not have $MC_VERSION versions yet.${NC}"
        echo -e "${YELLOW}Check Modrinth or consider alternative mods.${NC}"
        echo ""
    fi

    if [ "$error_count" -gt 0 ]; then
        echo -e "${YELLOW}Some mods failed to update. You may need to:${NC}"
        echo -e "  - Check the Modrinth page for those mods"
        echo -e "  - Increase DELAY_SECONDS if hitting rate limits"
        echo -e "  - Manually update problem mods"
        return 1
    fi

    if [ "$old_version_count" -eq 0 ]; then
        log_success "All mods updated successfully to $MC_VERSION!"
    else
        log_success "Update complete! ($old_version_count mods still on older MC versions)"
    fi

    return 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --all)
            UPDATE_ALL=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --delay)
            DELAY_SECONDS="$2"
            shift 2
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

# Check dependencies
check_dependencies

# Main execution
if [[ "$UPDATE_ALL" == "true" ]]; then
    log_info "Updating all servers..."
    echo ""

    errors=0
    for server_dir in "$REPO_ROOT/servers"/*/; do
        if [[ -d "$server_dir" ]]; then
            server=$(basename "$server_dir")
            if ! update_server "$server"; then
                errors=$((errors + 1))
            fi
            echo ""
        fi
    done

    if [[ $errors -gt 0 ]]; then
        log_error "$errors server(s) had update errors"
        exit 1
    fi

    log_success "All servers updated!"

elif [[ -n "$SERVER_NAME" ]]; then
    update_server "$SERVER_NAME"
else
    log_error "No server specified"
    echo ""
    usage
    exit 1
fi
