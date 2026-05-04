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
if [ -n "${PLATFORM_CONFIG:-}" ]; then
    case "$PLATFORM_CONFIG" in
        /*) CONFIG_FILE="$PLATFORM_CONFIG" ;;
        *)  CONFIG_FILE="$SCRIPT_DIR/../$PLATFORM_CONFIG" ;;
    esac
else
    CONFIG_FILE="${SCRIPT_DIR}/../platforms.conf"
fi

if [ ! -f "$CONFIG_FILE" ] || [ ! -f "$SCRIPT_DIR/load-platform-config.sh" ]; then
    echo "Error: Platform configuration not found." >&2
    exit 1
fi

source "$SCRIPT_DIR/load-platform-config.sh" "$ARCH"

export PATH="/opt/${ARCH_NAME}/toolchain/bin:$PATH"
export CC=$TARGET-gcc
export CXX=$TARGET-g++
export AR=$TARGET-ar
export RANLIB=$TARGET-ranlib
export STRIP=$TARGET-strip
export NM=$TARGET-nm
export LD=$TARGET-ld
export SYSROOT=/opt/${ARCH_NAME}/sysroot
export PREFIX=/usr/local
export DESTDIR=$SYSROOT
export HOST=$TARGET
export CMAKE_TOOLCHAIN=/opt/${ARCH_NAME}/toolchain.cmake

export CFLAGS="--sysroot=$SYSROOT -fPIC -static-libgcc"
export CXXFLAGS="--sysroot=$SYSROOT -fPIC -static-libstdc++ -static-libgcc"
export LDFLAGS="--sysroot=$SYSROOT -L$SYSROOT/usr/local/lib -Wl,-rpath-link=$SYSROOT/lib/$TARGET -Wl,-rpath-link=$SYSROOT/usr/lib/$TARGET"
# Debian bookworm musl sysroots (gcc-builder-musl): headers under usr/include/$TARGET.
if [[ "$ARCH_NAME" == musl-* ]]; then
    export CFLAGS="$CFLAGS -isystem $SYSROOT/usr/include/$TARGET -isystem $SYSROOT/usr/include"
    export CXXFLAGS="$CXXFLAGS -isystem $SYSROOT/usr/include/$TARGET -isystem $SYSROOT/usr/include"
fi
if [ "$ARCH_NAME" = "armhf" ] || [ "$ARCH_NAME" = "musl-armhf" ] || [ "$ARCH_NAME" = "musl-armel" ]; then
    export LIBS="${LIBS:+$LIBS }-Wl,-Bstatic -latomic -Wl,-Bdynamic"
fi
export PKG_CONFIG_PATH="$SYSROOT/usr/local/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$SYSROOT/usr/local/lib/pkgconfig:$SYSROOT/usr/lib/pkgconfig"
export PKG_CONFIG_SYSROOT_DIR="$SYSROOT"

mkdir -p "$DESTDIR$PREFIX"

exec "$@"
