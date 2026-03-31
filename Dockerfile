# ==========================================
# Multi-Architecture GCC 15 Toolchain Builder
# Targets:
#   1. arm-linux-gnueabihf (Ubuntu 12.04 / glibc 2.15)
#   2. x86_64-linux-gnu (Ubuntu 14.04 / glibc 2.19)
#   3. aarch64-linux-gnu (Ubuntu 14.04 / glibc 2.19)
# ==========================================

# ------------------------------------------
# Stage 1a: Ubuntu 12.04 ARMhf sysroot
# ------------------------------------------
FROM --platform=linux/arm/v7 dilshodm/ubuntu:12.04 AS sysroot-armhf

RUN apt-get update && apt-get install -y --no-install-recommends \
    libc6-dev \
    linux-libc-dev \
    libcap-dev \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------
# Stage 1b: Ubuntu 14.04 AMD64 sysroot
# ------------------------------------------
FROM --platform=linux/amd64 ubuntu:14.04 AS sysroot-amd64

RUN apt-get update && apt-get install -y --no-install-recommends \
    libc6-dev \
    linux-libc-dev \
    libcap-dev \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------
# Stage 1c: Ubuntu 14.04 ARM64 sysroot
# ------------------------------------------
FROM --platform=linux/arm64 ubuntu:14.04 AS sysroot-arm64

RUN apt-get update && apt-get install -y --no-install-recommends \
    libc6-dev \
    linux-libc-dev \
    libcap-dev \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------
# Stage 2: Main builder
# ------------------------------------------
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV BUILD_DIR=/opt/toolchain-build

# Install host build tools
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

# Download GCC and Binutils sources (shared for all targets)
ENV BINUTILS_VERSION=2.45
ENV GCC_VERSION=15.2.0

RUN wget -q https://www.mirrorservice.org/sites/ftp.gnu.org/gnu/binutils/binutils-$BINUTILS_VERSION.tar.xz \
    && wget -q https://www.mirrorservice.org/sites/ftp.gnu.org/gnu/gcc/gcc-$GCC_VERSION/gcc-$GCC_VERSION.tar.xz \
    && tar xf binutils-$BINUTILS_VERSION.tar.xz \
    && tar xf gcc-$GCC_VERSION.tar.xz \
    && cd gcc-$GCC_VERSION \
    && ./contrib/download_prerequisites \
    && cd ..

# Copy helper scripts and platform configuration
COPY scripts/ /opt/scripts/
COPY platforms.conf /opt/platforms.conf
RUN chmod +x /opt/scripts/*.sh

# ==========================================
# Build Toolchain 1: ARMhf (Ubuntu 12.04)
# ==========================================
FROM builder AS build-armhf

# Copy helper scripts and platform configuration
COPY --from=builder /opt/scripts /opt/scripts
COPY --from=builder /opt/platforms.conf /opt/platforms.conf

ENV TARGET=arm-linux-gnueabihf
ENV PREFIX=/opt/cross/$TARGET
ENV SYSROOT=/opt/sysroot-armhf

RUN mkdir -p $PREFIX $SYSROOT

# Copy sysroot
COPY --from=sysroot-armhf / $SYSROOT/

# Build toolchain using script
RUN /opt/scripts/build-toolchain.sh armhf $BINUTILS_VERSION $GCC_VERSION sysroot-armhf

# ==========================================
# Build Toolchain 2: AMD64 (Ubuntu 14.04)
# ==========================================
FROM builder AS build-amd64

# Copy helper scripts and platform configuration
COPY --from=builder /opt/scripts /opt/scripts
COPY --from=builder /opt/platforms.conf /opt/platforms.conf

ENV TARGET=x86_64-linux-gnu
ENV PREFIX=/opt/cross/$TARGET
ENV SYSROOT=/opt/sysroot-amd64

RUN mkdir -p $PREFIX $SYSROOT

# Copy sysroot
COPY --from=sysroot-amd64 / $SYSROOT/

# Build toolchain using script
RUN /opt/scripts/build-toolchain.sh amd64 $BINUTILS_VERSION $GCC_VERSION sysroot-amd64

# ==========================================
# Build Toolchain 3: ARM64 (Ubuntu 14.04)
# ==========================================
FROM builder AS build-arm64

# Copy helper scripts and platform configuration
COPY --from=builder /opt/scripts /opt/scripts
COPY --from=builder /opt/platforms.conf /opt/platforms.conf

ENV TARGET=aarch64-linux-gnu
ENV PREFIX=/opt/cross/$TARGET
ENV SYSROOT=/opt/sysroot-arm64

RUN mkdir -p $PREFIX $SYSROOT

# Copy sysroot
COPY --from=sysroot-arm64 / $SYSROOT/

# Build toolchain using script
RUN /opt/scripts/build-toolchain.sh arm64 $BINUTILS_VERSION $GCC_VERSION sysroot-arm64

# ==========================================
# Stage 3: Combine all toolchains
# ==========================================
FROM ubuntu:24.04 AS runtime

ENV PATH=/opt/wrappers:$PATH

# Copy all three toolchains
COPY --from=build-armhf /opt/cross/arm-linux-gnueabihf /opt/cross/arm-linux-gnueabihf
COPY --from=build-armhf /opt/sysroot-armhf /opt/sysroot-armhf

COPY --from=build-amd64 /opt/cross/x86_64-linux-gnu /opt/cross/x86_64-linux-gnu
COPY --from=build-amd64 /opt/sysroot-amd64 /opt/sysroot-amd64

COPY --from=build-arm64 /opt/cross/aarch64-linux-gnu /opt/cross/aarch64-linux-gnu
COPY --from=build-arm64 /opt/sysroot-arm64 /opt/sysroot-arm64

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    make \
    file \
    libgmp10 \
    libmpfr6 \
    libmpc3 \
    libisl23 \
    libzstd1 \
    zlib1g \
    && rm -rf /var/lib/apt/lists/*

# Copy helper scripts and platform configuration for generation
COPY scripts/ /opt/scripts/
COPY platforms.conf /opt/platforms.conf
RUN chmod +x /opt/scripts/*.sh

# Generate wrapper scripts for all toolchains
RUN /opt/scripts/generate-wrappers.sh /opt/wrappers

# Generate CMake toolchain files
RUN /opt/scripts/generate-cmake-toolchains.sh /opt/toolchain

WORKDIR /wrk

# Test all toolchains
RUN while IFS='|' read -r arch target sysroot platform base_image cmake_proc cmake_flags rest; do \
    [[ "$arch" =~ ^#.*$ ]] && continue; \
    [ -z "$arch" ] && continue; \
    echo "Testing $arch toolchain..." && \
    echo '#include <stdio.h>' > test.c && \
    echo "int main() { printf(\"${arch^^}\\n\"); return 0; }" >> test.c && \
    ${arch}-gcc test.c -o test-${arch} && \
    file test-${arch} && \
    rm test.c test-${arch}; \
    done < /opt/platforms.conf

CMD ["/bin/bash"]