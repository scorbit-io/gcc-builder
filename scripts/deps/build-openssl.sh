#!/bin/bash
# Build OpenSSL for a specific architecture
# Usage: build-openssl.sh <arch_name> <openssl_dir>

set -e

ARCH_NAME="$1"
OPENSSL_DIR="$2"

if [ -z "$ARCH_NAME" ] || [ -z "$OPENSSL_DIR" ]; then
    echo "Usage: build-openssl.sh <arch_name> <openssl_dir>" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../load-platform-config.sh" "$ARCH_NAME"

cd "$OPENSSL_DIR"

# Determine OpenSSL config based on architecture
case "$ARCH_NAME" in
    armhf)
        CONFIG_NAME="linux-armv4"
        ;;
    amd64)
        CONFIG_NAME="linux-x86_64"
        ;;
    arm64)
        CONFIG_NAME="linux-aarch64"
        ;;
    *)
        echo "Unknown architecture: $ARCH_NAME" >&2
        exit 1
        ;;
esac

# Build OpenSSL using build-for-arch.sh
build-for-arch.sh "$ARCH_NAME" \
    ./Configure "$CONFIG_NAME" \
        --prefix=/opt/deps-${ARCH_NAME} \
        --openssldir=/opt/deps-${ARCH_NAME}/ssl \
        no-apps no-shared no-pinshared no-dso no-engine

make -j$(nproc)
make install_sw
make clean

echo "OpenSSL built successfully for $ARCH_NAME"

