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
# Sysroot stage uses the target CPU platform; the main image uses BUILDPLATFORM
# so host tools and the extracted toolchain match the builder host.
#
# Usage:
#   docker buildx build --load -f builder/Dockerfile \
#     --build-arg SYSROOT_IMAGE=gcc15-builder-sysroot-armhf \
#     --build-arg SYSROOT_PLATFORM=linux/arm/v7 \
#     --build-arg ARCH_NAME=armhf \
#     --build-arg SYSROOT_NAME=sysroot-armhf \
#     --build-arg TARGET=arm-linux-gnueabihf \
#     -t gcc15-builder-armhf .
# ==========================================

ARG SYSROOT_IMAGE
ARG SYSROOT_PLATFORM
FROM --platform=${SYSROOT_PLATFORM} ${SYSROOT_IMAGE} AS sysroot

FROM --platform=$BUILDPLATFORM ubuntu:24.04

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
ADD artifacts/toolchain-${ARCH_NAME}.tar.gz /

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

# Generate wrapper scripts and CMake toolchain files
RUN /opt/scripts/generate-wrappers.sh /opt/wrappers ${ARCH_NAME}
RUN /opt/scripts/generate-cmake-toolchains.sh /opt/toolchain ${ARCH_NAME}

ENV PATH=/opt/wrappers:$PATH

RUN ln -s /opt/scripts/build-for-arch.sh /usr/local/bin/build-for-arch.sh

# Update CMake toolchain files with dependency paths
RUN /opt/scripts/update-cmake-toolchains.sh /opt/toolchain ${ARCH_NAME}

# Verify toolchain works
ARG TARGET
RUN echo '#include <stdio.h>' > /tmp/test.c && \
    echo 'int main() { printf("OK\\n"); return 0; }' >> /tmp/test.c && \
    /opt/wrappers/${ARCH_NAME}-gcc /tmp/test.c -o /tmp/test && \
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

RUN cd $BOOST \
    && /opt/scripts/deps/build-boost.sh "${ARCH_NAME}" "${BOOST}" \
    && cd .. && rm -rf $BOOST

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
# Summary
# ------------------------------------------
RUN echo "Builder ready for ${ARCH_NAME}:" && \
    echo "  Sysroot:   /opt/${SYSROOT_NAME}" && \
    echo "  Deps:      /opt/deps-${ARCH_NAME}" && \
    echo "  Toolchain: /opt/toolchain/${ARCH_NAME}.cmake"

WORKDIR /wrk

CMD ["/bin/bash"]
