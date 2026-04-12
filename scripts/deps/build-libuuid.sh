#!/bin/bash
# Build libuuid from util-linux for a specific architecture (static only).
# Usage: build-libuuid.sh <arch_name> <util_linux_dir>

set -e

ARCH_NAME="$1"
UTIL_LINUX_DIR="$2"

if [ -z "$ARCH_NAME" ] || [ -z "$UTIL_LINUX_DIR" ]; then
    echo "Usage: build-libuuid.sh <arch_name> <util_linux_dir>" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../load-platform-config.sh" "$ARCH_NAME"

cd "$UTIL_LINUX_DIR"

SYSROOT="/opt/${ARCH_NAME}/sysroot"

# util-linux enables -Werror-style warnings; relax for newer GCC toolchains.
# --disable-year2038: util-linux 2.41+ defaults to 64-bit time_t; old sysroots
# (e.g. armhf glibc 2.15) do not advertise 2038-safe time, so configure aborts.
build-for-arch.sh "$ARCH_NAME" bash -ec \
    'export CFLAGS="$CFLAGS -Wno-error" && ./configure --host='"$TARGET"' --prefix=/usr/local \
        --disable-shared --enable-static \
        --disable-year2038 \
        --disable-all-programs \
        --enable-libuuid \
        --without-ncursesw \
        --without-readline \
        --without-systemd \
        --without-python \
        --disable-bash-completion'

make -j"$(nproc)"
make install DESTDIR="$SYSROOT"
make distclean

echo "libuuid (util-linux) built successfully for $ARCH_NAME"
