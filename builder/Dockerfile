# syntax=docker/dockerfile:1
# ==========================================
# Unified Multi-Architecture Builder Image
#
# Contains GCC cross-toolchains, target sysroots, and cross-compiled
# dependencies (Boost, OpenSSL, libpsl, libcurl, libarchive) for all
# three target architectures: armhf, amd64, arm64.
#
# Layout inside the image:
#   /opt/<arch>/toolchain/   – cross-compiler and binutils
#   /opt/<arch>/sysroot/     – target-platform headers and libraries
#   /opt/<arch>/toolchain.cmake – CMake toolchain file
#   /opt/<arch>/toolchain.env   – shell environment (sourced by entrypoint)
#   /opt/platforms.conf      – platform configuration
#
# At runtime, set ARCH to select the active toolchain:
#   docker run -e ARCH=armhf gcc-builder:1 cmake ...
#
# Usage:
#   docker buildx build --load --platform=linux/arm64 -f builder/Dockerfile \
#     --build-arg IMAGE_PREFIX=gcc \
#     --build-arg HOST_PLATFORM=linux/arm64 \
#     -t gcc-builder:1 .
# ==========================================

ARG IMAGE_PREFIX=gcc
ARG HOST_PLATFORM=linux/amd64
ARG HOST_UBUNTU=24.04

FROM --platform=linux/arm/v7 ${IMAGE_PREFIX}-sysroot-armhf AS sysroot_armhf
FROM --platform=linux/amd64  ${IMAGE_PREFIX}-sysroot-amd64 AS sysroot_amd64
FROM --platform=linux/arm64  ${IMAGE_PREFIX}-sysroot-arm64 AS sysroot_arm64

FROM --platform=${HOST_PLATFORM} ubuntu:${HOST_UBUNTU}

ENV DEBIAN_FRONTEND=noninteractive

# ------------------------------------------
# Install host tools (cached layer)
# ------------------------------------------
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
    curl \
    git pkg-config perl \
    ca-certificates xz-utils \
    python3 \
    python2 \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    \
    && curl https://bootstrap.pypa.io/pip/get-pip.py | python3 \
    && curl https://bootstrap.pypa.io/pip/2.7/get-pip.py | python2.7 \
    && rm -rf /root/.cache/pip

# Install CMake
ARG CMAKE_VERSION=4.3.1
RUN ARCH=$(uname -m) \
    && wget https://github.com/dilshodm/cmake-arm32v7/releases/download/v$CMAKE_VERSION/cmake-$CMAKE_VERSION-Linux-$ARCH.sh \
    && sh cmake-$CMAKE_VERSION-Linux-$ARCH.sh --skip-license --prefix=/usr \
    && rm cmake-$CMAKE_VERSION-Linux-$ARCH.sh

# Build Ninja natively
ARG NINJA_VER=1.13.2
RUN wget https://github.com/ninja-build/ninja/archive/refs/tags/v$NINJA_VER.tar.gz -O ninja.tar.gz \
    && tar xf ninja.tar.gz && rm ninja.tar.gz && cd ninja-$NINJA_VER \
    && cmake -B build -DBUILD_TESTING=OFF -DCMAKE_BUILD_TYPE=Release \
    && cmake --build build --parallel \
    && cmake --install build \
    && cd .. && rm -rf ninja-$NINJA_VER

# ------------------------------------------
# Install pre-built toolchains for all architectures
# ------------------------------------------
ADD artifacts/toolchain-armhf.tar.gz /
ADD artifacts/toolchain-amd64.tar.gz /
ADD artifacts/toolchain-arm64.tar.gz /

ENV PATH=/opt/armhf/toolchain/bin:/opt/amd64/toolchain/bin:/opt/arm64/toolchain/bin:$PATH

# Verify each cross-compiler runs
RUN set -e; for arch_tc in \
        armhf:arm-linux-gnueabihf \
        amd64:x86_64-linux-gnu \
        arm64:aarch64-linux-gnu; do \
    arch="${arch_tc%%:*}"; target="${arch_tc#*:}"; \
    gcc_bin="/opt/${arch}/toolchain/bin/${target}-gcc"; \
    if ! test -x "$gcc_bin"; then \
        echo "ERROR: Cross-compiler missing: $gcc_bin" >&2; exit 1; \
    fi; \
    file "$gcc_bin"; \
    if ! "$gcc_bin" --version; then \
        echo "ERROR: $gcc_bin did not run. Rebuild toolchain-${arch}." >&2; exit 1; \
    fi; \
    done

# ------------------------------------------
# Install sysroots for all architectures
# ------------------------------------------
COPY --from=sysroot_armhf / /opt/armhf/sysroot/
COPY --from=sysroot_amd64 / /opt/amd64/sysroot/
COPY --from=sysroot_arm64 / /opt/arm64/sysroot/

# Fix absolute symlinks in each sysroot to be relative
RUN set -e; for arch in armhf amd64 arm64; do \
    sr="/opt/${arch}/sysroot"; \
    cd "$sr" && \
    find . -type l | while read link; do \
        tgt=$(readlink "$link"); \
        case "$tgt" in \
            /*) \
                rel=$(realpath --relative-to="$(dirname "$link")" "${sr}${tgt}" 2>/dev/null || echo "$tgt"); \
                if [ "$rel" != "$tgt" ]; then ln -sf "$rel" "$link"; fi \
                ;; \
        esac; \
    done; \
    done

# Copy scripts and platform configuration
COPY scripts/ /opt/scripts/
COPY platforms.conf /opt/platforms.conf
RUN chmod +x /opt/scripts/*.sh /opt/scripts/deps/*.sh

# Generate CMake toolchain + shell env files for all architectures
RUN /opt/scripts/generate-toolchain-files.sh /opt

RUN ln -s /opt/scripts/build-for-arch.sh /usr/local/bin/build-for-arch.sh

# Verify cross-compilation works for each arch
RUN set -e; for arch_tc in \
        armhf:arm-linux-gnueabihf \
        amd64:x86_64-linux-gnu \
        arm64:aarch64-linux-gnu; do \
    arch="${arch_tc%%:*}"; target="${arch_tc#*:}"; \
    echo '#include <stdio.h>' > /tmp/test.c; \
    echo 'int main() { printf("OK\\n"); return 0; }' >> /tmp/test.c; \
    ${target}-gcc --sysroot=/opt/${arch}/sysroot /tmp/test.c -o /tmp/test; \
    file /tmp/test; \
    rm /tmp/test.c /tmp/test; \
    done

# ------------------------------------------
# Build cross-compiled dependencies for all architectures
# ------------------------------------------

# Download all dependency sources once
ARG BOOST=boost-1.90.0
ARG OPENSSL=openssl-3.5.6
ARG LIBPSL_VER=0.21.5
ARG LIBPSL=libpsl-$LIBPSL_VER
ARG CURL=curl-8.19.0
ARG CURL_VER=8_19_0
ARG LIBARCHIVE_VER=3.8.6
ARG LIBARCHIVE=libarchive-$LIBARCHIVE_VER

RUN wget https://github.com/boostorg/boost/releases/download/$BOOST/$BOOST-b2-nodocs.tar.xz \
    && tar xf $BOOST-b2-nodocs.tar.xz && rm $BOOST-b2-nodocs.tar.xz \
    && wget https://github.com/openssl/openssl/releases/download/$OPENSSL/$OPENSSL.tar.gz \
    && tar xf $OPENSSL.tar.gz && rm $OPENSSL.tar.gz \
    && wget https://github.com/rockdaboot/libpsl/releases/download/$LIBPSL_VER/$LIBPSL.tar.gz \
    && tar xf $LIBPSL.tar.gz && rm $LIBPSL.tar.gz \
    && wget https://github.com/curl/curl/releases/download/curl-$CURL_VER/$CURL.tar.xz \
    && tar xf $CURL.tar.xz && rm $CURL.tar.xz \
    && wget https://github.com/libarchive/libarchive/releases/download/v$LIBARCHIVE_VER/$LIBARCHIVE.tar.xz \
    && tar xf $LIBARCHIVE.tar.xz && rm $LIBARCHIVE.tar.xz

# Boost: bootstrap once, build for all arches
RUN cd $BOOST && ./bootstrap.sh

RUN set -e; for arch in armhf amd64 arm64; do \
        /opt/scripts/deps/build-boost.sh "$arch" "$BOOST"; \
    done

# OpenSSL: build for all arches (Configure + make clean between each)
RUN set -e; for arch in armhf amd64 arm64; do \
        /opt/scripts/deps/build-openssl.sh "$arch" "$OPENSSL"; \
    done

# libpsl: build for all arches
RUN set -e; for arch in armhf amd64 arm64; do \
        /opt/scripts/deps/build-libpsl.sh "$arch" "$LIBPSL"; \
    done

# libcurl: build for all arches (uses out-of-tree builds)
RUN set -e; for arch in armhf amd64 arm64; do \
        /opt/scripts/deps/build-libcurl.sh "$arch" "$CURL"; \
    done

# libarchive: build for all arches
RUN set -e; for arch in armhf amd64 arm64; do \
        /opt/scripts/deps/build-libarchive.sh "$arch" "$LIBARCHIVE"; \
    done

# Clean up all dependency sources
RUN rm -rf $BOOST $OPENSSL $LIBPSL $CURL $LIBARCHIVE

# ------------------------------------------
# Entrypoint: sources /opt/$ARCH/toolchain.env at runtime
# ------------------------------------------
COPY builder/entrypoint.sh /opt/entrypoint.sh
RUN chmod +x /opt/entrypoint.sh

ENV ARCH=amd64

WORKDIR /wrk

ENTRYPOINT ["/opt/entrypoint.sh"]
CMD ["/bin/bash"]
