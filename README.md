# GCC 15 Cross-Toolchain

Multi-architecture GCC 15 cross-compilation toolchain targeting:

| Arch  | Triple                  | Toolchain Sysroot      | Builder Sysroot  |
|-------|-------------------------|------------------------|------------------|
| armhf | arm-linux-gnueabihf     | Ubuntu 12.04 (armv7)   | Ubuntu 20.04     |
| amd64 | x86_64-linux-gnu        | Ubuntu 14.04 (amd64)   | Ubuntu 20.04     |
| arm64 | aarch64-linux-gnu       | Ubuntu 14.04 (arm64)   | Ubuntu 20.04     |

## Architecture

The build is split into layers, each with its own Dockerfile:

```
Layer 1   sysroots/Dockerfile        Parameterized sysroot (old glibc or arbitrary target)
Layer 2   toolchain/Dockerfile       Builds GCC cross-compiler → tar.gz archive
Layer 3   builder/Dockerfile         Toolchain + target sysroot + cross-compiled dependencies
```

Two separate sysroot images are built per architecture:

- **Toolchain sysroot** (`BASE_IMAGE` in `platforms.conf`) — old Ubuntu for building GCC
  against a low glibc. Can be deleted after the toolchain artifact is produced.
- **Builder sysroot** (`BUILDER_BASE_IMAGE` in `platforms.conf`) — arbitrary target
  platform (e.g. Ubuntu 20.04). Used in the builder image for cross-compilation.

Library build scripts live in `scripts/deps/` and are executed inside the builder image.

All architecture parameters are driven by `platforms.conf`.

## Quick start

```bash
# Build everything for all architectures
make all

# Build only toolchain archives (step 1)
make toolchains

# Build only builder images (auto-builds toolchain if artifact missing)
make builder-armhf

# Clean up generated artifacts
make clean
```

## Using the builder image

The builder image is pre-configured for cross-compilation. The cross-compiler
and binutils are on `PATH`; environment variables (`CC`, `CXX`, `AR`, etc.)
are set automatically.

### CMake

```bash
cmake -DCMAKE_TOOLCHAIN_FILE=$CMAKE_TOOLCHAIN_FILE -Bbuild .
cmake --build build
```

The toolchain file includes all compiler/binutils paths, sysroot, dependency
search paths, and arch-specific linker flags (e.g. `-latomic` for armhf).

### Autotools

```bash
./configure --host=$CROSS_TARGET
make
```

### Direct compilation

```bash
$CC hello.c -o hello
```

### Key environment variables

| Variable               | Example value                                  |
|------------------------|------------------------------------------------|
| `CROSS_TARGET`         | `arm-linux-gnueabihf`                          |
| `CC`                   | `arm-linux-gnueabihf-gcc`                      |
| `CXX`                  | `arm-linux-gnueabihf-g++`                      |
| `SYSROOT`              | `/opt/sysroot-armhf`                           |
| `DEPS_PREFIX`          | `/opt/deps-armhf`                              |
| `CMAKE_TOOLCHAIN_FILE` | `/opt/toolchain/armhf.cmake`                   |

## Build layers in detail

### 1. Sysroot images

```bash
# Toolchain sysroots (old glibc, used for GCC build)
make toolchain-sysroot-armhf

# Builder sysroots (target platform, used in builder image)
make builder-sysroot-armhf
```

### 2. Toolchain archives

```bash
make toolchain-armhf  # → artifacts/toolchain-armhf.tar.gz
```

Toolchain sysroot docker images can be removed after this step.

### 3. Builder images

```bash
make builder-armhf    # → gcc15-builder-armhf
```

If `artifacts/toolchain-<arch>.tar.gz` already exists, the toolchain is not rebuilt.
Changing `BUILDER_BASE_IMAGE` in `platforms.conf` and re-running only rebuilds the
sysroot and dependency layers — the toolchain layer stays cached.

The toolchain tarball contains **host-native** GCC/binutils (e.g. linux/arm64 on
Apple Silicon). If you see `...-gcc: not found` inside the builder, delete the
matching artifact under `artifacts/` and run `make toolchain-<arch>` again on
this host so the compiler matches your machine.

## Configuration

Edit `platforms.conf` to add or modify target architectures:

```
# ARCH_NAME|TARGET_TRIPLET|SYSROOT_NAME|DOCKER_PLATFORM|BASE_IMAGE|BUILDER_BASE_IMAGE|CMAKE_PROCESSOR|CMAKE_FLAGS
armhf|arm-linux-gnueabihf|sysroot-armhf|linux/arm/v7|dilshodm/ubuntu:12.04|ubuntu:20.04|arm|-march=armv7-a ...
```

- `BASE_IMAGE` — base for the toolchain sysroot (old glibc for compatibility)
- `BUILDER_BASE_IMAGE` — base for the builder sysroot (arbitrary target platform)

## Host platform

The toolchain and builder images run on the host's native architecture. On an
Apple M4 (arm64), the cross-compilers are arm64 binaries that produce code for
the target platforms. On an x64 machine, the same Dockerfiles produce x64
cross-compiler binaries. No code changes are needed to switch hosts.
