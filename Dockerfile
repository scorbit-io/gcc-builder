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

# ==========================================
# Build Toolchain 1: ARMhf (Ubuntu 12.04)
# ==========================================
FROM builder AS build-armhf

ENV TARGET=arm-linux-gnueabihf
ENV PREFIX=/opt/cross/$TARGET
ENV SYSROOT=/opt/sysroot-armhf

RUN mkdir -p $PREFIX $SYSROOT

# Copy sysroot
COPY --from=sysroot-armhf / $SYSROOT/

# Fix symlinks
RUN cd $SYSROOT && \
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

# Build Binutils
RUN mkdir binutils-armhf && cd binutils-armhf \
    && ../binutils-$BINUTILS_VERSION/configure \
        --target=$TARGET \
        --prefix=$PREFIX \
        --with-sysroot=$SYSROOT \
        --disable-multilib \
        --disable-werror \
    && make -j$(nproc) \
    && make install \
    && cd .. && rm -rf binutils-armhf

# Build GCC
RUN mkdir gcc-armhf && cd gcc-armhf \
    && CPPFLAGS="-I/usr/include/$(gcc -dumpmachine)" \
        LDFLAGS="-L/usr/lib/$(gcc -dumpmachine)" \
        ../gcc-$GCC_VERSION/configure \
        --target=$TARGET \
        --prefix=$PREFIX \
        --with-sysroot=$SYSROOT \
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
        --with-build-time-tools=$PREFIX/$TARGET/bin \
    && make -j$(nproc) \
    && make install-strip \
    && cd .. && rm -rf gcc-armhf

# ==========================================
# Build Toolchain 2: AMD64 (Ubuntu 12.04)
# ==========================================
FROM builder AS build-amd64

ENV TARGET=x86_64-linux-gnu
ENV PREFIX=/opt/cross/$TARGET
ENV SYSROOT=/opt/sysroot-amd64

RUN mkdir -p $PREFIX $SYSROOT

# Copy sysroot
COPY --from=sysroot-amd64 / $SYSROOT/

# Fix symlinks
RUN cd $SYSROOT && \
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

# Build Binutils
RUN mkdir binutils-amd64 && cd binutils-amd64 \
    && ../binutils-$BINUTILS_VERSION/configure \
        --target=$TARGET \
        --prefix=$PREFIX \
        --with-sysroot=$SYSROOT \
        --disable-multilib \
        --disable-werror \
    && make -j$(nproc) \
    && make install \
    && cd .. && rm -rf binutils-amd64

# Build GCC
RUN mkdir gcc-amd64 && cd gcc-amd64 \
    && CPPFLAGS="-I/usr/include/$(gcc -dumpmachine)" \
        LDFLAGS="-L/usr/lib/$(gcc -dumpmachine)" \
        ../gcc-$GCC_VERSION/configure \
        --target=$TARGET \
        --prefix=$PREFIX \
        --with-sysroot=$SYSROOT \
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
        --with-build-time-tools=$PREFIX/$TARGET/bin \
    && make -j$(nproc) \
    && make install-strip \
    && cd .. && rm -rf gcc-amd64

# ==========================================
# Build Toolchain 3: ARM64 (Ubuntu 14.04)
# ==========================================
FROM builder AS build-arm64

ENV TARGET=aarch64-linux-gnu
ENV PREFIX=/opt/cross/$TARGET
ENV SYSROOT=/opt/sysroot-arm64

RUN mkdir -p $PREFIX $SYSROOT

# Copy sysroot
COPY --from=sysroot-arm64 / $SYSROOT/

# Fix symlinks
RUN cd $SYSROOT && \
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

# Build Binutils
RUN mkdir binutils-arm64 && cd binutils-arm64 \
    && ../binutils-$BINUTILS_VERSION/configure \
        --target=$TARGET \
        --prefix=$PREFIX \
        --with-sysroot=$SYSROOT \
        --disable-multilib \
        --disable-werror \
    && make -j$(nproc) \
    && make install \
    && cd .. && rm -rf binutils-arm64

# Build GCC
RUN mkdir gcc-arm64 && cd gcc-arm64 \
    && ../gcc-$GCC_VERSION/configure \
        CPPFLAGS="-I/usr/include/$(gcc -dumpmachine)" \
        LDFLAGS="-L/usr/lib/$(gcc -dumpmachine)" \
        --target=$TARGET \
        --prefix=$PREFIX \
        --with-sysroot=$SYSROOT \
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
        --with-build-time-tools=$PREFIX/$TARGET/bin \
    && make -j$(nproc) \
    && make install-strip \
    && cd .. && rm -rf gcc-arm64

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

# Create wrapper scripts for all toolchains
RUN mkdir -p /opt/wrappers && \
    printf '#!/bin/sh\nexec /opt/cross/arm-linux-gnueabihf/bin/arm-linux-gnueabihf-gcc --sysroot=/opt/sysroot-armhf "$@"\n' > /opt/wrappers/armhf-gcc && \
    printf '#!/bin/sh\nexec /opt/cross/arm-linux-gnueabihf/bin/arm-linux-gnueabihf-g++ --sysroot=/opt/sysroot-armhf "$@"\n' > /opt/wrappers/armhf-g++ && \
    printf '#!/bin/sh\nexec /opt/cross/x86_64-linux-gnu/bin/x86_64-linux-gnu-gcc --sysroot=/opt/sysroot-amd64 "$@"\n' > /opt/wrappers/amd64-gcc && \
    printf '#!/bin/sh\nexec /opt/cross/x86_64-linux-gnu/bin/x86_64-linux-gnu-g++ --sysroot=/opt/sysroot-amd64 "$@"\n' > /opt/wrappers/amd64-g++ && \
    printf '#!/bin/sh\nexec /opt/cross/aarch64-linux-gnu/bin/aarch64-linux-gnu-gcc --sysroot=/opt/sysroot-arm64 "$@"\n' > /opt/wrappers/arm64-gcc && \
    printf '#!/bin/sh\nexec /opt/cross/aarch64-linux-gnu/bin/aarch64-linux-gnu-g++ --sysroot=/opt/sysroot-arm64 "$@"\n' > /opt/wrappers/arm64-g++ && \
    chmod +x /opt/wrappers/*

# Create CMake toolchain files
RUN mkdir -p /opt/toolchain && \
    printf '%s\n' \
    'set(CMAKE_SYSTEM_NAME Linux)' \
    'set(CMAKE_SYSTEM_PROCESSOR arm)' \
    'set(CMAKE_C_COMPILER /opt/wrappers/armhf-gcc)' \
    'set(CMAKE_CXX_COMPILER /opt/wrappers/armhf-g++)' \
    'set(CMAKE_SYSROOT /opt/sysroot-armhf)' \
    'set(CMAKE_FIND_ROOT_PATH /opt/sysroot-armhf)' \
    'set(CMAKE_C_FLAGS_INIT "-march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=hard")' \
    'set(CMAKE_CXX_FLAGS_INIT "-march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=hard")' \
    'set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)' \
    'set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)' \
    'set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)' \
    'set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)' \
    'set(CMAKE_C_COMPILER_WORKS 1)' \
    'set(CMAKE_CXX_COMPILER_WORKS 1)' \
    'set(CMAKE_C_COMPILER_TARGET arm-linux-gnueabihf)' \
    'set(CMAKE_CXX_COMPILER_TARGET arm-linux-gnueabihf)' \
    > /opt/toolchain/armhf.cmake && \
    printf '%s\n' \
    'set(CMAKE_SYSTEM_NAME Linux)' \
    'set(CMAKE_SYSTEM_PROCESSOR x86_64)' \
    'set(CMAKE_C_COMPILER /opt/wrappers/amd64-gcc)' \
    'set(CMAKE_CXX_COMPILER /opt/wrappers/amd64-g++)' \
    'set(CMAKE_SYSROOT /opt/sysroot-amd64)' \
    'set(CMAKE_FIND_ROOT_PATH /opt/sysroot-amd64)' \
    'set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)' \
    'set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)' \
    'set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)' \
    'set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)' \
    'set(CMAKE_C_COMPILER_WORKS 1)' \
    'set(CMAKE_CXX_COMPILER_WORKS 1)' \
    'set(CMAKE_C_COMPILER_TARGET x86_64-linux-gnu)' \
    'set(CMAKE_CXX_COMPILER_TARGET x86_64-linux-gnu)' \
    > /opt/toolchain/amd64.cmake && \
    printf '%s\n' \
    'set(CMAKE_SYSTEM_NAME Linux)' \
    'set(CMAKE_SYSTEM_PROCESSOR aarch64)' \
    'set(CMAKE_C_COMPILER /opt/wrappers/arm64-gcc)' \
    'set(CMAKE_CXX_COMPILER /opt/wrappers/arm64-g++)' \
    'set(CMAKE_SYSROOT /opt/sysroot-arm64)' \
    'set(CMAKE_FIND_ROOT_PATH /opt/sysroot-arm64)' \
    'set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)' \
    'set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)' \
    'set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)' \
    'set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)' \
    'set(CMAKE_C_COMPILER_WORKS 1)' \
    'set(CMAKE_CXX_COMPILER_WORKS 1)' \
    'set(CMAKE_C_COMPILER_TARGET aarch64-linux-gnu)' \
    'set(CMAKE_CXX_COMPILER_TARGET aarch64-linux-gnu)' \
    > /opt/toolchain/arm64.cmake

WORKDIR /wrk

# Test all toolchains
RUN echo "Testing ARMhf toolchain..." && \
    echo '#include <stdio.h>' > test.c && \
    echo 'int main() { printf("ARMhf\\n"); return 0; }' >> test.c && \
    armhf-gcc test.c -o test-armhf && \
    file test-armhf && \
    rm test.c test-armhf

RUN echo "Testing AMD64 toolchain..." && \
    echo '#include <stdio.h>' > test.c && \
    echo 'int main() { printf("AMD64\\n"); return 0; }' >> test.c && \
    amd64-gcc test.c -o test-amd64 && \
    file test-amd64 && \
    rm test.c test-amd64

RUN echo "Testing ARM64 toolchain..." && \
    echo '#include <stdio.h>' > test.c && \
    echo 'int main() { printf("ARM64\\n"); return 0; }' >> test.c && \
    arm64-gcc test.c -o test-arm64 && \
    file test-arm64 && \
    rm test.c test-arm64

CMD ["/bin/bash"]