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

Set the release suffix for builder image tags using **one** of:

- **`.env`** (recommended for local use): copy `.env.example` to `.env` and set
  `DOCKER_RELEASE=…` (and optionally `DOCKER_USER=…`). The Makefile includes `.env`
  automatically; `.env` is listed in `.gitignore`.
- A one-line **`DOCKER_RELEASE`** file in the repo root, or **`DOCKER_RELEASE=12`**
  on the `make` command line.

That value becomes the image tag (e.g. `gcc-builder-armhf:12.04_12`, or
`dilshodm/gcc-builder-armhf:12.04_12` if `DOCKER_USER` is set). Each builder image
gets **one** tag (no extra `:latest`).

```bash
# Show targets and configuration hints (default when you run `make` with no arguments)
make
make help

# Build everything for all architectures (all toolchains, then all builders)
make all

# Build only toolchain archives (step 1)
make toolchains

# Build all builder images for every architecture (same as `make builders`).
# Does not run `toolchains` first; each `builder-*` still builds a missing
# toolchain artifact when needed.
make builder-all

# Build a single-architecture builder (auto-builds toolchain if artifact missing)
make builder-armhf

# Remove intermediate sysroot Docker images only (keeps artifacts/ and builder images)
make clean

# Also delete artifacts/ (toolchain tarballs)
make clean-all

# After `docker login`, upload the three versioned builder tags (see Publishing below)
make push
```

### Makefile targets (summary)

| Target | Purpose |
|--------|---------|
| *(default)* | Same as `help` — lists targets and options (no `DOCKER_RELEASE` needed). |
| `help` | Same as running `make` with no arguments. |
| `all` | `toolchains` then `builders` for every architecture. |
| `toolchains` | Produce all `artifacts/toolchain-<arch>.tar.gz` archives. |
| `builders` | Build all builder images (`builder-armhf`, `builder-amd64`, `builder-arm64`). |
| `builder-all` | Alias for `builders` — use when you only want builder images, not a full `make all`. |
| `clean` | Removes intermediate Docker images per arch only (`gcc-toolchain-sysroot-<arch>` and `gcc-sysroot-<arch>` when `IMAGE_PREFIX` is the default `gcc`). Does **not** delete `artifacts/` or final builder images. |
| `clean-all` | Runs `clean`, then deletes `artifacts/`. Does **not** remove final builder images. |
| `push` | Runs `docker push` for each `BUILDER_TAG` (`armhf`, `amd64`, `arm64`). Expects images already built and tagged; requires `docker login`. Set **`DOCKER_USER`** for normal Docker Hub names (`user/gcc-builder-…`). |

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

Published tags use `DOCKER_RELEASE` (`.env`, file `DOCKER_RELEASE`, or
`make DOCKER_RELEASE=…`) as the image tag, for example `12.04_12` when `DOCKER_RELEASE`
is `12`. Each architecture gets a **single** tag (`<ubuntu>_<release>`), for example
`gcc-builder-armhf:12.04_12` or `gcc-builder-amd64:20.04_12`.

Optional **`DOCKER_USER`** (e.g. in `.env` or `make DOCKER_USER=dilshodm`) prefixes
the image name with `user/` (e.g. `dilshodm/gcc-builder-armhf:12.04_12`). Without it,
tags are unprefixed (`gcc-builder-<arch>:…`).

```bash
make builder-armhf    # → gcc-builder-armhf:12.04_<release>
make builder-amd64    # → gcc-builder-amd64:20.04_<release>
make builder-arm64    # → gcc-builder-arm64:20.04_<release>
# With registry user: make DOCKER_USER=dilshodm builder-armhf
#   → dilshodm/gcc-builder-armhf:12.04_<release>
```

#### Publishing (`make push`)

Run **`docker login`** (Docker Hub or your default registry), then **`make push`**. That
pushes the three tags `$(BUILDER_TAG_armhf)`, `$(BUILDER_TAG_amd64)`, and
`$(BUILDER_TAG_arm64)` — the same names produced by **`builder-*`**.

**Host platform and push:** `docker push` does not choose CPU/OS; it uploads whatever
manifest is already on the tag. If you built with **`DOCKER_HOST_PLATFORM=linux/amd64`**
on macOS, each pushed image is an **linux/amd64** image (runnable on x86_64 hosts). If
you built with the default on Apple Silicon, pushed images are **linux/arm64**. Pullers
must match the image architecture (or use emulation). Rebuild with the desired
`DOCKER_HOST_PLATFORM` before pushing if you need a different host arch.

If **`DOCKER_USER`** is unset, `make push` still runs but prints a warning; Docker Hub
typically expects repositories under your username (set `DOCKER_USER` in `.env` or on
the command line when building **and** when the tags must match what you push).

If `artifacts/toolchain-<arch>.tar.gz` already exists, the toolchain is not rebuilt.
Changing the target sysroot Dockerfile and re-running only rebuilds the sysroot
and dependency layers — the toolchain layer stays cached.

The toolchain tarball contains **host-native** GCC/binutils (e.g. linux/arm64 on
Apple Silicon). If you see `...-gcc: not found` inside the builder, delete the
matching artifact under `artifacts/` and run `make toolchain-<arch>` again on
this host so the compiler matches your machine.

## Configuration

- **`.env`** — optional, gitignored. Copy `.env.example` to `.env` to set `DOCKER_RELEASE`,
  `DOCKER_USER`, **`DOCKER_HOST_PLATFORM`** (see Host platform below), or toolchain
  overrides (`BINUTILS_VERSION`, `GCC_VERSION`) without passing them on every `make`
  invocation.
- **`DOCKER_USER`** — optional. When set (e.g. `DOCKER_USER=dilshodm`), builder tags are
  `user/gcc-builder-armhf:…`, `user/gcc-builder-amd64:…`, etc. When unset, tags are
  unprefixed (`gcc-builder-armhf:…`, …).

Edit `platforms.conf` to add or modify target architectures:

```
# ARCH_NAME|TARGET_TRIPLET|SYSROOT_NAME|DOCKER_PLATFORM|BASE_IMAGE|SYSROOT_DOCKERFILE|CMAKE_PROCESSOR|CMAKE_FLAGS
armhf|arm-linux-gnueabihf|sysroot-armhf|linux/arm/v7|dilshodm/ubuntu:12.04|sysroots/Dockerfile.ubuntu12|arm|-march=armv7-a ...
```

- `BASE_IMAGE` — base for the toolchain sysroot (old glibc for compatibility)
- `SYSROOT_DOCKERFILE` — Dockerfile under `sysroots/` for the target sysroot image

## Host platform

The **toolchain tarball** and **builder image** both embed **host-native** GCC/binutils
for a single Linux platform: `linux/arm64` or `linux/amd64` (see `HOST_PLATFORM` in the
toolchain and builder Dockerfiles). By default the Makefile picks that from `uname`
(Apple Silicon → `linux/arm64`, typical PC → `linux/amd64`).

Set **`DOCKER_HOST_PLATFORM`** in `.env` to force the platform when the default does not
match where you will run the builder, for example on an M4 Mac:

```bash
# Build amd64 toolchains + amd64 builder images (for use on x86_64 Linux hosts)
DOCKER_HOST_PLATFORM=linux/amd64
```

Use `linux/arm64` to force AArch64 host binaries. When `DOCKER_HOST_PLATFORM` differs
from your machine’s architecture, Docker must emulate the other arch (buildx / QEMU);
builds are slower but the resulting images match the chosen platform.

Equivalent override on one command: `make HOST_LINUX_PLATFORM=linux/amd64 all` (same
variable the Makefile passes through as `HOST_LINUX_PLATFORM` after resolving
`DOCKER_HOST_PLATFORM`).
