# GCC 15 Cross-Toolchain

Multi-architecture GCC 15 cross-compilation toolchain targeting:

| Arch  | Triple                  | Toolchain Sysroot      | Target Sysroot   |
|-------|-------------------------|------------------------|------------------|
| armhf | arm-linux-gnueabihf     | Ubuntu 12.04 (armv7)   | Ubuntu 12.04     |
| amd64 | x86_64-linux-gnu        | Ubuntu 14.04 (amd64)   | Ubuntu 20.04     |
| arm64 | aarch64-linux-gnu       | Ubuntu 14.04 (arm64)   | Ubuntu 20.04     |

## Architecture

The build is split into layers, each with its own Dockerfile:

```
Layer 1a  toolchain-sysroots/Dockerfile   Minimal sysroot for GCC build (old glibc)
Layer 1b  sysroots/Dockerfile.*           Target sysroot for the builder image
Layer 2   toolchain/Dockerfile            Builds GCC cross-compiler → tar.gz archive
Layer 3   builder/Dockerfile              Toolchain + target sysroot + cross-compiled dependencies
```

Two separate sysroot images are built per architecture:

- **Toolchain sysroot** (`BASE_IMAGE` in `platforms.conf`) — old Ubuntu for building GCC
  against a low glibc. Can be deleted after the toolchain artifact is produced.
  Docker image tag: `gcc-toolchain-sysroot-<arch>` (with `IMAGE_PREFIX` from the Makefile).
- **Target sysroot** (`SYSROOT_DOCKERFILE` in `platforms.conf`) — per-arch Dockerfile in
  `sysroots/`. Used in the builder image for cross-compilation. Docker image tag:
  `gcc-sysroot-<arch>`.

Library build scripts live in `scripts/deps/` and are executed inside the builder image.

All architecture parameters are driven by `platforms.conf`.

## Quick start

Create a `DOCKER_RELEASE` file (one line, e.g. `12`) or pass `DOCKER_RELEASE=12` on the
`make` command line. That value becomes the tag on published builder images
(e.g. `gcc-builder-armhf:12.04_12`, or `dilshodm/gcc-builder-armhf:12.04_12` if you set
`DOCKER_USER=dilshodm`).

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

For **autotools** in the armhf image, `/etc/profile.d/gcc-armhf-libatomic.sh`
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

# Target sysroots (used inside the builder image)
make sysroot-armhf
```

### 2. Toolchain archives

```bash
make toolchain-armhf  # → artifacts/toolchain-armhf.tar.gz
```

Toolchain sysroot docker images can be removed after this step.

### 3. Builder images

Published tags use `DOCKER_RELEASE` (file `DOCKER_RELEASE` or `make DOCKER_RELEASE=…`)
as the image tag, for example `12.04_12` when `DOCKER_RELEASE` is `12`. The same build
also tags `gcc-builder-<arch>:latest` for convenience.

Optional **`DOCKER_USER`** (e.g. `make DOCKER_USER=dilshodm`) prefixes the published
image names with `user/`. Without it, images are `gcc-builder-<arch>:<ubuntu>_<release>` only.

```bash
make builder-armhf    # → gcc-builder-armhf:12.04_<release>  (+ gcc-builder-armhf:latest)
make builder-amd64    # → gcc-builder-amd64:20.04_<release> (+ gcc-builder-amd64:latest)
make builder-arm64    # → gcc-builder-arm64:20.04_<release> (+ gcc-builder-arm64:latest)
# With registry user: make DOCKER_USER=dilshodm builder-armhf
#   → dilshodm/gcc-builder-armhf:12.04_<release> (+ gcc-builder-armhf:latest)
```

If `artifacts/toolchain-<arch>.tar.gz` already exists, the toolchain is not rebuilt.
Changing the target sysroot Dockerfile and re-running only rebuilds the sysroot
and dependency layers — the toolchain layer stays cached.

The toolchain tarball contains **host-native** GCC/binutils (e.g. linux/arm64 on
Apple Silicon). If you see `...-gcc: not found` inside the builder, delete the
matching artifact under `artifacts/` and run `make toolchain-<arch>` again on
this host so the compiler matches your machine.

## Configuration

- **`DOCKER_USER`** — optional. When set (e.g. `DOCKER_USER=dilshodm`), published builder
  tags are `user/gcc-builder-armhf:…`, `user/gcc-builder-amd64:…`, etc. When unset,
  tags are unprefixed (`gcc-builder-armhf:…`, …). An additional `:latest` tag is
  always applied on the same image.

Edit `platforms.conf` to add or modify target architectures:

```
# ARCH_NAME|TARGET_TRIPLET|SYSROOT_NAME|DOCKER_PLATFORM|BASE_IMAGE|SYSROOT_DOCKERFILE|CMAKE_PROCESSOR|CMAKE_FLAGS
armhf|arm-linux-gnueabihf|sysroot-armhf|linux/arm/v7|dilshodm/ubuntu:12.04|sysroots/Dockerfile.ubuntu12|arm|-march=armv7-a ...
```

- `BASE_IMAGE` — base for the toolchain sysroot (old glibc for compatibility)
- `SYSROOT_DOCKERFILE` — Dockerfile under `sysroots/` for the target sysroot image

## Host platform

The toolchain and builder images run on the host's native architecture. On an
Apple M4 (arm64), the cross-compilers are arm64 binaries that produce code for
the target platforms. On an x64 machine, the same Dockerfiles produce x64
cross-compiler binaries. No code changes are needed to switch hosts.
