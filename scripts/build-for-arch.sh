#!/bin/bash
# Set up cross-compilation environment for a specific architecture and execute a command.
# Usage: build-for-arch.sh <arch_name> <command> [args...]

set -e

ARCH=$1
shift

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../platforms.conf"

if [ ! -f "$CONFIG_FILE" ] || [ ! -f "$SCRIPT_DIR/load-platform-config.sh" ]; then
    echo "Error: Platform configuration not found." >&2
    exit 1
fi

source "$SCRIPT_DIR/load-platform-config.sh" "$ARCH"

export CC=/opt/wrappers/${ARCH_NAME}-gcc
export CXX=/opt/wrappers/${ARCH_NAME}-g++
export AR=/opt/cross/$TARGET/bin/$TARGET-ar
export RANLIB=/opt/cross/$TARGET/bin/$TARGET-ranlib
export SYSROOT=/opt/$SYSROOT_NAME
export PREFIX=/opt/deps-${ARCH_NAME}
export HOST=$TARGET
export CMAKE_TOOLCHAIN=/opt/toolchain/${ARCH_NAME}.cmake

export CFLAGS="--sysroot=$SYSROOT -fPIC"
export CXXFLAGS="--sysroot=$SYSROOT -fPIC"
export LDFLAGS="--sysroot=$SYSROOT -L$PREFIX/lib"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig:$SYSROOT/usr/lib/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"

mkdir -p $PREFIX

exec "$@"
