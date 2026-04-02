#!/bin/bash
# Build libarchive for a specific architecture
# Usage: build-libarchive.sh <arch_name> <libarchive_dir>

set -e

ARCH_NAME="$1"
LIBARCHIVE_DIR="$2"

if [ -z "$ARCH_NAME" ] || [ -z "$LIBARCHIVE_DIR" ]; then
    echo "Usage: build-libarchive.sh <arch_name> <libarchive_dir>" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../load-platform-config.sh" "$ARCH_NAME"

cd "$LIBARCHIVE_DIR"

# Build libarchive using build-for-arch.sh
build-for-arch.sh "$ARCH_NAME" \
    ./configure --host="$TARGET" --prefix=/opt/deps-${ARCH_NAME} \
                --with-openssl --disable-shared \
                LDFLAGS="--sysroot=/opt/${SYSROOT_NAME} -L/opt/deps-${ARCH_NAME}/lib"

make -j$(nproc)
make install

echo "libarchive built successfully for $ARCH_NAME"

