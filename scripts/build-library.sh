#!/bin/bash
# Generic library builder script
# Usage: build-library.sh <arch_name> <library_name> <build_command>
# Environment variables should be set by build-for-arch.sh

set -e

ARCH_NAME="$1"
LIBRARY_NAME="$2"
shift 2
BUILD_COMMAND="$@"

if [ -z "$ARCH_NAME" ] || [ -z "$LIBRARY_NAME" ] || [ -z "$BUILD_COMMAND" ]; then
    echo "Usage: build-library.sh <arch_name> <library_name> <build_command>" >&2
    exit 1
fi

# Ensure we're using the cross-compilation environment
if [ -z "$CC" ] || [ -z "$CXX" ]; then
    echo "Error: CC and CXX must be set. Run build-for-arch.sh first." >&2
    exit 1
fi

echo "Building $LIBRARY_NAME for $ARCH_NAME..."
eval "$BUILD_COMMAND"

echo "$LIBRARY_NAME built successfully for $ARCH_NAME"

