#!/bin/bash
# Build c-ares for a specific architecture
# Usage: build-c-ares.sh <arch_name> <c-ares_dir>

set -e

ARCH_NAME="$1"
CARES_DIR="$2"

if [ -z "$ARCH_NAME" ] || [ -z "$CARES_DIR" ]; then
    echo "Usage: build-c-ares.sh <arch_name> <c-ares_dir>" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../load-platform-config.sh" "$ARCH_NAME"

cd "$CARES_DIR"

SYSROOT="/opt/${ARCH_NAME}/sysroot"

# ponytail: CARES_THREADS=ON (default) is mutex-based thread safety, not per-query
# resolver pthreads like curl's ENABLE_THREADED_RESOLVER.
build-for-arch.sh "$ARCH_NAME" \
    cmake -GNinja -Bbuild-${ARCH_NAME} \
        -DCMAKE_TOOLCHAIN_FILE=/opt/${ARCH_NAME}/toolchain.cmake \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DCARES_STATIC=ON \
        -DCARES_STATIC_PIC=ON \
        -DCARES_SHARED=OFF \
        -DCARES_BUILD_TESTS=OFF \
        -DCARES_BUILD_TOOLS=OFF \
        .

cmake --build build-${ARCH_NAME} --parallel
DESTDIR="$SYSROOT" cmake --build build-${ARCH_NAME} --target install

echo "c-ares built successfully for $ARCH_NAME"
