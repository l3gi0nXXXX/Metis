#!/bin/bash

# Build script for Magic CLI with static configuration
# This script builds the project using static toml files and restores original configuration

# Note: We don't use 'set -e' because we need to ensure files are restored on any error

# Color variables for better output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly NC='\033[0m' # No Color

# Formatting functions
info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}" >&2
}

step() {
    echo -e "${BLUE}🚀 $1${NC}"
}

complete() {
    echo -e "${GREEN}🎉 $1${NC}"
}

header() {
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}  $1${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════╝${NC}"
}

# Load Cangjie runtime libs
if [ -z "${CANGJIE_HOME+x}" ]; then
    error "CANGJIE_HOME is not set!"
    exit 1
fi
. $CANGJIE_HOME/envsetup.sh

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$ROOT_DIR/scripts/build_lock.sh"

# Define paths
MAGIC_PATH="$MAGIC_PATH"  # Expected to be set in environment
TARGET_DIR="./target/release/bin"
BINARY_DIR="./binary"
ORIGINAL_MAGIC_CJPM="$MAGIC_PATH/cjpm.toml"
ORIGINAL_LOCAL_CJPM="./cjpm.toml"
BACKUP_MAGIC_CJPM="$MAGIC_PATH/cjpm.toml.backup"
BACKUP_LOCAL_CJPM="./cjpm.toml.backup"

# Function to restore original files
restore_files() {
    info "Restoring original cjpm.toml files..."

    # Restore MAGIC_PATH/cjpm.toml if backup exists
    if [ -f "$BACKUP_MAGIC_CJPM" ]; then
        mv "$BACKUP_MAGIC_CJPM" "$ORIGINAL_MAGIC_CJPM"
        success "Restored $ORIGINAL_MAGIC_CJPM"
    fi

    # Restore local cjpm.toml if backup exists
    if [ -f "$BACKUP_LOCAL_CJPM" ]; then
        mv "$BACKUP_LOCAL_CJPM" "$ORIGINAL_LOCAL_CJPM"
        success "Restored $ORIGINAL_LOCAL_CJPM"
    fi
}

# Function to handle errors
error_handler() {
    local line_number=$1
    error "Error occurred at line $line_number"
    restore_files
    exit 1
}

# Function to run commands with error handling
run_command() {
    if ! "$@"; then
        error_handler $LINENO
    fi
}

# Check if MAGIC_PATH is set
if [ -z "$MAGIC_PATH" ]; then
    error "MAGIC_PATH environment variable is not set"
    error_handler $LINENO
fi

# Check if required files exist
if [ ! -f "$SCRIPT_DIR/magic-static.toml" ]; then
    error "$SCRIPT_DIR/magic-static.toml not found"
    error_handler $LINENO
fi

if [ ! -f "$SCRIPT_DIR/cli-static.toml" ]; then
    error "$SCRIPT_DIR/cli-static.toml not found"
    error_handler $LINENO
fi

header "Starting Magic CLI Build Process"
echo ""
info "Script directory: $SCRIPT_DIR"
info "Magic path: $MAGIC_PATH"
echo ""

# Step 1: Backup original MAGIC_PATH/cjpm.toml and copy static version
step "Step 1: Setting up static configuration for $MAGIC_PATH/cjpm.toml"
if [ -f "$ORIGINAL_MAGIC_CJPM" ]; then
    cp "$ORIGINAL_MAGIC_CJPM" "$BACKUP_MAGIC_CJPM"
    success "Backed up $ORIGINAL_MAGIC_CJPM to $BACKUP_MAGIC_CJPM"
fi
cp "$SCRIPT_DIR/magic-static.toml" "$ORIGINAL_MAGIC_CJPM"
success "Copied $SCRIPT_DIR/magic-static.toml to $ORIGINAL_MAGIC_CJPM"
echo ""

# Step 2: Backup original local cjpm.toml and copy static version
step "Step 2: Setting up static configuration for local cjpm.toml"
if [ -f "$ORIGINAL_LOCAL_CJPM" ]; then
    cp "$ORIGINAL_LOCAL_CJPM" "$BACKUP_LOCAL_CJPM"
    success "Backed up $ORIGINAL_LOCAL_CJPM to $BACKUP_LOCAL_CJPM"
fi
cp "$SCRIPT_DIR/cli-static.toml" "$ORIGINAL_LOCAL_CJPM"
success "Copied $SCRIPT_DIR/cli-static.toml to $ORIGINAL_LOCAL_CJPM"
echo ""

# Step 3: Clean up ffi directory and build
step "Step 3.1: Cleaning up ffi directory..."
if [ -d "./ffi" ]; then
    info "Removing .a, .so, and .dylib files from ./ffi directory..."
    find ./ffi -name "*.a" -type f -delete
    find ./ffi -name "*.so" -type f -delete
    find ./ffi -name "*.dylib" -type f -delete
    success "Cleanup completed"
else
    warning "./ffi directory not found, skipping cleanup"
fi
echo ""

step "Step 3.2: Cleaning up existing project..."
with_metis_cjpm_build_lock bash -lc 'cjpm clean >/dev/null 2>&1'
echo ""

step "Step 3.3: Building project with static configuration..."
with_metis_cjpm_build_lock bash -lc 'cjpm build 2>/dev/null'
echo ""

# Step 4: Copy binary to target location
step "Step 4: Copying binary..."
if [ ! -d "$BINARY_DIR" ]; then
    mkdir -p "$BINARY_DIR"
    success "Created directory: $BINARY_DIR"
fi

if [ -f "$TARGET_DIR/metis" ]; then
    cp "$TARGET_DIR/metis" "$BINARY_DIR/magic-cli"
    success "Copied $TARGET_DIR/metis to $BINARY_DIR/magic-cli"
else
    error "Binary not found at $TARGET_DIR/metis"
    restore_files
    exit 1
fi
echo ""

# Step 5: Restore original files
step "Step 5: Cleaning up and restoring original files..."
restore_files
echo ""

complete "Build completed successfully!"
success "Binary available at: $BINARY_DIR/magic-cli"
