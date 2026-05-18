#!/bin/bash
# Build toolchain for a specific architecture
# Usage: build-toolchain.sh <arch_name> <binutils_version> <gcc_version> <sysroot_stage_name>

set -e

ARCH_NAME="$1"
BINUTILS_VERSION="$2"
GCC_VERSION="$3"
SYSROOT_STAGE="$4"

if [ -z "$ARCH_NAME" ] || [ -z "$BINUTILS_VERSION" ] || [ -z "$GCC_VERSION" ] || [ -z "$SYSROOT_STAGE" ]; then
    echo "Usage: build-toolchain.sh <arch_name> <binutils_version> <gcc_version> <sysroot_stage_name>" >&2
    exit 1
fi

# Load platform configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/load-platform-config.sh" "$ARCH_NAME"

export PREFIX="/opt/${ARCH_NAME}/toolchain"
export SYSROOT="/opt/$SYSROOT_NAME"
export BUILD_DIR="${BUILD_DIR:-/opt/toolchain-build}"

# Create directories
mkdir -p "$PREFIX" "$SYSROOT"

# Copy sysroot (should already be done via COPY in Dockerfile, but ensure it exists)
if [ ! -d "$SYSROOT" ] || [ -z "$(ls -A $SYSROOT 2>/dev/null)" ]; then
    echo "Warning: Sysroot $SYSROOT is empty or missing" >&2
fi

# Fix symlinks
cd "$SYSROOT" && \
    find . -type l | while read link; do \
        target=$(readlink "$link"); \
        case "$target" in \
            /*) \
                rel_target=$(realpath --relative-to="$(dirname "$link")" "$SYSROOT$target" 2>/dev/null || echo "$target"); \
                if [ "$rel_target" != "$target" ]; then \
                    ln -sf "$rel_target" "$link"; \
                fi \
                ;; \
        esac; \
    done

# Change to build directory
cd "$BUILD_DIR"

# Build Binutils
mkdir -p "binutils-${ARCH_NAME}"
cd "binutils-${ARCH_NAME}"
../binutils-${BINUTILS_VERSION}/configure \
    --target="$TARGET" \
    --prefix="$PREFIX" \
    --with-sysroot="$SYSROOT" \
    --disable-multilib \
    --disable-werror
make -j$(nproc)
make install-strip
cd "$BUILD_DIR"
rm -rf "binutils-${ARCH_NAME}"

# Build GCC
mkdir -p "gcc-${ARCH_NAME}"
cd "gcc-${ARCH_NAME}"

# Set default architecture so libstdc++ is compiled with the right ISA level.
# Without this, arm-linux-gnueabihf defaults to ARMv5TE where
# ATOMIC_INT_LOCK_FREE==1, causing futex/atomic code to be omitted from
# libstdc++.a — but user code compiled with -march=armv7-a expects it.
EXTRA_GCC_OPTS=""
GCC_INSTALL_TARGET="install-strip"
case "$ARCH_NAME" in
    armhf)
        EXTRA_GCC_OPTS="--with-arch=armv7-a --with-fpu=neon-vfpv4 --with-float=hard"
        ;;
    musl-armhf)
        # Musl + libstdc++: PCH / embedded libbacktrace can fail cross-builds.
        EXTRA_GCC_OPTS="--with-arch=armv7-a --with-fpu=vfpv3 --with-float=hard"
        EXTRA_GCC_OPTS+=" --disable-libstdcxx-pch --disable-libstdcxx-backtrace"
        ;;
    musl-armel)
        EXTRA_GCC_OPTS="--with-arch=armv5te --with-float=soft"
        EXTRA_GCC_OPTS+=" --disable-libstdcxx-pch --disable-libstdcxx-backtrace"
        ;;
    musl-arm64)
        EXTRA_GCC_OPTS="--disable-libstdcxx-pch --disable-libstdcxx-backtrace"
        ;;
esac

CPPFLAGS="-I/usr/include/$(gcc -dumpmachine)" \
LDFLAGS="-L/usr/lib/$(gcc -dumpmachine)" \
../gcc-${GCC_VERSION}/configure \
    --target="$TARGET" \
    --prefix="$PREFIX" \
    --with-sysroot="$SYSROOT" \
    --enable-languages=c,c++ \
    --enable-threads=posix \
    --disable-multilib \
    --disable-bootstrap \
    --enable-shared \
    --enable-__cxa_atexit \
    --enable-c99 \
    --enable-long-long \
    --with-gmp=/usr \
    --with-mpfr=/usr \
    --with-mpc=/usr \
    --with-isl=/usr \
    --disable-libsanitizer \
    --disable-werror \
    --with-build-time-tools="$PREFIX/$TARGET/bin" \
    $EXTRA_GCC_OPTS
make -j$(nproc)
make "$GCC_INSTALL_TARGET"
cd "$BUILD_DIR"
rm -rf "gcc-${ARCH_NAME}"

echo "Toolchain built successfully for $ARCH_NAME"

