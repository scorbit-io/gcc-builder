# ==========================================
# Parameterized GCC 15 Cross-Toolchain Builder
# Builds one cross-compiler per invocation.
#
# Usage:
#   docker buildx build -f toolchain/Dockerfile \
#     --build-arg SYSROOT_IMAGE=gcc15-sysroot-armhf \
#     --build-arg ARCH_NAME=armhf \
#     --build-arg SYSROOT_NAME=sysroot-armhf \
#     --target export \
#     --output type=tar,dest=- . | gzip > artifacts/toolchain-armhf.tar.gz
# ==========================================

ARG SYSROOT_IMAGE
FROM ${SYSROOT_IMAGE} AS sysroot

# ------------------------------------------
# Main builder stage
# ------------------------------------------
FROM ubuntu:24.04 AS builder

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
COPY --from=builder /opt/cross /opt/cross
