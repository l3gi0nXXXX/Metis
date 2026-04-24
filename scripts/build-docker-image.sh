#!/bin/bash
# Magic-CLI Service Build Script

set -e

# Configuration
IMAGE_TAG="latest"
IMAGE_NAME="magic-cli"
MAGIC_CLI_HOME="."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command_exists docker; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi

    if ! command_exists docker-compose; then
        log_error "Docker Compose is not installed or not in PATH"
        exit 1
    fi

    # Check if Docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running"
        exit 1
    fi

    log_info "Prerequisites check passed"
}

# Function to build Magic-CLI image
build_image() {
    log_info "Building Magic-CLI container image..."

    # Check if required environment variables are set
    if [ -z "$CANGJIE_HOME" ]; then
        log_error "CANGJIE_HOME environment variable not set. Please set it to the CangjieSDK source path."
        exit 1
    fi

    # Check if CangjieSDK envsetup.sh exists
    if [ ! -f "$CANGJIE_HOME/envsetup.sh" ]; then
        log_error "CangjieSDK envsetup.sh not found at $CANGJIE_HOME/envsetup.sh"
        exit 1
    fi

    # Check if files exist in docker build context
    log_info "Checking Docker build context files..."

    # Copy Magic-CLI binary to Docker context
    # Create docker/magic-cli directory if it doesn't exist
    if [ ! -f "docker/magic-cli/magic-cli" ]; then
        log_info "Copying Magic-CLI binary to Docker build context..."

        if [ ! -f "$MAGIC_CLI_HOME/binary/magic-cli" ]; then
            log_info "Magic-CLI binary not found, building..."
            ./script/build-magic-cli.sh
        fi

        cp "$MAGIC_CLI_HOME/binary/magic-cli" docker/magic-cli/
        if [ $? -eq 0 ]; then
            log_info "✓ Magic-CLI binary copied successfully"
        else
            log_error "Failed to copy Magic-CLI binary"
            exit 1
        fi
    else
        log_info "✓ Magic-CLI binary already exists in Docker context"
    fi

    # Copy CangjieSDK to Docker context
    if [ ! -f "docker/magic-cli/CangjieSDK/envsetup.sh" ]; then
        log_info "Copying CangjieSDK to Docker build context..."
        mkdir -p docker/magic-cli/CangjieSDK
        cp -r "$CANGJIE_HOME"/* docker/magic-cli/CangjieSDK/
        if [ $? -eq 0 ]; then
            log_info "✓ CangjieSDK copied successfully"
        else
            log_error "Failed to copy CangjieSDK"
            exit 1
        fi
    else
        log_info "✓ CangjieSDK already exists in Docker context"
    fi

    # Verify Docker context files
    if [ ! -f "docker/magic-cli/magic-cli" ]; then
        log_error "Magic-CLI binary not found in Docker context"
        exit 1
    fi

    if [ ! -f "docker/magic-cli/CangjieSDK/envsetup.sh" ]; then
        log_error "CangjieSDK envsetup.sh not found in Docker context"
        exit 1
    fi

    log_info "Docker context files verified successfully"
    log_info "Docker context structure:"
    ls -la docker/magic-cli/

    cd docker/magic-cli
    docker build \
        --platform=linux/amd64 \
        -t "${IMAGE_NAME}:${IMAGE_TAG}" \
        .
    cd ../..

    if [ $? -eq 0 ]; then
        log_info "Magic-CLI image built successfully"
    else
        log_error "Failed to build Magic-CLI image"
        exit 1
    fi
}

# Function to show built images
show_images() {
    log_info "Built Docker images:"
    docker images | grep -E "(magic-cli|${IMAGE_NAME})"
}

# Function to cleanup
cleanup() {
    log_info "Cleaning up temporary files..."

    # Optional: Clean up Docker context files to save space
    # Comment out if you want to keep these files for debugging
    if [ -d "docker/magic-cli/magic-cli" ]; then
        log_info "Cleaning up Docker context files..."
        rm -rf docker/magic-cli/magic-cli
    fi

    if [ -d "docker/magic-cli/CangjieSDK" ]; then
        rm -rf docker/magic-cli/CangjieSDK
    fi

    log_info "Cleanup completed"
}

# Main build function
main() {
    log_info "Starting build process..."
    log_info "Image name: ${IMAGE_NAME}"
    log_info "Image tag: ${IMAGE_TAG}"

    check_prerequisites
    build_image
    show_images
    # cleanup
    log_info "Build process completed successfully!"
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [--help]"
        echo
        echo "Options:"
        echo "  --help, -h        Show this help message"
        echo
        echo "Required environment variables for Magic-CLI build:"
        echo "  CANGJIE_HOME      Path to CangjieSDK directory"
        echo
        echo "  $0"
        exit 0
        ;;
    *)
        main
        ;;
esac