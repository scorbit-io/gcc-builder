#!/bin/bash
# Update CMake toolchain files with dependency paths
# Usage: update-cmake-toolchains.sh <toolchain_dir> [arch_name]

set -e

TOOLCHAIN_DIR="${1:-/opt/toolchain}"
ARCH_FILTER="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../platforms.conf"

mkdir -p "$TOOLCHAIN_DIR"

# Read all platforms from config and update CMake files
while IFS='|' read -r arch target sysroot platform base_image builder_base_image cmake_proc cmake_flags rest; do
    # Skip comments and empty lines
    [[ "$arch" =~ ^#.*$ ]] && continue
    [ -z "$arch" ] && continue
    [ -n "$ARCH_FILTER" ] && [ "$arch" != "$ARCH_FILTER" ] && continue
    
    CMAKE_FILE="${TOOLCHAIN_DIR}/${arch}.cmake"
    
    # Append dependency paths to each toolchain file
    cat >> "$CMAKE_FILE" <<EOF

# Add dependency installation paths
list(APPEND CMAKE_PREFIX_PATH /opt/deps-$arch)
list(APPEND CMAKE_FIND_ROOT_PATH /opt/deps-$arch)
set(ENV{PKG_CONFIG_PATH} "/opt/deps-$arch/lib/pkgconfig")
EOF
    
done < "$CONFIG_FILE"

echo "CMake toolchain files updated with dependency paths in $TOOLCHAIN_DIR"

