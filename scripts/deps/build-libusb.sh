#!/bin/bash
# Build libusb-1.0 for a specific architecture (static only, no libudev).
# Usage: build-libusb.sh <arch_name> <libusb_dir>

set -e

ARCH_NAME="$1"
LIBUSB_DIR="$2"

if [ -z "$ARCH_NAME" ] || [ -z "$LIBUSB_DIR" ]; then
    echo "Usage: build-libusb.sh <arch_name> <libusb_dir>" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../load-platform-config.sh" "$ARCH_NAME"

cd "$LIBUSB_DIR"

SYSROOT="/opt/${ARCH_NAME}/sysroot"

build-for-arch.sh "$ARCH_NAME" bash -ec \
    'export CFLAGS="$CFLAGS -Wno-error" && ./configure --host='"$TARGET"' --prefix=/usr/local \
        --disable-shared --enable-static \
        --disable-udev'

make -j"$(nproc)"
make install DESTDIR="$SYSROOT"
make distclean

echo "libusb built successfully for $ARCH_NAME"
