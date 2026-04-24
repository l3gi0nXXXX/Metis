#!/bin/bash

OS="$(uname -s)"

# Load Cangjie runtime libs
if [ -z "${CANGJIE_HOME+x}" ]; then
    echo "Error: CANGJIE_HOME is not set!" >&2
    exit 1
fi
. $CANGJIE_HOME/envsetup.sh

# Set the Cangjie stdx libs according to the Magic project
if [ -z "${MAGIC_PATH+x}" ]; then
    echo "Error: MAGIC_PATH is not set!" >&2
    exit 1
fi
STDX_LIB_PATH=$(find "${MAGIC_PATH:-}" -type d -path '*/dynamic/stdx' -print -quit 2>/dev/null)

# Get the absolute path of the script's directory (resolves symlinks)
SCRIPT_DIR=$(dirname "$(realpath "$0" 2>/dev/null || readlink -f "$0" 2>/dev/null || echo "$0")")

# Set libs of this project and Magic according to "../target" relative to the script's location
CLI_LIB_PATH="$SCRIPT_DIR/../target/release/metis:$SCRIPT_DIR/../ffi"
MAGIC_LIB_PATH="$SCRIPT_DIR/../target/release/magic"

# Merge all lib paths
LIB_PATHS="$CLI_LIB_PATH:$MAGIC_LIB_PATH:$STDX_LIB_PATH"

append_if_dir() {
    local dir="$1"
    if [[ -n "$dir" && -d "$dir" ]]; then
        LIB_PATHS="$LIB_PATHS:$dir"
    fi
}

# Path to the executable CLI binary ("../target/bin/metis" relative to the script)
CLI_BIN="$SCRIPT_DIR/../target/release/bin/metis"
# Check if the executable exists before running
if [[ ! -f "$CLI_BIN" ]]; then
    echo "Error: Executable not found at $CLI_BIN" >&2
    exit 1
fi

# Add the library path to `LD_LIBRARY_PATH` (for Linux) and `DYLD_LIBRARY_PATH` (for macOS)
case "$OS" in
    "Linux")
        export LD_LIBRARY_PATH="$LIB_PATHS:$LD_LIBRARY_PATH"
        ;;
    "Darwin")
        # stdx loads OpenSSL at runtime by library name (for example `libssl.3.dylib`),
        # so Homebrew's OpenSSL lib directory must be visible to dyld.
        append_if_dir "/opt/homebrew/opt/openssl@3/lib"
        append_if_dir "/opt/homebrew/opt/openssl@3.5/lib"
        append_if_dir "/usr/local/opt/openssl@3/lib"
        export DYLD_LIBRARY_PATH="$LIB_PATHS:$DYLD_LIBRARY_PATH"  # macOS support
        # xattr -dr com.apple.quarantine ${script_dir}/* &> /dev/null || true
        codesign -s - -f --preserve-metadata=entitlements,requirements,flags,runtime $CLI_BIN &> /dev/null || true
        ;;
    *)
        echo "Unknown/Unsupported OS: $OS"
        ;;
esac

# Execute the CLI binary and forward all arguments (`$@`)
exec "$CLI_BIN" "$@"
