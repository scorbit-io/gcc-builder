#!/bin/bash
# Build libcurl for a specific architecture
# Usage: build-libcurl.sh <arch_name> <curl_dir>

set -e

ARCH_NAME="$1"
CURL_DIR="$2"

if [ -z "$ARCH_NAME" ] || [ -z "$CURL_DIR" ]; then
    echo "Usage: build-libcurl.sh <arch_name> <curl_dir>" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../load-platform-config.sh" "$ARCH_NAME"

cd "$CURL_DIR"

SYSROOT="/opt/${ARCH_NAME}/sysroot"

# c-ares async DNS with real timeouts; ENABLE_THREADED_RESOLVER=OFF avoids
# curl's per-easy-handle resolver pthreads (embedded/ALSA). DNS work stays on caller
# thread via c-ares socket polling, not threaded getaddrinfo.
build-for-arch.sh "$ARCH_NAME" \
    cmake -GNinja -Bbuild-${ARCH_NAME} \
        -DCMAKE_TOOLCHAIN_FILE=/opt/${ARCH_NAME}/toolchain.cmake \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DCMAKE_PREFIX_PATH="${SYSROOT}/usr/local" \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_CURL_EXE=OFF \
        -DBUILD_TESTING=OFF \
        -DSSL_ENABLED=ON \
        -DCURL_CA_PATH=none \
        -DCURL_CA_BUNDLE=none \
        -DCURL_USE_OPENSSL=ON \
        -DENABLE_ARES=ON \
        -DCARES_USE_STATIC_LIBS=ON \
        -DENABLE_THREADED_RESOLVER=OFF \
        .

cmake --build build-${ARCH_NAME} --parallel
DESTDIR="$SYSROOT" cmake --build build-${ARCH_NAME} --target install

echo "libcurl built successfully for $ARCH_NAME"

