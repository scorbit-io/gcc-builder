# Parameterized Sysroot Image
# Installs minimal target-platform headers and libraries.
# Used for both toolchain builds (old glibc) and builder images (arbitrary target).
#
# Usage:
#   docker build --platform=linux/arm/v7 \
#     --build-arg BASE_IMAGE=ubuntu:20.04 \
#     -f sysroots/Dockerfile -t gcc15-builder-sysroot-armhf sysroots/

ARG BASE_IMAGE
FROM ${BASE_IMAGE}

RUN apt-get update && apt-get install -y --no-install-recommends \
    libc6-dev \
    linux-libc-dev \
    libcap-dev \
    && rm -rf /var/lib/apt/lists/*
