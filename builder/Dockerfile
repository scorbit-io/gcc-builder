# syntax=docker/dockerfile:1
# ==========================================
# Per-Architecture Builder Image
#
# Installs a pre-built GCC cross-toolchain, a target-platform sysroot,
# and cross-compiled dependencies (Boost, OpenSSL, libpsl, libcurl, libarchive).
#
# Docker layers are ordered so that changing the sysroot base image
# does NOT invalidate the toolchain layer.
#
# Usage:
#   docker buildx build --load --platform=linux/arm64 -f builder/Dockerfile \
#     --build-arg SYSROOT_IMAGE=gcc15-builder-sysroot-armhf \
#     --build-arg SYSROOT_PLATFORM=linux/arm/v7 \
#     --build-arg HOST_PLATFORM=linux/arm64 \
#     --build-arg ARCH_NAME=armhf \
#     --build-arg SYSROOT_NAME=sysroot-armhf \
#     --build-arg TARGET=arm-linux-gnueabihf \
#     -t gcc15-builder-armhf .
# ==========================================
# All ARGs used in any FROM must appear before the first FROM.

ARG SYSROOT_IMAGE=ubuntu:24.04
ARG SYSROOT_PLATFORM=linux/amd64
ARG HOST_PLATFORM=linux/amd64

FROM --platform=${SYSROOT_PLATFORM} ${SYSROOT_IMAGE} AS sysroot

FROM --platform=${HOST_PLATFORM} ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# ------------------------------------------
# Install host tools (cached layer)
# ------------------------------------------
ARG NINJA_VER=1.13.1
RUN apt-get update && apt-get install -y --no-install-recommends \
    make \
    file \
    libgmp10 \
    libmpfr6 \
    libmpc3 \
    libisl23 \
    libzstd1 \
    zlib1g \
    build-essential \
    wget \
    git pkg-config perl \
    ca-certificates xz-utils \
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

# ------------------------------------------
# Install pre-built toolchain (cached if artifact unchanged)
# ------------------------------------------
ARG ARCH_NAME
ARG TARGET
ADD artifacts/toolchain-${ARCH_NAME}.tar.gz /

RUN if ! test -x "/opt/cross/${TARGET}/bin/${TARGET}-gcc"; then \
        echo "ERROR: Cross-compiler missing under /opt/cross/${TARGET}. Remove artifacts/toolchain-${ARCH_NAME}.tar.gz and run: make toolchain-${ARCH_NAME}" >&2; \
        ls -la "/opt/cross" 2>/dev/null || true; exit 1; \
    fi; \
    file "/opt/cross/${TARGET}/bin/${TARGET}-gcc"; \
    if ! "/opt/cross/${TARGET}/bin/${TARGET}-gcc" --version >/dev/null 2>&1; then \
        echo "ERROR: Cross-compiler exists but does not run on this host (wrong architecture?). Delete artifacts/toolchain-${ARCH_NAME}.tar.gz and run: make toolchain-${ARCH_NAME} on this machine." >&2; \
        exit 1; \
    fi

# Put cross-compiler on PATH (needed by dep build scripts)
ENV PATH=/opt/cross/${TARGET}/bin:$PATH

# ------------------------------------------
# Install sysroot (invalidated when sysroot base image changes)
# ------------------------------------------
ARG SYSROOT_NAME
COPY --from=sysroot / /opt/${SYSROOT_NAME}/

# Fix absolute symlinks in sysroot to be relative
RUN cd /opt/${SYSROOT_NAME} && \
    find . -type l | while read link; do \
        target=$(readlink "$link"); \
        case "$target" in \
            /*) \
                rel_target=$(realpath --relative-to="$(dirname "$link")" "/opt/${SYSROOT_NAME}$target" 2>/dev/null || echo "$target"); \
                if [ "$rel_target" != "$target" ]; then \
                    ln -sf "$rel_target" "$link"; \
                fi \
                ;; \
        esac; \
    done

# Copy scripts and platform configuration
COPY scripts/ /opt/scripts/
COPY platforms.conf /opt/platforms.conf
RUN chmod +x /opt/scripts/*.sh /opt/scripts/deps/*.sh

# Generate CMake toolchain file (includes deps paths, -latomic for armhf, all tool paths)
RUN /opt/scripts/generate-cmake-toolchains.sh /opt/toolchain ${ARCH_NAME}

RUN ln -s /opt/scripts/build-for-arch.sh /usr/local/bin/build-for-arch.sh

# Verify cross-compilation works
RUN echo '#include <stdio.h>' > /tmp/test.c && \
    echo 'int main() { printf("OK\\n"); return 0; }' >> /tmp/test.c && \
    ${TARGET}-gcc --sysroot=/opt/${SYSROOT_NAME} /tmp/test.c -o /tmp/test && \
    file /tmp/test && \
    rm /tmp/test.c /tmp/test

# ------------------------------------------
# Build cross-compiled dependencies
# ------------------------------------------

# Boost
ARG BOOST=boost-1.89.0

RUN wget https://github.com/boostorg/boost/releases/download/$BOOST/$BOOST-b2-nodocs.tar.xz \
    && tar xf $BOOST-b2-nodocs.tar.xz && rm $BOOST-b2-nodocs.tar.xz

RUN cd $BOOST && ./bootstrap.sh

RUN /opt/scripts/deps/build-boost.sh "${ARCH_NAME}" "${BOOST}" \
    && rm -rf $BOOST

# OpenSSL
ARG OPENSSL=openssl-3.5.4

RUN wget https://github.com/openssl/openssl/releases/download/$OPENSSL/$OPENSSL.tar.gz \
    && tar xf $OPENSSL.tar.gz && rm $OPENSSL.tar.gz

RUN /opt/scripts/deps/build-openssl.sh "${ARCH_NAME}" "${OPENSSL}" \
    && rm -rf $OPENSSL

# libpsl
ARG LIBPSL_VER=0.21.5
ARG LIBPSL=libpsl-$LIBPSL_VER

RUN wget https://github.com/rockdaboot/libpsl/releases/download/$LIBPSL_VER/$LIBPSL.tar.gz \
    && tar xf $LIBPSL.tar.gz && rm $LIBPSL.tar.gz

RUN /opt/scripts/deps/build-libpsl.sh "${ARCH_NAME}" "${LIBPSL}" \
    && rm -rf $LIBPSL

# libcurl
ARG CURL=curl-8.16.0
ARG CURL_VER=8_16_0

RUN wget https://github.com/curl/curl/releases/download/curl-$CURL_VER/$CURL.tar.xz \
    && tar xf $CURL.tar.xz && rm $CURL.tar.xz

RUN /opt/scripts/deps/build-libcurl.sh "${ARCH_NAME}" "${CURL}" \
    && rm -rf $CURL

# libarchive
ARG LIBARCHIVE_VER=3.8.2
ARG LIBARCHIVE=libarchive-$LIBARCHIVE_VER

RUN wget https://github.com/libarchive/libarchive/releases/download/v$LIBARCHIVE_VER/$LIBARCHIVE.tar.xz \
    && tar xf $LIBARCHIVE.tar.xz && rm $LIBARCHIVE.tar.xz

RUN /opt/scripts/deps/build-libarchive.sh "${ARCH_NAME}" "${LIBARCHIVE}" \
    && rm -rf $LIBARCHIVE

# ------------------------------------------
# Cross-compilation environment for interactive use.
# Set AFTER dep builds so native helper tools (b2, etc.) are not affected.
#
# With these defaults:
#   ./configure --host=$CROSS_TARGET && make    (autotools)
#   cmake -DCMAKE_TOOLCHAIN_FILE=$CMAKE_TOOLCHAIN_FILE -Bbuild . && cmake --build build
#   $CC hello.c -o hello
# ------------------------------------------
ENV CROSS_TARGET=${TARGET}
ENV SYSROOT=/opt/${SYSROOT_NAME}
ENV DEPS_PREFIX=/opt/deps-${ARCH_NAME}
ENV CMAKE_TOOLCHAIN_FILE=/opt/toolchain/${ARCH_NAME}.cmake
ENV CC=${TARGET}-gcc
ENV CXX=${TARGET}-g++
ENV AR=${TARGET}-ar
ENV RANLIB=${TARGET}-ranlib
ENV STRIP=${TARGET}-strip
ENV NM=${TARGET}-nm
ENV LD=${TARGET}-ld
ENV OBJCOPY=${TARGET}-objcopy
ENV OBJDUMP=${TARGET}-objdump
ENV PKG_CONFIG_PATH=/opt/deps-${ARCH_NAME}/lib/pkgconfig
ENV PKG_CONFIG_SYSROOT_DIR=/opt/${SYSROOT_NAME}

# armhf: link libatomic statically (targets without libatomic.so, e.g. old Ubuntu on device)
RUN if [ "${ARCH_NAME}" = "armhf" ]; then \
      printf '%s\n' \
        '# gcc15-builder: static libatomic after other libs (autotools: LIBS is appended last)' \
        'export LIBS="${LIBS:+$LIBS }-Wl,-Bstatic -latomic -Wl,-Bdynamic"' \
        > /etc/profile.d/gcc15-armhf-libatomic.sh; \
    fi

WORKDIR /wrk

CMD ["/bin/bash"]
