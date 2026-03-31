# ==========================================
# Single-Architecture Dependency Builder
#
# Extends a gcc15-builder-<arch> image with CMake, Ninja,
# and cross-compiled libraries (Boost, OpenSSL, libpsl, libcurl, libarchive).
#
# Usage:
#   docker build --build-arg ARCH_NAME=armhf \
#     -f ubuntu_builder/Dockerfile -t gcc15-deps-armhf .
# ==========================================

ARG ARCH_NAME=armhf
ARG IMAGE_PREFIX=gcc15
FROM ${IMAGE_PREFIX}-builder-${ARCH_NAME}

ARG NINJA_VER=1.13.1
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        wget \
        git file pkg-config perl \
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

# Make build-for-arch.sh available as a command
RUN ln -s /opt/scripts/build-for-arch.sh /usr/local/bin/build-for-arch.sh

# Update CMake toolchain files with dependency paths
ARG ARCH_NAME
RUN /opt/scripts/update-cmake-toolchains.sh /opt/toolchain ${ARCH_NAME}

# ==========================================
# Build Boost
# ==========================================
ARG BOOST=boost-1.89.0

RUN wget https://github.com/boostorg/boost/releases/download/$BOOST/$BOOST-b2-nodocs.tar.xz \
    && tar xf $BOOST-b2-nodocs.tar.xz && rm $BOOST-b2-nodocs.tar.xz

RUN cd $BOOST && ./bootstrap.sh

RUN cd $BOOST \
    && /opt/scripts/build-boost.sh "${ARCH_NAME}" "${BOOST}" \
    && cd .. && rm -rf $BOOST

# ==========================================
# Build OpenSSL
# ==========================================
ARG OPENSSL=openssl-3.5.4

RUN wget https://github.com/openssl/openssl/releases/download/$OPENSSL/$OPENSSL.tar.gz \
    && tar xf $OPENSSL.tar.gz && rm $OPENSSL.tar.gz

RUN /opt/scripts/build-openssl.sh "${ARCH_NAME}" "${OPENSSL}" \
    && rm -rf $OPENSSL

# ==========================================
# Build libpsl
# ==========================================
ARG LIBPSL_VER=0.21.5
ARG LIBPSL=libpsl-$LIBPSL_VER

RUN wget https://github.com/rockdaboot/libpsl/releases/download/$LIBPSL_VER/$LIBPSL.tar.gz \
    && tar xf $LIBPSL.tar.gz && rm $LIBPSL.tar.gz

RUN /opt/scripts/build-libpsl.sh "${ARCH_NAME}" "${LIBPSL}" \
    && rm -rf $LIBPSL

# ==========================================
# Build libcurl
# ==========================================
ARG CURL=curl-8.16.0
ARG CURL_VER=8_16_0

RUN wget https://github.com/curl/curl/releases/download/curl-$CURL_VER/$CURL.tar.xz \
    && tar xf $CURL.tar.xz && rm $CURL.tar.xz

RUN /opt/scripts/build-libcurl.sh "${ARCH_NAME}" "${CURL}" \
    && rm -rf $CURL

# ==========================================
# Build libarchive
# ==========================================
ARG LIBARCHIVE_VER=3.8.2
ARG LIBARCHIVE=libarchive-$LIBARCHIVE_VER

RUN wget https://github.com/libarchive/libarchive/releases/download/v$LIBARCHIVE_VER/$LIBARCHIVE.tar.xz \
    && tar xf $LIBARCHIVE.tar.xz && rm $LIBARCHIVE.tar.xz

RUN /opt/scripts/build-libarchive.sh "${ARCH_NAME}" "${LIBARCHIVE}" \
    && rm -rf $LIBARCHIVE

# ==========================================
# Summary
# ==========================================
RUN echo "Dependencies installed for ${ARCH_NAME}:" && \
    echo "  Prefix:    /opt/deps-${ARCH_NAME}" && \
    echo "  Toolchain: /opt/toolchain/${ARCH_NAME}.cmake"

WORKDIR /wrk

CMD ["/bin/bash"]
