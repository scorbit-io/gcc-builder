# GCC 16 Cross-Toolchain

Multi-architecture GCC 16 cross-compilation toolchain targeting:


| Arch  | Triple              | Toolchain Sysroot    | Target Sysroot |
| ----- | ------------------- | -------------------- | -------------- |
| armhf | arm-linux-gnueabihf | Ubuntu 12.04 (armv7) | Ubuntu 12.04   |
| amd64 | x86_64-linux-gnu    | Ubuntu 14.04 (amd64) | Ubuntu 18.04   |
| arm64 | aarch64-linux-gnu   | Ubuntu 14.04 (arm64) | Ubuntu 18.04   |


## Architecture

The build is split into layers, each with its own Dockerfile:

```
Layer 1a  toolchain-sysroots/Dockerfile   Minimal sysroot for GCC build (old glibc)
Layer 1b  sysroots/Dockerfile.*           Target sysroot for the builder image
Layer 2   toolchain/Dockerfile            Builds GCC cross-compiler → tar.gz archive
Layer 3   builder/Dockerfile              Unified image: all toolchains + sysroots + deps
python-builder/Dockerfile                 Slim image: Python 3 + 2.7, pip, wheel tooling (independent of layers 1–3)
```

Two separate sysroot images are built per architecture:

- **Toolchain sysroot** (`BASE_IMAGE` in `platforms.conf`) — old Ubuntu for building GCC
against a low glibc. Can be deleted after the toolchain artifact is produced.
Docker image tag: `gcc-toolchain-sysroot-<arch>` (with `IMAGE_PREFIX` from the Makefile).
- **Target sysroot** (`SYSROOT_DOCKERFILE` in `platforms.conf`) — per-arch Dockerfile in
`sysroots/`. Used in the builder image for cross-compilation. Docker image tag:
`gcc-sysroot-<arch>`.

The final builder image (`gcc-builder:<release>`) contains all three architectures.
At runtime, set `ARCH` to select the active toolchain (defaults to `arm64`).

Library build scripts live in `scripts/deps/` and are executed inside the builder image.

All architecture parameters are driven by `platforms.conf`.

### Layout inside the image

```
/opt/
  platforms.conf
  scripts/
  entrypoint.sh
  <arch>/                      (armhf, amd64, arm64)
    toolchain/bin/<triple>-gcc, ...
    sysroot/usr/, ...
    toolchain.cmake
    toolchain.env
```

## Quick start

Set the release suffix for the builder image tag using **one** of:

- `**.env`** (recommended for local use): copy `.env.example` to `.env` and set
`DOCKER_RELEASE=…` (and optionally `DOCKER_USER=…`). The Makefile includes `.env`
automatically; `.env` is listed in `.gitignore`.
- A one-line `**DOCKER_RELEASE**` file in the repo root, or `**DOCKER_RELEASE=12**`
on the `make` command line.

That value becomes the image tag (e.g. `gcc-builder:12` and `python-builder:12`, or
`dilshodm/gcc-builder:12` / `dilshodm/python-builder:12` if `DOCKER_USER` is set).
Each image gets **one** tag (no extra `:latest`).

```bash
# Show targets and configuration hints (default when you run `make` with no arguments)
make
make help

# Build everything (all toolchains, then unified builder)
make all

# Build only toolchain archives (step 1)
make toolchains

# Build the unified builder image (auto-builds toolchains if artifacts missing)
make builder

# Build the Python wheel image (independent of toolchains)
make python-builder

# Remove intermediate sysroot Docker images only (keeps artifacts/ and builder image)
make clean

# Also delete artifacts/ (toolchain tarballs)
make clean-all

# After `docker login`, upload images (see Publishing below)
make push
make push-python
```

### Makefile targets (summary)


| Target       | Purpose                                                                                                                                                                                                     |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| *(default)*  | Same as `help` — lists targets and options (no `DOCKER_RELEASE` needed).                                                                                                                                    |
| `help`       | Same as running `make` with no arguments.                                                                                                                                                                   |
| `all`        | `toolchains` then `builder`.                                                                                                                                                                                |
| `toolchains` | Produce all `artifacts/<platform-slug>/toolchain-<arch>.tar.gz` archives (e.g. `artifacts/linux-amd64/`).                                                                                                      |
| `builder`        | Build the unified builder image with all 3 architectures. Auto-builds missing toolchain artifacts.                                                                                                          |
| `python-builder` | Build the slim Python wheel image (`python-builder:<release>`). Independent of toolchains.                                                                                                                    |
| `clean`          | Removes intermediate Docker images per arch only (`gcc-toolchain-sysroot-<arch>` and `gcc-sysroot-<arch>` when `IMAGE_PREFIX` is the default `gcc`). Does **not** delete `artifacts/` or the builder image. |
| `clean-all`      | Runs `clean`, then deletes `artifacts/`. Does **not** remove the builder image.                                                                                                                             |
| `push`           | Runs `docker push` for the builder tag. Expects the image already built and tagged; requires `docker login`. Set `**DOCKER_USER**` for normal Docker Hub names (`user/gcc-builder:…`).                      |
| `push-python`    | Runs `docker push` for the python-builder tag (same `DOCKER_RELEASE` / `DOCKER_USER` as gcc-builder).                                                                                                       |


## Using gcc-builder from application repos

The unified image is meant to be pulled or built once, then reused from CI or local
CMake projects. Two Scorbit repositories consume it this way:

| Repository   | Typical path                         | Role |
| ------------ | ------------------------------------ | ---- |
| Scorbit SDK  | `~/work/scorbit/scorbit_sdk`         | Linux SDK (`.deb` / `.tar.gz`) via gcc-builder; Python wheels via python-builder |
| scorbitd     | `~/work/scorbit/scorbitd`            | Daemon / service builds for Linux targets |

Both read the image tag from a one-line **`DOCKER_RELEASE`** file at the repo root
(same idea as this project). **`DOCKER_RELEASE` must match** the tag you built or
pulled here (for example `12` → `…/gcc-builder:12` and `…/python-builder:12`).

### 1. Produce the images

From this repository:

```bash
cd ~/work/scorbit/gcc-builder
# Set DOCKER_RELEASE via .env, DOCKER_RELEASE file, or: make DOCKER_RELEASE=12 …
make all              # toolchains + unified builder, or: make builder
make python-builder   # Python 3 + 2.7 wheel image (independent of toolchains)
# Optional: publish (set DOCKER_USER for hub-style names, e.g. dilshodm/gcc-builder:12)
make push
make push-python
```

Use the **same `DOCKER_RELEASE`** for both gcc-builder and python-builder when publishing.

Use the **same host platform** you will use to run Docker in the SDK/scorbitd
repos (`HOST_LINUX_PLATFORM` / `DOCKER_HOST_PLATFORM`; see [Host platform](#host-platform)).
If the consumer machine cannot run the image’s architecture, `docker pull` / `make armhf`
will fail in confusing ways.

### 2. Point the app repo at that tag

- Ensure **`DOCKER_RELEASE`** in `~/work/scorbit/scorbit_sdk/DOCKER_RELEASE` (or
  `~/work/scorbit/scorbitd/DOCKER_RELEASE`) equals the tag you built.
- By default, `scripts/linux-build.sh` uses **`dilshodm/gcc-builder:${REL}`**. If you
  build locally **without** `DOCKER_USER`, your image is `gcc-builder:${REL}` instead;
  change the `DOCKER_IMAGE=…` line in that script (or fork the pattern) to match.

### 3. Run Linux builds from the SDK or scorbitd

**Scorbit SDK** — mounts the tree at `/src`, sets `-e ARCH=…`, and runs
`scripts/build-core.sh` (CMake + Ninja + cpack). Example:

```bash
cd ~/work/scorbit/scorbit_sdk
make armhf        # or: make arm64 / make amd64
# Optional: make python / make python27   # wheels via dilshodm/python-builder:${REL}
```

**scorbitd** — same `scripts/linux-build.sh` / `_common.sh` pattern:

```bash
cd ~/work/scorbit/scorbitd
make armhf        # or: make arm64 / make amd64 (see that repo’s Makefile for default `all`)
```

What happens under the hood (both repos):

1. `scripts/linux-build.sh <arch>` loads `DOCKER_RELEASE`, picks ABI labels per arch,
   and calls `build_using_docker` in `scripts/_common.sh`.
2. `docker_build` runs a container with **`-e ARCH=$ARCH`**, the repo bind-mounted at
   **`/src`**, and `CPM_SOURCE_CACHE` under `build/_cache`.
3. The image **`ENTRYPOINT`** runs `builder/entrypoint.sh`, which sources
   **`/opt/$ARCH/toolchain.env`** so `CC`, `CXX`, `SYSROOT`, **`CMAKE_TOOLCHAIN_FILE`**, etc.
   are set before `bash -c` runs your command.
4. `scripts/build-core.sh` passes **`-DCMAKE_TOOLCHAIN_FILE=…`** explicitly to CMake when
   that variable is set (required for nested dependencies).

If CMake cannot find the compiler, confirm **`docker images`** lists your tag and that
you did not build toolchains on a different CPU than `HOST_LINUX_PLATFORM` implies
(see [Configuration](#configuration) and tarball notes there).


## Using the builder image

The builder image contains cross-toolchains for all three architectures. An entrypoint
script sources `/opt/$ARCH/toolchain.env` to configure the environment for the selected
architecture. The default is `ARCH=amd64`.

```bash
# Run with a specific architecture
docker run -e ARCH=armhf gcc-builder:1 bash

# Default (amd64)
docker run gcc-builder:1 bash
```

The cross-compiler and binutils are on `PATH`; environment variables (`CC`, `CXX`, `AR`,
etc.) are set automatically by the entrypoint.

### CMake

```bash
cmake -DCMAKE_TOOLCHAIN_FILE=$CMAKE_TOOLCHAIN_FILE -Bbuild .
cmake --build build
```

CMake does **not** read `CMAKE_TOOLCHAIN_FILE` from the environment; you must
pass `**-DCMAKE_TOOLCHAIN_FILE=$CMAKE_TOOLCHAIN_FILE`** on the `**cmake**`
command line so nested `FetchContent` / CPM projects inherit cross settings.

The toolchain file includes all compiler/binutils paths, sysroot, dependency
search paths, `**-static-libgcc**` for C and `**-static-libstdc++ -static-libgcc**`
for C++ (glibc stays dynamic), and for **armhf** appends **static libatomic** via
`CMAKE_*_STANDARD_LIBRARIES` so it appears **after** static archives such as
`libcrypto.a` (link order matters). Binaries then do not need `libatomic.so` on
the device.

The entrypoint also sets `CFLAGS` / `CXXFLAGS` to the same static-lib defaults for
plain `gcc` / `g++` invocations. Override or clear them if you need fully
dynamic C++ runtime.

For **autotools** with the armhf arch, `toolchain.env` sets `LIBS` (appended last
by `configure`/`make`), not `LDFLAGS`. For a one-off build you can use:

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

These are set by the entrypoint based on `ARCH` (examples for `ARCH=armhf`):


| Variable               | Example value                      |
| ---------------------- | ---------------------------------- |
| `ARCH_NAME`            | `armhf`                            |
| `CROSS_TARGET`         | `arm-linux-gnueabihf`              |
| `CC`                   | `arm-linux-gnueabihf-gcc`          |
| `CXX`                  | `arm-linux-gnueabihf-g++`          |
| `SYSROOT`              | `/opt/armhf/sysroot`               |
| `CMAKE_TOOLCHAIN_FILE` | `/opt/armhf/toolchain.cmake`       |
| `CFLAGS`               | `-static-libgcc`                   |
| `CXXFLAGS`             | `-static-libstdc++ -static-libgcc` |


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
make toolchain-armhf  # → artifacts/linux-amd64/toolchain-armhf.tar.gz (slug from DOCKER_HOST_PLATFORM)
```

Toolchain sysroot docker images can be removed after this step.

### 3. Builder image

The published tag uses `DOCKER_RELEASE` (`.env`, file `DOCKER_RELEASE`, or
`make DOCKER_RELEASE=…`) as the image tag, for example `gcc-builder:12`.

Optional `**DOCKER_USER**` (e.g. in `.env` or `make DOCKER_USER=dilshodm`) prefixes
the image name with `user/` (e.g. `dilshodm/gcc-builder:12`). Without it,
the tag is unprefixed (`gcc-builder:…`).

```bash
make builder          # → gcc-builder:<release>
# With registry user: make DOCKER_USER=dilshodm builder
#   → dilshodm/gcc-builder:<release>
```

#### Publishing (`make push`)

Run `**docker login**` (Docker Hub or your default registry), then `**make push**`. That
pushes the `BUILDER_TAG` — the same name produced by `**make builder**`.

**Host platform and push:** `docker push` does not choose CPU/OS; it uploads whatever
manifest is already on the tag. If you built with `**DOCKER_HOST_PLATFORM=linux/amd64`**
on macOS, the pushed image is a **linux/amd64** image (runnable on x86_64 hosts). If
you built with the default on Apple Silicon, the pushed image is **linux/arm64**. Pullers
must match the image architecture (or use emulation). Rebuild with the desired
`DOCKER_HOST_PLATFORM` before pushing if you need a different host arch.

If `**DOCKER_USER`** is unset, `make push` still runs but prints a warning; Docker Hub
typically expects repositories under your username (set `DOCKER_USER` in `.env` or on
the command line when building **and** when the tags must match what you push).

If `artifacts/<platform-slug>/toolchain-<arch>.tar.gz` already exists, the toolchain is not rebuilt.
Changing the target sysroot Dockerfile and re-running only rebuilds the sysroot
and dependency layers — the toolchain layer stays cached.

The toolchain tarball contains **host-native** GCC/binutils (e.g. linux/arm64 on
Apple Silicon). If you see `...-gcc: not found` inside the builder, delete the
matching artifact under `artifacts/` and run `make toolchain-<arch>` again on
this host so the compiler matches your machine.

## Configuration

- `**.env`** — optional, gitignored. Copy `.env.example` to `.env` to set `DOCKER_RELEASE`,
`DOCKER_USER`, `**DOCKER_HOST_PLATFORM**` (see Host platform below), or toolchain
overrides (`BINUTILS_VERSION`, `GCC_VERSION`) without passing them on every `make`
invocation.
- `**DOCKER_USER**` — optional. When set (e.g. `DOCKER_USER=dilshodm`), the builder tag is
`user/gcc-builder:…`. When unset, the tag is unprefixed (`gcc-builder:…`).

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

Set `**DOCKER_HOST_PLATFORM`** in `.env` to force the platform when the default does not
match where you will run the builder, for example on an M4 Mac:

```bash
# Build amd64 toolchains + amd64 builder image (for use on x86_64 Linux hosts)
DOCKER_HOST_PLATFORM=linux/amd64
```

Use `linux/arm64` to force AArch64 host binaries. When `DOCKER_HOST_PLATFORM` differs
from your machine's architecture, Docker must emulate the other arch (buildx / QEMU);
builds are slower but the resulting images match the chosen platform.

Equivalent override on one command: `make HOST_LINUX_PLATFORM=linux/amd64 all` (same
variable the Makefile passes through as `HOST_LINUX_PLATFORM` after resolving
`DOCKER_HOST_PLATFORM`).