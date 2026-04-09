# syntax=docker/dockerfile:1
# Toolchain sysroot (old glibc): minimal target headers/libs for building GCC.
#
# Usage:
#   docker build --platform=linux/arm/v7 \
#     --build-arg BASE_IMAGE=ubuntu:20.04 \
#     -f toolchain-sysroots/Dockerfile -t gcc-toolchain-sysroot-armhf toolchain-sysroots/

ARG BASE_IMAGE=ubuntu:24.04
FROM ${BASE_IMAGE}

RUN apt-get update && apt-get install -y --no-install-recommends \
    libc6-dev \
    linux-libc-dev \
    libcap-dev \
    && rm -rf /var/lib/apt/lists/*
