#!/bin/bash
# Generate CMake toolchain files for all (or a specific) architecture
# Usage: generate-cmake-toolchains.sh <toolchain_dir> [arch_name]

set -e

TOOLCHAIN_DIR="${1:-/opt/toolchain}"
ARCH_FILTER="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../platforms.conf"

mkdir -p "$TOOLCHAIN_DIR"

# Read all platforms from config and generate CMake files
while IFS='|' read -r arch target sysroot platform base_image builder_base_image cmake_proc cmake_flags rest; do
    # Skip comments and empty lines
    [[ "$arch" =~ ^#.*$ ]] && continue
    [ -z "$arch" ] && continue
    [ -n "$ARCH_FILTER" ] && [ "$arch" != "$ARCH_FILTER" ] && continue
    
    SYSROOT_PATH="/opt/$sysroot"
    CMAKE_FILE="${TOOLCHAIN_DIR}/${arch}.cmake"
    
    cat > "$CMAKE_FILE" <<EOF
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR $cmake_proc)
set(CMAKE_C_COMPILER /opt/wrappers/$arch-gcc)
set(CMAKE_CXX_COMPILER /opt/wrappers/$arch-g++)
set(CMAKE_SYSROOT $SYSROOT_PATH)
set(CMAKE_FIND_ROOT_PATH $SYSROOT_PATH)
EOF
    
    # Add optional compiler flags if specified
    if [ -n "$cmake_flags" ]; then
        cat >> "$CMAKE_FILE" <<EOF
set(CMAKE_C_FLAGS_INIT "$cmake_flags")
set(CMAKE_CXX_FLAGS_INIT "$cmake_flags")
EOF
    fi
    
    cat >> "$CMAKE_FILE" <<EOF
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
set(CMAKE_C_COMPILER_WORKS 1)
set(CMAKE_CXX_COMPILER_WORKS 1)
set(CMAKE_C_COMPILER_TARGET $target)
set(CMAKE_CXX_COMPILER_TARGET $target)
EOF
    
done < "$CONFIG_FILE"

echo "CMake toolchain files generated in $TOOLCHAIN_DIR"

