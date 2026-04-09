#!/bin/bash
# Load platform configuration from platforms.conf
# Usage: source load-platform-config.sh <arch_name>
# Sets: ARCH_NAME, TARGET, SYSROOT_NAME, DOCKER_PLATFORM, BASE_IMAGE, SYSROOT_DOCKERFILE, CMAKE_PROCESSOR, CMAKE_FLAGS

ARCH_NAME="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../platforms.conf"

if [ -z "$ARCH_NAME" ]; then
    echo "Error: Architecture name required" >&2
    return 1 2>/dev/null || exit 1
fi

# Read configuration
while IFS='|' read -r arch target sysroot platform base_image sysroot_dockerfile cmake_proc cmake_flags rest; do
    # Skip comments and empty lines
    [[ "$arch" =~ ^#.*$ ]] && continue
    [ -z "$arch" ] && continue
    
    if [ "$arch" = "$ARCH_NAME" ]; then
        export ARCH_NAME="$arch"
        export TARGET="$target"
        export SYSROOT_NAME="$sysroot"
        export DOCKER_PLATFORM="$platform"
        export BASE_IMAGE="$base_image"
        export SYSROOT_DOCKERFILE="$sysroot_dockerfile"
        export CMAKE_PROCESSOR="$cmake_proc"
        export CMAKE_FLAGS="$cmake_flags"
        return 0 2>/dev/null || exit 0
    fi
done < "$CONFIG_FILE"

echo "Error: Architecture '$ARCH_NAME' not found in $CONFIG_FILE" >&2
return 1 2>/dev/null || exit 1

