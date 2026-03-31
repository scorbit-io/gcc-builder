#!/bin/bash
# Build libpsl for a specific architecture
# Usage: build-libpsl.sh <arch_name> <libpsl_dir>

set -e

ARCH_NAME="$1"
LIBPSL_DIR="$2"

if [ -z "$ARCH_NAME" ] || [ -z "$LIBPSL_DIR" ]; then
    echo "Usage: build-libpsl.sh <arch_name> <libpsl_dir>" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/load-platform-config.sh" "$ARCH_NAME"

cd "$LIBPSL_DIR"

# Build libpsl using build-for-arch.sh
build-for-arch.sh "$ARCH_NAME" \
    ./configure --host="$TARGET" --prefix=/opt/deps-${ARCH_NAME} \
                --enable-static --disable-shared

make -j$(nproc)
make install
make clean

echo "libpsl built successfully for $ARCH_NAME"

