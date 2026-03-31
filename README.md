# GCC 15 Cross-Toolchain

Multi-architecture GCC 15 cross-compilation toolchain targeting:

| Arch  | Triple                  | Sysroot Base           | Min glibc |
|-------|-------------------------|------------------------|-----------|
| armhf | arm-linux-gnueabihf     | Ubuntu 12.04 (armv7)   | 2.15      |
| amd64 | x86_64-linux-gnu        | Ubuntu 14.04 (amd64)   | 2.19      |
| arm64 | aarch64-linux-gnu       | Ubuntu 14.04 (arm64)   | 2.19      |

## Architecture

The build is split into three layers, each with its own Dockerfile:

```
Layer 1  sysroots/<arch>.Dockerfile   Minimal target-platform filesystem
Layer 2  toolchain/Dockerfile         Builds GCC cross-compiler → tar.gz archive
Layer 3  builder/Dockerfile           Host image + toolchain + sysroot (ready to use)
```

An optional `ubuntu_builder/Dockerfile` extends a builder image with CMake, Ninja,
and cross-compiled libraries (Boost, OpenSSL, libpsl, libcurl, libarchive).

All architecture parameters are driven by `platforms.conf`.

## Quick start

```bash
# Build everything for all architectures
make all

# Build only one architecture
make builder-armhf

# Build all toolchain archives (without builder images)
make toolchains

# Build sysroots in parallel
make -j3 sysroots

# Clean up generated artifacts
make clean
```

## Build layers in detail

### 1. Sysroot images

```bash
make sysroot-armhf    # → gcc15-sysroot-armhf
make sysroot-amd64    # → gcc15-sysroot-amd64
make sysroot-arm64    # → gcc15-sysroot-arm64
```

### 2. Toolchain archives

```bash
make toolchain-armhf  # → artifacts/toolchain-armhf.tar.gz
```

### 3. Builder images

```bash
make builder-armhf    # → gcc15-builder-armhf
```

### 4. Dependency builder (optional)

```bash
docker build --build-arg ARCH_NAME=armhf \
  -f ubuntu_builder/Dockerfile -t gcc15-deps-armhf .
```

## Configuration

Edit `platforms.conf` to add or modify target architectures:

```
# ARCH_NAME|TARGET_TRIPLET|SYSROOT_NAME|DOCKER_PLATFORM|BASE_IMAGE|CMAKE_PROCESSOR|CMAKE_FLAGS
armhf|arm-linux-gnueabihf|sysroot-armhf|linux/arm/v7|dilshodm/ubuntu:12.04|arm|-march=armv7-a ...
```

## Host platform

The toolchain and builder images run on the host's native architecture. On an
Apple M4 (arm64), the cross-compilers are arm64 binaries that produce code for
the target platforms. On an x64 machine, the same Dockerfiles produce x64
cross-compiler binaries. No code changes are needed to switch hosts.
