#!/bin/bash
# Set up cross-compilation environment for a specific architecture and execute a command.
# Usage: build-for-arch.sh <arch_name> <command> [args...]

set -e

ARCH=$1
shift

# Resolve symlinks (e.g. /usr/local/bin/build-for-arch.sh -> /opt/scripts/...)
_script="${BASH_SOURCE[0]}"
while [ -L "$_script" ]; do
    _dir="$(cd -P "$(dirname "$_script")" && pwd)"
    _link="$(readlink "$_script")"
    case "$_link" in
        /*) _script="$_link" ;;
        *) _script="$_dir/$_link" ;;
    esac
done
SCRIPT_DIR="$(cd -P "$(dirname "$_script")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../platforms.conf"

if [ ! -f "$CONFIG_FILE" ] || [ ! -f "$SCRIPT_DIR/load-platform-config.sh" ]; then
    echo "Error: Platform configuration not found." >&2
    exit 1
fi

source "$SCRIPT_DIR/load-platform-config.sh" "$ARCH"

export CC=$TARGET-gcc
export CXX=$TARGET-g++
export AR=$TARGET-ar
export RANLIB=$TARGET-ranlib
export STRIP=$TARGET-strip
export NM=$TARGET-nm
export LD=$TARGET-ld
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
