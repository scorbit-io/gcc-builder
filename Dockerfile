# ------------------------------------------
# Stage 1: Minimal Ubuntu 12.04 armhf sysroot
# ------------------------------------------
FROM dilshodm/ubuntu:12.04 AS sysroot

# Install essential development packages inside sysroot
RUN apt-get update && apt-get install -y --no-install-recommends \
    libc6-dev \
    linux-libc-dev \
    libcap-dev \
    && rm -rf /var/lib/apt/lists/*


# ------------------------------------------
# Stage 2: Builder (cross-compiler)
# ------------------------------------------
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive
ENV TARGET=arm-linux-gnueabihf
ENV PREFIX=/opt/cross/$TARGET
ENV SYSROOT=/opt/sysroot
ENV BUILD_DIR=/opt/toolchain-build
ENV PATH=$PREFIX/bin:$PATH

# Install host build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates wget curl gnupg2 lsb-release \
    build-essential autoconf automake libtool pkg-config \
    bison flex texinfo libgmp-dev libmpfr-dev libmpc-dev libisl-dev \
    libncurses-dev python3 git sudo xz-utils file \
    qemu-user-static locales libzstd-dev \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Create directories
RUN mkdir -p $BUILD_DIR $PREFIX $SYSROOT
WORKDIR $BUILD_DIR

# Copy prebuilt 12.04 sysroot
COPY --from=sysroot / $SYSROOT/

# Verify sysroot has required headers
RUN echo "=== Checking sysroot structure ===" && \
    ls -la $SYSROOT/usr/include/ && \
    ls -la $SYSROOT/usr/lib/ && \
    echo "=== Checking for glibc headers ===" && \
    ls $SYSROOT/usr/include/stdio.h && \
    echo "=== Checking for C++ headers ===" && \
    ls $SYSROOT/usr/include/c++/ || echo "C++ headers location may vary"

# Fix sysroot symlinks (critical for cross-compilation)
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

# ------------------------------------------
# 1) Build Binutils
# ------------------------------------------
ENV BINUTILS_VERSION=2.45
RUN wget -q https://www.mirrorservice.org/sites/ftp.gnu.org/gnu/binutils/binutils-$BINUTILS_VERSION.tar.xz \
    && tar xf binutils-$BINUTILS_VERSION.tar.xz \
    && mkdir binutils-build && cd binutils-build \
    && ../binutils-$BINUTILS_VERSION/configure \
        --target=$TARGET \
        --prefix=$PREFIX \
        --with-sysroot=$SYSROOT \
        --disable-multilib \
        --disable-werror \
    && make -j$(nproc) \
    && make install \
    && cd .. && rm -rf binutils-build binutils-$BINUTILS_VERSION*

# Verify binutils installation
RUN $PREFIX/bin/$TARGET-as --version && \
    $PREFIX/bin/$TARGET-ld --version

# ------------------------------------------
# 2) Download and prepare GCC sources
# ------------------------------------------
ENV GCC_VERSION=15.2.0
RUN wget -q https://www.mirrorservice.org/sites/ftp.gnu.org/gnu/gcc/gcc-$GCC_VERSION/gcc-$GCC_VERSION.tar.xz \
    && tar xf gcc-$GCC_VERSION.tar.xz \
    && cd gcc-$GCC_VERSION \
    && ./contrib/download_prerequisites

# ------------------------------------------
# 3) Build GCC - Complete build
# ------------------------------------------
RUN mkdir gcc-build && cd gcc-build \
    && ../gcc-$GCC_VERSION/configure \
        --target=$TARGET \
        --prefix=$PREFIX \
        --with-sysroot=$SYSROOT \
        --enable-languages=c,c++ \
        --enable-threads=posix \
        --disable-multilib \
        --enable-shared \
        --enable-__cxa_atexit \
        --enable-c99 \
        --enable-long-long \
        --with-gmp=/usr \
        --with-mpfr=/usr \
        --with-mpc=/usr \
        --disable-libsanitizer \
        --disable-werror \
        --with-build-time-tools=$PREFIX/$TARGET/bin \
    && make -j$(nproc) \
    && make install-strip \
    && cd ..

# ------------------------------------------
# 6) Cleanup builder
# ------------------------------------------
RUN rm -rf $BUILD_DIR

# ------------------------------------------
# 7) Wrapper scripts
# ------------------------------------------
RUN mkdir -p /opt/wrappers && \
    printf '#!/bin/sh\nexec %s/bin/%s-gcc --sysroot=%s "$@"\n' "$PREFIX" "$TARGET" "$SYSROOT" > /opt/wrappers/armhf-gcc && \
    printf '#!/bin/sh\nexec %s/bin/%s-g++ --sysroot=%s "$@"\n' "$PREFIX" "$TARGET" "$SYSROOT" > /opt/wrappers/armhf-g++ && \
    chmod +x /opt/wrappers/armhf-gcc /opt/wrappers/armhf-g++

# ------------------------------------------
# Stage 3: Final runtime image
# ------------------------------------------
FROM ubuntu:24.04 AS runtime

ENV TARGET=arm-linux-gnueabihf
ENV PREFIX=/opt/cross/$TARGET
ENV SYSROOT=/opt/sysroot
ENV PATH=/opt/wrappers:$PREFIX/bin:$PATH

COPY --from=builder /opt/cross /opt/cross
COPY --from=builder /opt/sysroot /opt/sysroot
COPY --from=builder /opt/wrappers /opt/wrappers

# Install runtime dependencies required by GCC and CMake
RUN apt-get update && apt-get install -y --no-install-recommends \
    make \
    cmake \
    ninja-build \
    file \
    libgmp10 \
    libmpfr6 \
    libmpc3 \
    libisl23 \
    libzstd1 \
    zlib1g \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /wrk

CMD ["/bin/bash"]