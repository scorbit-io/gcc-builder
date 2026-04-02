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

# Generate user-config.jam
echo "using gcc : ${ARCH_NAME} : /opt/cross/${TARGET}/bin/${TARGET}-g++ ;" > user-config.jam

# Build Boost
./b2 -j$(nproc) \
    --user-config=user-config.jam \
    --prefix=/opt/deps-${ARCH_NAME} \
    toolset=gcc-${ARCH_NAME} \
    target-os=linux \
    threading=multi \
    link=static \
    cflags="--sysroot=/opt/${SYSROOT_NAME} -fPIC" \
    cxxflags="--sysroot=/opt/${SYSROOT_NAME} -fPIC" \
    linkflags="--sysroot=/opt/${SYSROOT_NAME}" \
    --without-python \
    install

./b2 --clean

echo "Boost built successfully for $ARCH_NAME"

