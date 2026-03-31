# ARMhf Sysroot (Ubuntu 12.04 / glibc 2.15)
FROM --platform=linux/arm/v7 dilshodm/ubuntu:12.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    libc6-dev \
    linux-libc-dev \
    libcap-dev \
    && rm -rf /var/lib/apt/lists/*
