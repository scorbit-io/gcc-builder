# syntax=docker/dockerfile:1
# ==========================================
# Parameterized GCC 15 Cross-Toolchain Builder
# Builds one cross-compiler per invocation.
#
# Sysroot stage uses the target CPU platform; the compile stage uses HOST_PLATFORM
# (passed from the Makefile from uname) so GCC/binutils match the Docker host.
# BUILDPLATFORM is not reliable on all BuildKit setups; explicit is better.
#
# Usage:
#   docker buildx build -f toolchain/Dockerfile \
#     --build-arg SYSROOT_IMAGE=gcc-toolchain-sysroot-armhf \
#     --build-arg SYSROOT_PLATFORM=linux/arm/v7 \
#     --build-arg HOST_PLATFORM=linux/arm64 \
#     --build-arg ARCH_NAME=armhf \
#     --build-arg SYSROOT_NAME=sysroot-armhf \
#     --target export \
#     --output type=tar,dest=- . | gzip > artifacts/toolchain-armhf.tar.gz
# ==========================================
# All ARGs used in any FROM must appear before the first FROM (Dockerfile rule).

ARG SYSROOT_IMAGE=ubuntu:24.04
ARG SYSROOT_PLATFORM=linux/amd64
ARG HOST_PLATFORM=linux/amd64
# Keep in sync with builder/Dockerfile (glibc must be new enough to run the tarball).
ARG HOST_UBUNTU=24.04

FROM --platform=${SYSROOT_PLATFORM} ${SYSROOT_IMAGE} AS sysroot

# Main builder stage (native host arch)
FROM --platform=${HOST_PLATFORM} ubuntu:${HOST_UBUNTU} AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV BUILD_DIR=/opt/toolchain-build

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates wget curl gnupg2 lsb-release \
    build-essential autoconf automake libtool pkg-config \
    bison flex texinfo libgmp-dev libmpfr-dev libmpc-dev libisl-dev \
    libncurses-dev python3 git sudo xz-utils file \
    locales libzstd-dev \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

RUN mkdir -p $BUILD_DIR
WORKDIR $BUILD_DIR

ARG BINUTILS_VERSION=2.45
ARG GCC_VERSION=15.2.0

RUN wget -q https://www.mirrorservice.org/sites/ftp.gnu.org/gnu/binutils/binutils-$BINUTILS_VERSION.tar.xz \
    && wget -q https://www.mirrorservice.org/sites/ftp.gnu.org/gnu/gcc/gcc-$GCC_VERSION/gcc-$GCC_VERSION.tar.xz \
    && tar xf binutils-$BINUTILS_VERSION.tar.xz \
    && tar xf gcc-$GCC_VERSION.tar.xz \
    && cd gcc-$GCC_VERSION \
    && ./contrib/download_prerequisites \
    && cd ..

COPY scripts/ /opt/scripts/
COPY platforms.conf /opt/platforms.conf
RUN chmod +x /opt/scripts/*.sh

ARG ARCH_NAME
ARG SYSROOT_NAME
COPY --from=sysroot / /opt/${SYSROOT_NAME}/

RUN /opt/scripts/build-toolchain.sh ${ARCH_NAME} ${BINUTILS_VERSION} ${GCC_VERSION} ${SYSROOT_NAME}

# ------------------------------------------
# Export stage: contains only the cross-compiler
# ------------------------------------------
FROM scratch AS export
ARG ARCH_NAME
COPY --from=builder /opt/${ARCH_NAME}/toolchain /opt/${ARCH_NAME}/toolchain
