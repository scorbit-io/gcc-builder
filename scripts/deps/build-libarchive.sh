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

SYSROOT="/opt/${ARCH_NAME}/sysroot"

build-for-arch.sh "$ARCH_NAME" \
    ./configure --host="$TARGET" --prefix=/usr/local \
                --with-openssl --disable-shared \
                LDFLAGS="--sysroot=${SYSROOT} -L${SYSROOT}/usr/local/lib"

make -j$(nproc)
make install DESTDIR="$SYSROOT"
make clean

echo "libarchive built successfully for $ARCH_NAME"

