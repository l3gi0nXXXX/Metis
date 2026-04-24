#!/bin/bash
# install-ripgrep.sh - Cross-platform ripgrep installer for Magic-CLI

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if ripgrep is already installed
check_ripgrep() {
    if command -v rg &> /dev/null; then
        print_success "ripgrep already installed: $(rg --version | head -n1)"
        return 0
    else
        return 1
    fi
}

# Install ripgrep on different platforms
install_ripgrep() {
    local platform=$(uname -s | tr '[:upper:]' '[:lower:]')
    
    case "$platform" in
        "darwin")
            install_macos
            ;;
        "linux")
            install_linux
            ;;
        *)
            print_error "Unsupported platform: $platform"
            print_info "Please install ripgrep manually from: https://github.com/BurntSushi/ripgrep/releases"
            exit 1
            ;;
    esac
}

install_macos() {
    print_info "Installing ripgrep on macOS..."
    
    if command -v brew &> /dev/null; then
        print_info "Using Homebrew to install ripgrep..."
        brew install ripgrep
        print_success "ripgrep installed via Homebrew"
    elif command -v port &> /dev/null; then
        print_info "Using MacPorts to install ripgrep..."
        sudo port install ripgrep
        print_success "ripgrep installed via MacPorts"
    else
        print_warning "Package manager not found. Installing from GitHub releases..."
        install_from_github "apple-darwin" "tar.gz"
    fi
}

install_linux() {
    print_info "Installing ripgrep on Linux..."
    
    # Detect Linux distribution
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO=$ID
    else
        print_warning "Cannot detect Linux distribution"
        DISTRO="unknown"
    fi
    
    case "$DISTRO" in
        "ubuntu"|"debian")
            print_info "Using apt to install ripgrep..."
            sudo apt update && sudo apt install -y ripgrep
            print_success "ripgrep installed via apt"
            ;;
        "fedora"|"rhel"|"centos")
            print_info "Using dnf/yum to install ripgrep..."
            if command -v dnf &> /dev/null; then
                sudo dnf install -y ripgrep
            else
                sudo yum install -y ripgrep
            fi
            print_success "ripgrep installed via dnf/yum"
            ;;
        "arch"|"manjaro")
            print_info "Using pacman to install ripgrep..."
            sudo pacman -S --noconfirm ripgrep
            print_success "ripgrep installed via pacman"
            ;;
        "opensuse"|"suse")
            print_info "Using zypper to install ripgrep..."
            sudo zypper install -y ripgrep
            print_success "ripgrep installed via zypper"
            ;;
        *)
            print_warning "Unsupported Linux distribution: $DISTRO"
            print_info "Trying to install from GitHub releases..."
            install_from_github "unknown-linux-gnu" "tar.gz"
            ;;
    esac
}

install_from_github() {
    local platform_suffix=$1
    local archive_ext=$2
    local arch=$(uname -m)
    
    # Map architecture names
    case "$arch" in
        "x86_64"|"amd64")
            arch="x86_64"
            ;;
        "aarch64"|"arm64")
            arch="aarch64"
            ;;
        *)
            print_error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
    
    local version="14.1.1"  # Latest version as of implementation
    local filename="ripgrep-${version}-${arch}-${platform_suffix}.${archive_ext}"
    local url="https://github.com/BurntSushi/ripgrep/releases/download/${version}/${filename}"
    local temp_dir=$(mktemp -d)
    
    print_info "Downloading ripgrep from GitHub: $filename"
    
    if command -v curl &> /dev/null; then
        curl -L "$url" -o "$temp_dir/$filename"
    elif command -v wget &> /dev/null; then
        wget "$url" -O "$temp_dir/$filename"
    else
        print_error "Neither curl nor wget found. Cannot download ripgrep."
        exit 1
    fi
    
    print_info "Extracting and installing ripgrep..."
    cd "$temp_dir"
    
    if [[ "$archive_ext" == "tar.gz" ]]; then
        tar -xzf "$filename"
        cd ripgrep-${version}-${arch}-${platform_suffix}
    else
        print_error "Unsupported archive format: $archive_ext"
        exit 1
    fi
    
    # Install to /usr/local/bin (requires sudo)
    sudo cp rg /usr/local/bin/
    sudo chmod +x /usr/local/bin/rg
    
    # Clean up
    cd /
    rm -rf "$temp_dir"
    
    print_success "ripgrep installed to /usr/local/bin/rg"
}

# Test ripgrep installation
test_ripgrep() {
    print_info "Testing ripgrep installation..."
    if rg --version > /dev/null 2>&1; then
        print_success "ripgrep is working correctly!"
        print_info "Version: $(rg --version | head -n1)"
        print_info "Magic-CLI will now use ripgrep for 10x+ faster search performance! 🚀"
    else
        print_error "ripgrep installation failed or not working properly"
        exit 1
    fi
}

# Main installation flow
main() {
    echo "🔍 Magic-CLI Ripgrep Installer"
    echo "========================================="
    
    if check_ripgrep; then
        print_info "Magic-CLI is already optimized with ripgrep! 🚀"
        exit 0
    fi
    
    print_info "Installing ripgrep for Magic-CLI performance boost..."
    install_ripgrep
    test_ripgrep
    
    echo ""
    print_success "🎉 Installation complete!"
    print_info "Magic-CLI will now automatically use ripgrep for faster search."
    print_info "No additional configuration needed - just run Magic-CLI as usual!"
}

# Run main function
main "$@"