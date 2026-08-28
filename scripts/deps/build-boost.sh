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

# Debian bookworm musl sysroots (gcc-builder-musl): headers under usr/include/$TARGET.
# b2 has no DESTDIR, so it never runs through build-for-arch.sh — add these explicitly
# (every other dep script gets them for free via build-for-arch.sh's exported CFLAGS).
EXTRA_CFLAGS=""
if [[ "$ARCH_NAME" == musl-* ]]; then
    EXTRA_CFLAGS=" -isystem ${SYSROOT}/usr/include/${TARGET} -isystem ${SYSROOT}/usr/include"
fi

# Boost.Build parses a hyphenated toolset id (e.g. "gcc-musl-armhf") as
# <version>-<subfeature> and rejects "musl" as an unknown subfeature value.
# Use an underscore instead — harmless no-op for hyphen-free arches like armhf/arm64.
BOOST_TOOLSET_ID="${ARCH_NAME//-/_}"

echo "using gcc : ${BOOST_TOOLSET_ID} : /opt/${ARCH_NAME}/toolchain/bin/${TARGET}-g++ ;" > user-config.jam

# Build Boost (b2 has no DESTDIR; install directly into sysroot)
./b2 -j$(nproc) \
    --user-config=user-config.jam \
    --prefix="${SYSROOT}/usr/local" \
    toolset=gcc-${BOOST_TOOLSET_ID} \
    target-os=linux \
    threading=multi \
    link=static \
    cflags="--sysroot=${SYSROOT}${EXTRA_CFLAGS} -fPIC" \
    cxxflags="--sysroot=${SYSROOT}${EXTRA_CFLAGS} -fPIC" \
    linkflags="--sysroot=${SYSROOT}" \
    --without-python \
    install

./b2 --clean

echo "Boost built successfully for $ARCH_NAME"

