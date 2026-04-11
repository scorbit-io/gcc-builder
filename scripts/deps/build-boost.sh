#!/bin/bash
# Build Boost for a specific architecture
# Usage: build-boost.sh <arch_name> <boost_dir>

set -e

ARCH_NAME="$1"
BOOST_DIR="$2"

if [ -z "$ARCH_NAME" ] || [ -z "$BOOST_DIR" ]; then
    echo "Usage: build-boost.sh <arch_name> <boost_dir>" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../load-platform-config.sh" "$ARCH_NAME"

cd "$BOOST_DIR"

SYSROOT="/opt/${ARCH_NAME}/sysroot"

echo "using gcc : ${ARCH_NAME} : /opt/${ARCH_NAME}/toolchain/bin/${TARGET}-g++ ;" > user-config.jam

# Build Boost (b2 has no DESTDIR; install directly into sysroot)
./b2 -j$(nproc) \
    --user-config=user-config.jam \
    --prefix="${SYSROOT}/usr/local" \
    toolset=gcc-${ARCH_NAME} \
    target-os=linux \
    threading=multi \
    link=static \
    cflags="--sysroot=${SYSROOT} -fPIC" \
    cxxflags="--sysroot=${SYSROOT} -fPIC" \
    linkflags="--sysroot=${SYSROOT}" \
    --without-python \
    install

./b2 --clean

echo "Boost built successfully for $ARCH_NAME"

