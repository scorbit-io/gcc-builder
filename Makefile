# GCC 16 Cross-Toolchain Build System
#
# Builds cross-compilers for armhf/amd64/arm64 and a single unified builder image.
#
# Layers:
#   1a. toolchain-sysroot-<arch> – minimal sysroot for GCC build (old glibc)
#   1b. sysroot-<arch>            – target sysroot for builder (arbitrary base image)
#   2.  toolchain-<arch>         – builds GCC cross-compiler, exports tar.gz archive
#   3.  builder                  – single image with all toolchains + sysroots + dependencies
#
# Examples:
#   make all                 # build toolchains then builder
#   make builder             # build unified builder image (auto-builds toolchains if needed)
#   make toolchains          # build all toolchain archives only
#   make toolchain-armhf     # build one toolchain archive
#
# Optional local overrides: copy .env.example to .env (see .gitignore).

-include .env

ARCHES        := armhf amd64 arm64
IMAGE_PREFIX  := gcc
ARTIFACTS_DIR := artifacts

# Optional Docker Hub (or registry) user/namespace for published builder tags.
DOCKER_USER ?=
DOCKER_REPO_PREFIX := $(if $(strip $(DOCKER_USER)),$(DOCKER_USER)/,)

# Suffix for published builder tag, e.g. gcc-builder:1 or user/gcc-builder:1
DOCKER_RELEASE_FILE ?= DOCKER_RELEASE
DOCKER_RELEASE      ?= $(shell cat $(DOCKER_RELEASE_FILE) 2>/dev/null | tr -d ' \t\n\r')
ifeq ($(DOCKER_RELEASE),)
# Musl tarball/sysroot targets do not need a release tag (builder-musl / push-musl still do).
DOCKER_RELEASE_EXEMPT := help clean clean-all \
	musl-toolchains \
	musl-toolchain-armhf musl-toolchain-armel musl-toolchain-arm64 \
	musl-toolchain-sysroot-armhf musl-toolchain-sysroot-armel musl-toolchain-sysroot-arm64 \
	musl-sysroot-armhf musl-sysroot-armel musl-sysroot-arm64
ifneq ($(filter-out $(DOCKER_RELEASE_EXEMPT),$(MAKECMDGOALS)),)
$(error Set DOCKER_RELEASE=… on the command line, create $(DOCKER_RELEASE_FILE), or use .env — run `make help`)
endif
endif

BUILDER_TAG        := $(DOCKER_REPO_PREFIX)gcc-builder:$(DOCKER_RELEASE)
PYTHON_BUILDER_TAG := $(DOCKER_REPO_PREFIX)python-builder:$(DOCKER_RELEASE)

BINUTILS_VERSION ?= 2.45
GCC_VERSION      ?= 16.1.0
HOST_UBUNTU      ?=22.04

comma := ,
empty :=
space := $(empty) $(empty)

# Single host platform for local builds (first linux/* token if comma-separated).
ifneq ($(strip $(DOCKER_HOST_PLATFORM)),)
_host_plat_src := $(strip $(DOCKER_HOST_PLATFORM))
else ifneq ($(strip $(HOST_LINUX_PLATFORM)),)
_host_plat_src := $(strip $(HOST_LINUX_PLATFORM))
else
UNAME_M := $(shell uname -m)
ifeq ($(UNAME_M),aarch64)
_host_plat_src := linux/arm64
else ifeq ($(UNAME_M),arm64)
_host_plat_src := linux/arm64
else ifeq ($(UNAME_M),x86_64)
_host_plat_src := linux/amd64
else
_host_plat_src := linux/$(UNAME_M)
endif
endif
platform_slug = $(subst /,-,$(1))
host_arch     = $(lastword $(subst /,$(space),$(1)))
first_linux_platform = $(firstword $(subst $(comma),$(space),$(strip $(1))))
HOST_LINUX_PLATFORM := $(call first_linux_platform,$(_host_plat_src))
ifeq ($(HOST_LINUX_PLATFORM),)
$(error Could not resolve HOST_LINUX_PLATFORM from "$(_host_plat_src)")
endif
ifneq ($(findstring linux/,$(HOST_LINUX_PLATFORM)),linux/)
$(error HOST_LINUX_PLATFORM must look like linux/amd64 or linux/arm64, got "$(HOST_LINUX_PLATFORM)")
endif

HOST_PLATFORM_SLUG     := $(call platform_slug,$(HOST_LINUX_PLATFORM))
HOST_ARCH              := $(call host_arch,$(HOST_LINUX_PLATFORM))
ARTIFACTS_PLATFORM_DIR := $(ARTIFACTS_DIR)/$(HOST_PLATFORM_SLUG)

BUILDER_TAG_ARCH        := $(DOCKER_REPO_PREFIX)gcc-builder:$(DOCKER_RELEASE)-$(HOST_ARCH)
PYTHON_BUILDER_TAG_ARCH := $(DOCKER_REPO_PREFIX)python-builder:$(DOCKER_RELEASE)-$(HOST_ARCH)

# Helper: extract a field from platforms.conf
platform = $(shell scripts/parse-platform.sh $(1) $(2))

# -------------------------------------------------------
# Phony targets
# -------------------------------------------------------
MUSL_ARCHES := armhf armel arm64
PLATFORMS_MUSL := platforms-musl.conf
# musl-$(stem) e.g. musl-armhf — arch keys in platforms-musl.conf
platform_musl = $(shell scripts/parse-platform.sh musl-$(1) $(2) $(PLATFORMS_MUSL))

MUSL_BUILDER_TAG      := $(DOCKER_REPO_PREFIX)gcc-builder-musl:$(DOCKER_RELEASE)
MUSL_BUILDER_TAG_ARCH := $(DOCKER_REPO_PREFIX)gcc-builder-musl:$(DOCKER_RELEASE)-$(HOST_ARCH)

.PHONY: help all toolchains builder builder-musl python-builder musl-toolchains clean clean-all \
	push push-musl push-python manifest manifest-python manifest-musl

.DEFAULT_GOAL := help

.SECONDARY: $(addprefix toolchain-sysroot-,$(ARCHES)) $(addprefix sysroot-,$(ARCHES))

help:
	@echo 'GCC cross-toolchain — common targets'
	@echo ''
	@echo '  all             Toolchains, gcc-builder, and python-builder for this host platform'
	@echo '  toolchains      artifacts/<platform-slug>/toolchain-<arch>.tar.gz for each arch'
	@echo '  builder         Unified builder image with all 3 architectures'
	@echo '  python-builder  Slim image for Python 3 / 2.7 wheel packaging (pip, setuptools, wheel)'
	@echo '  builder-musl    gcc-builder-musl image (Debian bookworm musl sysroots, armhf + armel + arm64, static defaults)'
	@echo '  musl-toolchains musl cross-compiler tarballs only (musl-toolchain-<cpu>.tar.gz)'
	@echo '  clean           Remove intermediate gcc-toolchain-sysroot-* / gcc-sysroot-* images only'
	@echo '  clean-all       Same as clean, plus delete artifacts/'
	@echo '  push            docker push gcc-builder:$(DOCKER_RELEASE)-<host-arch> for this host'
	@echo '  push-python     docker push python-builder:$(DOCKER_RELEASE)-<host-arch>'
	@echo '  push-musl       docker push gcc-builder-musl:$(DOCKER_RELEASE)-<host-arch>'
	@echo '  manifest        Merge pushed per-arch gcc-builder tags into :$(DOCKER_RELEASE) (imagetools)'
	@echo '  manifest-python / manifest-musl   Same for python-builder / gcc-builder-musl'
	@echo ''
	@echo 'Per-arch pattern targets (arch: $(ARCHES)):'
	@echo '  toolchain-sysroot-<arch>   Old-glibc sysroot image for GCC build'
	@echo '  sysroot-<arch>             Target sysroot image for the builder'
	@echo '  toolchain-<arch>           Cross toolchain tarball'
	@echo ''
	@echo 'Configuration: set DOCKER_RELEASE (file $(DOCKER_RELEASE_FILE) or .env). Not required for: help, clean*, musl-toolchains, musl-toolchain-*, musl-sysroot-*, musl-toolchain-sysroot-*.'
	@echo '  .env (see .env.example), file $(DOCKER_RELEASE_FILE), or DOCKER_RELEASE=… on the command line'
	@echo '  Optional: DOCKER_USER, DOCKER_HOST_PLATFORM, BINUTILS_VERSION, GCC_VERSION, HOST_LINUX_PLATFORM, HOST_UBUNTU'
	@echo ''
	@echo 'See README.md for full documentation.'

all: toolchains builder python-builder

musl-toolchains: $(addprefix musl-toolchain-,$(MUSL_ARCHES))

builder-musl: $(addprefix musl-sysroot-,$(MUSL_ARCHES))
	@set -e; for a in $(MUSL_ARCHES); do \
		art="$(ARTIFACTS_PLATFORM_DIR)/musl-toolchain-$$a.tar.gz"; \
		if [ -f "$$art" ] && ! gzip -t "$$art" 2>/dev/null; then \
			echo "Corrupt musl toolchain archive for $$a; removing..."; \
			rm -f "$$art"; \
		fi; \
		if [ ! -f "$$art" ]; then \
			echo "Musl toolchain artifact not found, building musl-toolchain-$$a..."; \
			$(MAKE) musl-toolchain-$$a; \
		fi; \
		test -f "$$art" || { echo "Missing musl toolchain archive after build: $$art" >&2; exit 1; }; \
	done
	docker buildx build --load \
		--platform=$(HOST_LINUX_PLATFORM) \
		-f builder/Dockerfile.musl \
		--build-arg IMAGE_PREFIX=$(IMAGE_PREFIX) \
		--build-arg HOST_PLATFORM=$(HOST_LINUX_PLATFORM) \
		--build-arg HOST_UBUNTU=$(HOST_UBUNTU) \
		--build-arg ARTIFACTS_SUBDIR=$(HOST_PLATFORM_SLUG) \
		-t $(MUSL_BUILDER_TAG_ARCH) \
		.

push-musl:
ifeq ($(strip $(DOCKER_USER)),)
	@echo 'Warning: DOCKER_USER is unset; pushing unprefixed name (Docker Hub usually needs user/repo).' >&2
endif
	docker push $(MUSL_BUILDER_TAG_ARCH)

toolchains: $(addprefix toolchain-,$(ARCHES))

push:
ifeq ($(strip $(DOCKER_USER)),)
	@echo 'Warning: DOCKER_USER is unset; pushing unprefixed name (Docker Hub usually needs user/repo).' >&2
endif
	docker push $(BUILDER_TAG_ARCH)

push-python:
ifeq ($(strip $(DOCKER_USER)),)
	@echo 'Warning: DOCKER_USER is unset; pushing unprefixed name (Docker Hub usually needs user/repo).' >&2
endif
	docker push $(PYTHON_BUILDER_TAG_ARCH)

manifest:
	@set -e; \
	archs="$$(scripts/discover-host-archs.sh $(DOCKER_RELEASE) gcc-builder)"; \
	tags=""; \
	for a in $$archs; do tags="$$tags $(BUILDER_TAG)-$$a"; done; \
	echo "docker buildx imagetools create -t $(BUILDER_TAG)$$tags"; \
	docker buildx imagetools create -t $(BUILDER_TAG) $$tags

manifest-python:
	@set -e; \
	archs="$$(scripts/discover-host-archs.sh $(DOCKER_RELEASE) python-builder)"; \
	tags=""; \
	for a in $$archs; do tags="$$tags $(PYTHON_BUILDER_TAG)-$$a"; done; \
	echo "docker buildx imagetools create -t $(PYTHON_BUILDER_TAG)$$tags"; \
	docker buildx imagetools create -t $(PYTHON_BUILDER_TAG) $$tags

manifest-musl:
	@set -e; \
	archs="$$(scripts/discover-host-archs.sh $(DOCKER_RELEASE) gcc-builder-musl)"; \
	tags=""; \
	for a in $$archs; do tags="$$tags $(MUSL_BUILDER_TAG)-$$a"; done; \
	echo "docker buildx imagetools create -t $(MUSL_BUILDER_TAG)$$tags"; \
	docker buildx imagetools create -t $(MUSL_BUILDER_TAG) $$tags

python-builder:
	docker buildx build --load \
		--platform=$(HOST_LINUX_PLATFORM) \
		-f python-builder/Dockerfile \
		--build-arg HOST_UBUNTU=$(HOST_UBUNTU) \
		-t $(PYTHON_BUILDER_TAG_ARCH) \
		.

# -------------------------------------------------------
# Layer 1a: Toolchain sysroot images (old glibc for GCC build)
# -------------------------------------------------------
toolchain-sysroot-%:
	docker build \
		--platform=$(call platform,$*,platform) \
		--build-arg BASE_IMAGE=$(call platform,$*,base_image) \
		-f toolchain-sysroots/Dockerfile \
		-t $(IMAGE_PREFIX)-toolchain-sysroot-$* \
		toolchain-sysroots/

# -------------------------------------------------------
# Layer 1b: Target sysroot images for the builder (per-arch Dockerfile)
# -------------------------------------------------------
sysroot-%:
	docker build \
		--platform=$(call platform,$*,platform) \
		-f $(call platform,$*,sysroot_dockerfile) \
		-t $(IMAGE_PREFIX)-sysroot-$* \
		sysroots/

# -------------------------------------------------------
# Layer 2: Toolchain builds → tar.gz archives
# -------------------------------------------------------
toolchain-%: toolchain-sysroot-%
	mkdir -p $(ARTIFACTS_PLATFORM_DIR)
	bash -c 'set -euo pipefail; \
		docker buildx build \
			--platform=$(HOST_LINUX_PLATFORM) \
			-f toolchain/Dockerfile \
			--build-arg SYSROOT_IMAGE=$(IMAGE_PREFIX)-toolchain-sysroot-$* \
			--build-arg SYSROOT_PLATFORM=$(call platform,$*,platform) \
			--build-arg HOST_PLATFORM=$(HOST_LINUX_PLATFORM) \
			--build-arg HOST_UBUNTU=$(HOST_UBUNTU) \
			--build-arg ARCH_NAME=$* \
			--build-arg SYSROOT_NAME=$(call platform,$*,sysroot) \
			--build-arg BINUTILS_VERSION=$(BINUTILS_VERSION) \
			--build-arg GCC_VERSION=$(GCC_VERSION) \
			--target export \
			--output type=tar,dest=- . \
		| gzip > "$(ARTIFACTS_PLATFORM_DIR)/toolchain-$*.tar.gz.tmp" && \
		mv "$(ARTIFACTS_PLATFORM_DIR)/toolchain-$*.tar.gz.tmp" "$(ARTIFACTS_PLATFORM_DIR)/toolchain-$*.tar.gz"'

# -------------------------------------------------------
# Layer 3: Unified builder image (all architectures)
# -------------------------------------------------------
builder: $(addprefix sysroot-,$(ARCHES))
	@set -e; for a in $(ARCHES); do \
		art="$(ARTIFACTS_PLATFORM_DIR)/toolchain-$$a.tar.gz"; \
		if [ -f "$$art" ] && ! gzip -t "$$art" 2>/dev/null; then \
			echo "Corrupt toolchain archive for $$a (gzip -t failed); removing and rebuilding..."; \
			rm -f "$$art"; \
		fi; \
		if [ ! -f "$$art" ]; then \
			echo "Toolchain artifact not found, building toolchain-$$a..."; \
			$(MAKE) toolchain-$$a; \
		fi; \
		test -f "$$art" || { echo "Missing toolchain archive after build: $$art" >&2; exit 1; }; \
	done
	docker buildx build --load \
		--platform=$(HOST_LINUX_PLATFORM) \
		-f builder/Dockerfile \
		--build-arg IMAGE_PREFIX=$(IMAGE_PREFIX) \
		--build-arg HOST_PLATFORM=$(HOST_LINUX_PLATFORM) \
		--build-arg HOST_UBUNTU=$(HOST_UBUNTU) \
		--build-arg ARTIFACTS_SUBDIR=$(HOST_PLATFORM_SLUG) \
		-t $(BUILDER_TAG_ARCH) \
		.

# -------------------------------------------------------
# Cleanup
# -------------------------------------------------------
# Musl layer 1a / 1b / 2 (names chosen so they do not match toolchain-% / sysroot-% patterns)
# Musl toolchain sysroots: Debian bookworm-slim (arm32v7 armhf, arm32v5 armel, arm64v8 arm64).
musl-toolchain-sysroot-armhf:
	docker build \
		--platform=$(call platform_musl,armhf,platform) \
		-f toolchain-sysroots/Dockerfile.debian-musl-armhf \
		-t $(IMAGE_PREFIX)-musl-toolchain-sysroot-armhf \
		toolchain-sysroots/

musl-toolchain-sysroot-armel:
	docker build \
		--platform=$(call platform_musl,armel,platform) \
		-f toolchain-sysroots/Dockerfile.debian-musl-armel \
		-t $(IMAGE_PREFIX)-musl-toolchain-sysroot-armel \
		toolchain-sysroots/

musl-toolchain-sysroot-arm64:
	docker build \
		--platform=$(call platform_musl,arm64,platform) \
		-f toolchain-sysroots/Dockerfile.debian-musl-arm64 \
		-t $(IMAGE_PREFIX)-musl-toolchain-sysroot-arm64 \
		toolchain-sysroots/

musl-sysroot-armhf:
	docker build \
		--platform=$(call platform_musl,armhf,platform) \
		-f sysroots/Dockerfile.debian-musl-armhf \
		-t $(IMAGE_PREFIX)-musl-sysroot-armhf \
		sysroots/

musl-sysroot-armel:
	docker build \
		--platform=$(call platform_musl,armel,platform) \
		-f sysroots/Dockerfile.debian-musl-armel \
		-t $(IMAGE_PREFIX)-musl-sysroot-armel \
		sysroots/

musl-sysroot-arm64:
	docker build \
		--platform=$(call platform_musl,arm64,platform) \
		-f sysroots/Dockerfile.debian-musl-arm64 \
		-t $(IMAGE_PREFIX)-musl-sysroot-arm64 \
		sysroots/

musl-toolchain-%: musl-toolchain-sysroot-%
	mkdir -p $(ARTIFACTS_PLATFORM_DIR)
	bash -c 'set -euo pipefail; \
		docker buildx build \
			--platform=$(HOST_LINUX_PLATFORM) \
			-f toolchain/Dockerfile \
			--build-arg SYSROOT_IMAGE=$(IMAGE_PREFIX)-musl-toolchain-sysroot-$* \
			--build-arg SYSROOT_PLATFORM=$(call platform_musl,$*,platform) \
			--build-arg HOST_PLATFORM=$(HOST_LINUX_PLATFORM) \
			--build-arg HOST_UBUNTU=$(HOST_UBUNTU) \
			--build-arg ARCH_NAME=musl-$* \
			--build-arg SYSROOT_NAME=$(call platform_musl,$*,sysroot) \
			--build-arg BINUTILS_VERSION=$(BINUTILS_VERSION) \
			--build-arg GCC_VERSION=$(GCC_VERSION) \
			--build-arg PLATFORMS_FILE=$(PLATFORMS_MUSL) \
			--target export \
			--output type=tar,dest=- . \
		| gzip > "$(ARTIFACTS_PLATFORM_DIR)/musl-toolchain-$*.tar.gz.tmp" && \
		mv "$(ARTIFACTS_PLATFORM_DIR)/musl-toolchain-$*.tar.gz.tmp" "$(ARTIFACTS_PLATFORM_DIR)/musl-toolchain-$*.tar.gz"'

clean:
	@for a in $(ARCHES); do \
		docker rmi $(IMAGE_PREFIX)-toolchain-sysroot-$$a 2>/dev/null || true; \
		docker rmi $(IMAGE_PREFIX)-sysroot-$$a 2>/dev/null || true; \
	done
	@for a in $(MUSL_ARCHES); do \
		docker rmi $(IMAGE_PREFIX)-musl-toolchain-sysroot-$$a 2>/dev/null || true; \
		docker rmi $(IMAGE_PREFIX)-musl-sysroot-$$a 2>/dev/null || true; \
	done

clean-all: clean
	rm -rf $(ARTIFACTS_DIR)
