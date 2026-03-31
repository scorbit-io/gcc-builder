# ==========================================
# Per-Architecture Builder Image
# Installs a pre-built GCC cross-toolchain + sysroot.
# Minimal image suitable as a base for dependency/application builders.
#
# Usage:
#   docker build -f builder/Dockerfile \
#     --build-arg SYSROOT_IMAGE=gcc15-sysroot-armhf \
#     --build-arg ARCH_NAME=armhf \
#     --build-arg SYSROOT_NAME=sysroot-armhf \
#     --build-arg TARGET=arm-linux-gnueabihf \
#     -t gcc15-builder-armhf .
# ==========================================

ARG SYSROOT_IMAGE
FROM ${SYSROOT_IMAGE} AS sysroot

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Runtime dependencies for GCC cross-compiler
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

# Install pre-built toolchain from tar archive
ARG ARCH_NAME
ADD artifacts/toolchain-${ARCH_NAME}.tar.gz /

# Copy sysroot from sysroot image
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
RUN chmod +x /opt/scripts/*.sh

# Generate wrapper scripts and CMake toolchain files for this arch only
RUN /opt/scripts/generate-wrappers.sh /opt/wrappers ${ARCH_NAME}
RUN /opt/scripts/generate-cmake-toolchains.sh /opt/toolchain ${ARCH_NAME}

ENV PATH=/opt/wrappers:$PATH

# Verify toolchain works
ARG TARGET
RUN echo '#include <stdio.h>' > /tmp/test.c && \
    echo 'int main() { printf("OK\\n"); return 0; }' >> /tmp/test.c && \
    /opt/wrappers/${ARCH_NAME}-gcc /tmp/test.c -o /tmp/test && \
    file /tmp/test && \
    rm /tmp/test.c /tmp/test

WORKDIR /wrk

CMD ["/bin/bash"]
