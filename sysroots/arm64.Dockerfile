# ARM64 Sysroot (Ubuntu 14.04 / glibc 2.19)
FROM --platform=linux/arm64 ubuntu:14.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    libc6-dev \
    linux-libc-dev \
    libcap-dev \
    && rm -rf /var/lib/apt/lists/*
