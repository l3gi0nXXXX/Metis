#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

print_header() {
    echo -e "${WHITE}================================${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${WHITE}================================${NC}"
}


get_platform() {
    # 获取操作系统
    local os=$(uname -s | tr '[:upper:]' '[:lower:]')
    case "$os" in
        darwin*)    os="macos" ;;
        linux*)     os="linux" ;;
        msys*|cygwin*|mingw*) os="windows" ;;
        freebsd*)   os="freebsd" ;;
        *)          os="unknown" ;;
    esac

    # 获取架构
    local arch=$(uname -m)
    case "$arch" in
        x86_64|x64)     arch="x86_64" ;;
        aarch64|arm64)  arch="aarch64" ;;
        armv7l)         arch="armv7" ;;
        armv6l)         arch="armv6" ;;
        i386|i686)      arch="x86" ;;
        *)              arch="$arch" ;;
    esac

    local platform="${os}-${arch}"
    echo "$platform"
}

# Display script header
print_header "🚀 Magic CLI Release Script"

PLATFORM=$(get_platform)

# Configuration
OWNER=<username>
REPO=<repo-name>
TAG="v0.0.1-${PLATFORM}"
ACCESS_TOKEN=<gitcode-access-token>
RELEASE_NAME=$TAG
RELEASE_BODY="Release $TAG"

# Display configuration
print_info "Configuration:"
echo -e "  ${GRAY}Owner:${NC} ${CYAN}${OWNER}${NC}"
echo -e "  ${GRAY}Repository:${NC} ${CYAN}${REPO}${NC}"
echo -e "  ${GRAY}Tag:${NC} ${CYAN}${TAG}${NC}"
echo -e "  ${GRAY}Platform:${NC} ${CYAN}${PLATFORM}${NC}"
echo -e "  ${GRAY}Release Name:${NC} ${CYAN}${RELEASE_NAME}${NC}"
echo ""

Step 1: Build magic-cli
print_step "Step 1: Building magic-cli for ${CYAN}${PLATFORM}${NC}"
echo ""

if bash "$SCRIPT_DIR/../build-static/build-magic-cli.sh"; then
    print_success "Build completed successfully!"
else
    print_error "Build failed!"
    exit 1
fi

echo ""

# Function to create release
create_release() {
    python3 "$SCRIPT_DIR/gitcode.py" release \
        --owner "$OWNER" \
        --repo "$REPO" \
        --tag "$TAG" \
        --access-token "$ACCESS_TOKEN" \
        --release-name "$RELEASE_NAME" \
        --release-body "$RELEASE_BODY"
}

# Step 2: Create release
print_step "Step 2: Creating release ${CYAN}${TAG}${NC} for ${CYAN}${PLATFORM}${NC}"
echo ""

# Store release output to check for tag exists error
release_output=$(create_release 2>&1)
release_exit_code=$?

# Check if release failed due to tag already exists
if [ $release_exit_code -ne 0 ]; then
    if echo "$release_output" | grep -q "tag already exists"; then
        print_warning "Tag ${TAG} already exists. Deleting existing tag and retrying..."
        echo ""

        # Delete the existing tag
        print_step "Deleting existing tag ${CYAN}${TAG}${NC}"
        python3 "$SCRIPT_DIR/gitcode.py" delete-tag \
            --owner "$OWNER" \
            --repo "$REPO" \
            --tag "$TAG" \
            --access-token "$ACCESS_TOKEN"

        if [ $? -eq 0 ]; then
            print_success "Tag deleted successfully!"
            echo ""

            # Retry creating the release using the same function
            print_step "Retrying release creation for ${CYAN}${TAG}${NC}"
            echo ""

            create_release
            if [ $? -ne 0 ]; then
                print_error "Failed to create release ${TAG} for ${PLATFORM} after tag deletion"
                echo "$release_output"
                exit 1
            fi
        else
            print_error "Failed to delete existing tag ${TAG}"
            echo "$release_output"
            exit 1
        fi
    else
        print_error "Failed to create release ${TAG} for ${PLATFORM}"
        echo "$release_output"
        exit 1
    fi
fi

print_success "Release created successfully!"
echo ""

# Step 3: Upload binary
print_step "Step 3: Uploading binary for ${CYAN}${PLATFORM}${NC}"
echo ""

python3 "$SCRIPT_DIR/gitcode.py" upload \
    --owner "$OWNER" \
    --repo "$REPO" \
    --tag "$TAG" \
    --access-token "$ACCESS_TOKEN" \
    ./binary/magic-cli \
    --remote-name "magic-cli-$PLATFORM"

if [ $? -eq 0 ]; then
    print_success "Binary uploaded successfully!"
    echo ""
    print_header "✅ Release Process Completed!"
    echo -e "${GREEN}🎉 Magic CLI ${TAG} has been released for ${PLATFORM}!${NC}"
    echo -e "${GRAY}Binary name: magic-cli-${PLATFORM}${NC}"
else
    print_error "Binary upload failed!"
    exit 1
fi