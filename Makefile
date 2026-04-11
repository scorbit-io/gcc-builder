# GCC 15 Cross-Toolchain Build System
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
ifneq ($(filter-out help clean clean-all,$(MAKECMDGOALS)),)
$(error Set DOCKER_RELEASE=… on the command line, create $(DOCKER_RELEASE_FILE), or use .env — run `make help`)
endif
endif

BUILDER_TAG := $(DOCKER_REPO_PREFIX)gcc-builder:$(DOCKER_RELEASE)

BINUTILS_VERSION ?= 2.45
GCC_VERSION      ?= 15.2.0
HOST_UBUNTU      ?=22.04

ifndef HOST_LINUX_PLATFORM
ifneq ($(strip $(DOCKER_HOST_PLATFORM)),)
HOST_LINUX_PLATFORM := $(strip $(DOCKER_HOST_PLATFORM))
else
UNAME_M := $(shell uname -m)
ifeq ($(UNAME_M),aarch64)
HOST_LINUX_PLATFORM := linux/arm64
else ifeq ($(UNAME_M),arm64)
HOST_LINUX_PLATFORM := linux/arm64
else ifeq ($(UNAME_M),x86_64)
HOST_LINUX_PLATFORM := linux/amd64
else
HOST_LINUX_PLATFORM := linux/$(UNAME_M)
endif
endif
endif

# Helper: extract a field from platforms.conf
platform = $(shell scripts/parse-platform.sh $(1) $(2))

# -------------------------------------------------------
# Phony targets
# -------------------------------------------------------
.PHONY: help all toolchains builder clean clean-all push

.DEFAULT_GOAL := help

.SECONDARY: $(addprefix toolchain-sysroot-,$(ARCHES)) $(addprefix sysroot-,$(ARCHES))

help:
	@echo 'GCC cross-toolchain — common targets'
	@echo ''
	@echo '  all             All toolchain archives, then unified builder image'
	@echo '  toolchains      artifacts/toolchain-<arch>.tar.gz for each arch'
	@echo '  builder         Unified builder image with all 3 architectures'
	@echo '  clean           Remove intermediate gcc-toolchain-sysroot-* / gcc-sysroot-* images only'
	@echo '  clean-all       Same as clean, plus delete artifacts/'
	@echo '  push            docker push the builder tag (requires docker login; set DOCKER_USER)'
	@echo ''
	@echo 'Per-arch pattern targets (arch: $(ARCHES)):'
	@echo '  toolchain-sysroot-<arch>   Old-glibc sysroot image for GCC build'
	@echo '  sysroot-<arch>             Target sysroot image for the builder'
	@echo '  toolchain-<arch>           Cross toolchain tarball'
	@echo ''
	@echo 'Configuration (need DOCKER_RELEASE for any build except clean/clean-all/help):'
	@echo '  .env (see .env.example), file $(DOCKER_RELEASE_FILE), or DOCKER_RELEASE=… on the command line'
	@echo '  Optional: DOCKER_USER, DOCKER_HOST_PLATFORM, BINUTILS_VERSION, GCC_VERSION, HOST_LINUX_PLATFORM, HOST_UBUNTU'
	@echo ''
	@echo 'See README.md for full documentation.'

all: toolchains builder

toolchains: $(addprefix toolchain-,$(ARCHES))

# Push the unified builder image to the default registry.
push:
ifeq ($(strip $(DOCKER_USER)),)
	@echo 'Warning: DOCKER_USER is unset; pushing unprefixed name (Docker Hub usually needs user/repo).' >&2
endif
	docker push $(BUILDER_TAG)

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
	mkdir -p $(ARTIFACTS_DIR)
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
		| gzip > "$(ARTIFACTS_DIR)/toolchain-$*.tar.gz.tmp" && \
		mv "$(ARTIFACTS_DIR)/toolchain-$*.tar.gz.tmp" "$(ARTIFACTS_DIR)/toolchain-$*.tar.gz"'

# -------------------------------------------------------
# Layer 3: Unified builder image (all architectures)
# -------------------------------------------------------
builder: $(addprefix sysroot-,$(ARCHES))
	@for a in $(ARCHES); do \
		if [ -f "$(ARTIFACTS_DIR)/toolchain-$$a.tar.gz" ] && ! gzip -t "$(ARTIFACTS_DIR)/toolchain-$$a.tar.gz" 2>/dev/null; then \
			echo "Corrupt toolchain archive for $$a (gzip -t failed); removing and rebuilding..."; \
			rm -f "$(ARTIFACTS_DIR)/toolchain-$$a.tar.gz"; \
		fi; \
		if [ ! -f "$(ARTIFACTS_DIR)/toolchain-$$a.tar.gz" ]; then \
			echo "Toolchain artifact not found, building toolchain-$$a..."; \
			$(MAKE) toolchain-$$a; \
		fi; \
	done
	docker buildx build --load \
		--platform=$(HOST_LINUX_PLATFORM) \
		-f builder/Dockerfile \
		--build-arg IMAGE_PREFIX=$(IMAGE_PREFIX) \
		--build-arg HOST_PLATFORM=$(HOST_LINUX_PLATFORM) \
		--build-arg HOST_UBUNTU=$(HOST_UBUNTU) \
		-t $(BUILDER_TAG) \
		.

# -------------------------------------------------------
# Cleanup
# -------------------------------------------------------
clean:
	@for a in $(ARCHES); do \
		docker rmi $(IMAGE_PREFIX)-toolchain-sysroot-$$a 2>/dev/null || true; \
		docker rmi $(IMAGE_PREFIX)-sysroot-$$a 2>/dev/null || true; \
	done

clean-all: clean
	rm -rf $(ARTIFACTS_DIR)
