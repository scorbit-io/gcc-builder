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
- **Builder sysroot** (`BUILDER_SYSROOT_DOCKERFILE` in `platforms.conf`) — per-arch
  Dockerfile in `builder-sysroots/`. Used in the builder image for cross-compilation.

Library build scripts live in `scripts/deps/` and are executed inside the builder image.

All architecture parameters are driven by `platforms.conf`.

## Quick start

Create a `DOCKER_RELEASE` file (one line, e.g. `12`) or pass `DOCKER_RELEASE=12` on the
`make` command line. That value becomes the tag suffix on published builder images
(`dilshodm/ubuntu-builder-arm:12.04_12`, and so on).

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

CMake does **not** read `CMAKE_TOOLCHAIN_FILE` from the environment; you must
pass **`-DCMAKE_TOOLCHAIN_FILE=$CMAKE_TOOLCHAIN_FILE`** on the **`cmake`**
command line so nested `FetchContent` / CPM projects inherit cross settings.

The toolchain file includes all compiler/binutils paths, sysroot, dependency
search paths, **`-static-libgcc`** for C and **`-static-libstdc++ -static-libgcc`**
for C++ (glibc stays dynamic), and for **armhf** appends **static libatomic** via
`CMAKE_*_STANDARD_LIBRARIES` so it appears **after** static archives such as
`libcrypto.a` (link order matters). Binaries then do not need `libatomic.so` on
the device.

The image also sets `CFLAGS` / `CXXFLAGS` to the same static-lib defaults for
plain `gcc` / `g++` invocations. Override or clear them if you need fully
dynamic C++ runtime.

For **autotools** in the armhf image, `/etc/profile.d/gcc15-armhf-libatomic.sh`
sets `LIBS` (appended last by `configure`/`make`), not `LDFLAGS`. For a one-off
build you can use:

`LIBS="-Wl,-Bstatic -latomic -Wl,-Bdynamic" ./configure --host=$CROSS_TARGET`

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
| `CMAKE_TOOLCHAIN_FILE` | `/opt/toolchain/armhf.cmake`                   |
| `CFLAGS`               | `-static-libgcc`                               |
| `CXXFLAGS`             | `-static-libstdc++ -static-libgcc`           |

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

Published tags use `DOCKER_RELEASE` (file `DOCKER_RELEASE` or `make DOCKER_RELEASE=…`)
as the suffix after the Ubuntu version, for example `12.04_12` when `DOCKER_RELEASE` is `12`.

```bash
make builder-armhf    # → dilshodm/ubuntu-builder-arm:12.04_<release>  (+ gcc15-builder-armhf alias)
make builder-amd64    # → dilshodm/ubuntu-builder-amd64:20.04_<release> (+ gcc15-builder-amd64)
make builder-arm64    # → dilshodm/ubuntu-builder-arm64:20.04_<release> (+ gcc15-builder-arm64)
```

If `artifacts/toolchain-<arch>.tar.gz` already exists, the toolchain is not rebuilt.
Changing the builder sysroot Dockerfile and re-running only rebuilds the sysroot
and dependency layers — the toolchain layer stays cached.

The toolchain tarball contains **host-native** GCC/binutils (e.g. linux/arm64 on
Apple Silicon). If you see `...-gcc: not found` inside the builder, delete the
matching artifact under `artifacts/` and run `make toolchain-<arch>` again on
this host so the compiler matches your machine.

## Configuration

Edit `platforms.conf` to add or modify target architectures:

```
# ARCH_NAME|TARGET_TRIPLET|SYSROOT_NAME|DOCKER_PLATFORM|BASE_IMAGE|BUILDER_SYSROOT_DOCKERFILE|CMAKE_PROCESSOR|CMAKE_FLAGS
armhf|arm-linux-gnueabihf|sysroot-armhf|linux/arm/v7|dilshodm/ubuntu:12.04|builder-sysroots/Dockerfile.ubuntu12|arm|-march=armv7-a ...
```

- `BASE_IMAGE` — base for the toolchain sysroot (old glibc for compatibility)
- `BUILDER_SYSROOT_DOCKERFILE` — Dockerfile that produces the builder sysroot image

## Host platform

The toolchain and builder images run on the host's native architecture. On an
Apple M4 (arm64), the cross-compilers are arm64 binaries that produce code for
the target platforms. On an x64 machine, the same Dockerfiles produce x64
cross-compiler binaries. No code changes are needed to switch hosts.
