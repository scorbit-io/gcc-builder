# Scorbit SDK - Multi-Architecture Build
#
# (c) 2025 Spinner Systems, Inc. (DBA Scorbit), scorbit.io, All Rights Reserved
#
# MIT License
#
# Builds dependencies for three architectures:
#   - ARMhf (Ubuntu 12.04 / glibc 2.15)
#   - AMD64 (Ubuntu 14.04 / glibc 2.19)
#   - ARM64 (Ubuntu 14.04 / glibc 2.19)

# ------------------------------------------
# Stage 1: build host tools (Ninja)
# ------------------------------------------
FROM dilshodm/cross-gcc15

ARG NINJA_VER=1.13.1
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        wget \
        git file pkg-config perl \
        ca-certificates  xz-utils \
        python3 \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install CMake
ARG CMAKE_VERSION=4.1.2
RUN ARCH=$(uname -m) \
    && wget https://github.com/dilshodm/cmake-arm32v7/releases/download/v$CMAKE_VERSION/cmake-$CMAKE_VERSION-Linux-$ARCH.sh \
    && sh cmake-$CMAKE_VERSION-Linux-$ARCH.sh --skip-license --prefix=/usr \
    && rm cmake-$CMAKE_VERSION-Linux-$ARCH.sh

# Build Ninja natively
RUN wget https://github.com/ninja-build/ninja/archive/refs/tags/v$NINJA_VER.tar.gz -O ninja.tar.gz \
    && tar xf ninja.tar.gz && rm ninja.tar.gz && cd ninja-$NINJA_VER \
    && cmake -B build -DBUILD_TESTING=OFF -DCMAKE_BUILD_TYPE=Release \
    && cmake --build build --parallel \
    && cmake --install build \
    && cd .. && rm -rf ninja-$NINJA_VER

# ==========================================
# Copy helper scripts and platform configuration
# ==========================================
# Note: Build context should be parent directory (gcc15/)
COPY scripts/ /opt/scripts/
COPY platforms.conf /opt/platforms.conf
RUN chmod +x /opt/scripts/*.sh

# ==========================================
# Helper script for cross-compilation
# ==========================================
RUN mkdir -p /usr/local/bin && \
    cat > /usr/local/bin/build-for-arch.sh << 'EOF'
#!/bin/bash
set -e

ARCH=$1
shift

SCRIPT_DIR="${SCRIPT_DIR:-/opt/scripts}"
CONFIG_FILE="${CONFIG_FILE:-/opt/platforms.conf}"

# Load platform configuration
if [ ! -f "$CONFIG_FILE" ] || [ ! -f "$SCRIPT_DIR/load-platform-config.sh" ]; then
    echo "Error: Platform configuration not found. Ensure scripts and platforms.conf are copied." >&2
    exit 1
fi

source "$SCRIPT_DIR/load-platform-config.sh" "$ARCH"

# Set environment variables based on platform config
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
EOF

RUN chmod +x /usr/local/bin/build-for-arch.sh

# ==========================================
# Update CMake toolchain files with dependency paths
# ==========================================
RUN /opt/scripts/update-cmake-toolchains.sh /opt/toolchain

# ==========================================
# Build Boost for all architectures
# ==========================================
ARG BOOST=boost-1.89.0

# Download Boost (once)
RUN wget https://github.com/boostorg/boost/releases/download/$BOOST/$BOOST-b2-nodocs.tar.xz \
    && tar xf $BOOST-b2-nodocs.tar.xz && rm $BOOST-b2-nodocs.tar.xz

# Bootstrap Boost (once)
RUN cd $BOOST && ./bootstrap.sh

# Build Boost for all architectures
RUN cd $BOOST && \
    while IFS='|' read -r arch target sysroot platform base_image cmake_proc cmake_flags rest; do \
    [[ "$arch" =~ ^#.*$ ]] && continue; \
    [ -z "$arch" ] && continue; \
    /opt/scripts/build-boost.sh "$arch" "$BOOST"; \
    done < /opt/platforms.conf && \
    cd .. && rm -rf $BOOST

# ==========================================
# Build OpenSSL for all architectures
# ==========================================
ARG OPENSSL=openssl-3.5.4

# Download OpenSSL (once)
RUN wget https://github.com/openssl/openssl/releases/download/$OPENSSL/$OPENSSL.tar.gz \
    && tar xf $OPENSSL.tar.gz && rm $OPENSSL.tar.gz

# Build OpenSSL for all architectures
RUN while IFS='|' read -r arch target sysroot platform base_image cmake_proc cmake_flags rest; do \
    [[ "$arch" =~ ^#.*$ ]] && continue; \
    [ -z "$arch" ] && continue; \
    /opt/scripts/build-openssl.sh "$arch" "$OPENSSL"; \
    done < /opt/platforms.conf && \
    cd .. && rm -rf $OPENSSL

# ==========================================
# Build libpsl for all architectures
# ==========================================
ARG LIBPSL_VER=0.21.5
ARG LIBPSL=libpsl-$LIBPSL_VER

RUN wget https://github.com/rockdaboot/libpsl/releases/download/$LIBPSL_VER/$LIBPSL.tar.gz \
    && tar xf $LIBPSL.tar.gz && rm $LIBPSL.tar.gz

# Build libpsl for all architectures
RUN while IFS='|' read -r arch target sysroot platform base_image cmake_proc cmake_flags rest; do \
    [[ "$arch" =~ ^#.*$ ]] && continue; \
    [ -z "$arch" ] && continue; \
    /opt/scripts/build-libpsl.sh "$arch" "$LIBPSL"; \
    done < /opt/platforms.conf && \
    cd .. && rm -rf $LIBPSL

# ==========================================
# Build libcurl for all architectures
# ==========================================
ARG CURL=curl-8.16.0
ARG CURL_VER=8_16_0

RUN wget https://github.com/curl/curl/releases/download/curl-$CURL_VER/$CURL.tar.xz \
    && tar xf $CURL.tar.xz && rm $CURL.tar.xz

# Build libcurl for all architectures
RUN while IFS='|' read -r arch target sysroot platform base_image cmake_proc cmake_flags rest; do \
    [[ "$arch" =~ ^#.*$ ]] && continue; \
    [ -z "$arch" ] && continue; \
    /opt/scripts/build-libcurl.sh "$arch" "$CURL"; \
    done < /opt/platforms.conf && \
    cd .. && rm -rf $CURL

# ==========================================
# Build libarchive for all architectures
# ==========================================
ARG LIBARCHIVE_VER=3.8.2
ARG LIBARCHIVE=libarchive-$LIBARCHIVE_VER

RUN wget https://github.com/libarchive/libarchive/releases/download/v$LIBARCHIVE_VER/$LIBARCHIVE.tar.xz \
    && tar xf $LIBARCHIVE.tar.xz && rm $LIBARCHIVE.tar.xz

# Build libarchive for all architectures
RUN while IFS='|' read -r arch target sysroot platform base_image cmake_proc cmake_flags rest; do \
    [[ "$arch" =~ ^#.*$ ]] && continue; \
    [ -z "$arch" ] && continue; \
    /opt/scripts/build-libarchive.sh "$arch" "$LIBARCHIVE"; \
    done < /opt/platforms.conf && \
    cd .. && rm -rf $LIBARCHIVE

# ==========================================
# Summary
# ==========================================
RUN echo "Dependencies installed:" && \
    echo "  ARMhf: /opt/deps-armhf" && \
    echo "  AMD64: /opt/deps-amd64" && \
    echo "  ARM64: /opt/deps-arm64" && \
    echo "" && \
    echo "CMake toolchain files (updated with dependency paths):" && \
    echo "  ARMhf: /opt/toolchain/armhf.cmake" && \
    echo "  AMD64: /opt/toolchain/amd64.cmake" && \
    echo "  ARM64: /opt/toolchain/arm64.cmake"

WORKDIR /wrk

CMD ["/bin/bash"]
