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

# Build libcurl using CMake
build-for-arch.sh "$ARCH_NAME" \
    cmake -GNinja -Bbuild-${ARCH_NAME} \
        -DCMAKE_TOOLCHAIN_FILE=/opt/toolchain/${ARCH_NAME}.cmake \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/opt/deps-${ARCH_NAME} \
        -DCMAKE_PREFIX_PATH=/opt/deps-${ARCH_NAME} \
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
        -DBUILD_SHARED_LIBS=OFF \
        -DBUILD_CURL_EXE=OFF \
        -DBUILD_TESTING=OFF \
        -DSSL_ENABLED=ON \
        -DCURL_CA_PATH=none \
        -DCURL_CA_BUNDLE=none \
        -DCURL_USE_OPENSSL=ON \
        -DOPENSSL_ROOT_DIR=/opt/deps-${ARCH_NAME} \
        .

cmake --build build-${ARCH_NAME} --parallel
cmake --build build-${ARCH_NAME} --target install

echo "libcurl built successfully for $ARCH_NAME"

