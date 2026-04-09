# GCC 15 Cross-Toolchain Build System
#
# Builds cross-compilers and per-architecture builder images.
#
# Layers:
#   1a. toolchain-sysroot-<arch> – minimal sysroot for GCC build (old glibc)
#   1b. sysroot-<arch>            – target sysroot for builder (arbitrary base image)
#   2.  toolchain-<arch>         – builds GCC cross-compiler, exports tar.gz archive
#   3.  builder-<arch>           – host image with toolchain + sysroot + dependencies
#
# Examples:
#   make all                 # build toolchains then builders for all architectures
#   make builder-armhf       # build armhf builder (auto-builds toolchain if needed)
#   make toolchains          # build all toolchain archives only
#   make toolchain-armhf     # build one toolchain archive
#
# Optional local overrides: copy .env.example to .env (see .gitignore).

-include .env

ARCHES        := armhf amd64 arm64
IMAGE_PREFIX  := gcc
ARTIFACTS_DIR := artifacts

# Optional Docker Hub (or registry) user/namespace for published builder tags.
# If set: dilshodm/gcc-builder-armhf:12.04_<release>. If empty: gcc-builder-armhf:12.04_<release>
DOCKER_USER ?=
DOCKER_REPO_PREFIX := $(if $(strip $(DOCKER_USER)),$(DOCKER_USER)/,)

# Suffix for published builder tags, e.g. gcc-builder-armhf:12.04_12 or user/gcc-builder-armhf:12.04_12
DOCKER_RELEASE_FILE ?= DOCKER_RELEASE
DOCKER_RELEASE      ?= $(shell cat $(DOCKER_RELEASE_FILE) 2>/dev/null | tr -d ' \t\n\r')
# Bare `make`, `make help`, `make clean`, and `make clean-all` do not need a release.
ifeq ($(DOCKER_RELEASE),)
ifneq ($(filter-out help clean clean-all,$(MAKECMDGOALS)),)
$(error Set DOCKER_RELEASE=… on the command line, create $(DOCKER_RELEASE_FILE), or use .env — run `make help`)
endif
endif

# Final docker image names (Ubuntu version matches toolchain / builder sysroot base)
BUILDER_TAG_armhf := $(DOCKER_REPO_PREFIX)gcc-builder-armhf:12.04_$(DOCKER_RELEASE)
BUILDER_TAG_amd64 := $(DOCKER_REPO_PREFIX)gcc-builder-amd64:20.04_$(DOCKER_RELEASE)
BUILDER_TAG_arm64 := $(DOCKER_REPO_PREFIX)gcc-builder-arm64:20.04_$(DOCKER_RELEASE)

BINUTILS_VERSION ?= 2.45
GCC_VERSION      ?= 15.2.0

# Native linux/* platform for Ubuntu stages that run host binaries (toolchain compile + builder).
# Auto-detected from uname unless overridden:
#   - DOCKER_HOST_PLATFORM in .env (e.g. linux/amd64 to build x86_64 images on Apple Silicon), or
#   - HOST_LINUX_PLATFORM on the make command line.
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
.PHONY: help all toolchains builders builder-all clean clean-all

.DEFAULT_GOAL := help

# Pattern-built docker layers do not create files named sysroot-armhf, etc. Without this,
# GNU Make removes them as "intermediate" files after builder-% runs.
.SECONDARY: $(addprefix toolchain-sysroot-,$(ARCHES)) $(addprefix sysroot-,$(ARCHES))

help:
	@echo 'GCC 15 cross-toolchain — common targets'
	@echo ''
	@echo '  all             All toolchain archives, then all builder images'
	@echo '  toolchains      artifacts/toolchain-<arch>.tar.gz for each arch'
	@echo '  builders        All builder images (armhf, amd64, arm64)'
	@echo '  builder-all     Same as builders (no up-front toolchains; missing tarballs built as needed)'
	@echo '  clean           Remove intermediate gcc-toolchain-sysroot-* / gcc-sysroot-* images only'
	@echo '  clean-all       Same as clean, plus delete artifacts/'
	@echo ''
	@echo 'Per-arch pattern targets (arch: $(ARCHES)):'
	@echo '  toolchain-sysroot-<arch>   Old-glibc sysroot image for GCC build'
	@echo '  sysroot-<arch>             Target sysroot image for the builder'
	@echo '  toolchain-<arch>           Cross toolchain tarball'
	@echo '  builder-<arch>             Final builder image (one versioned tag)'
	@echo ''
	@echo 'Configuration (need DOCKER_RELEASE for any build except clean/clean-all/help):'
	@echo '  .env (see .env.example), file $(DOCKER_RELEASE_FILE), or DOCKER_RELEASE=… on the command line'
	@echo '  Optional: DOCKER_USER, DOCKER_HOST_PLATFORM, BINUTILS_VERSION, GCC_VERSION, HOST_LINUX_PLATFORM'
	@echo ''
	@echo 'See README.md for full documentation.'

all: toolchains builders

toolchains: $(addprefix toolchain-,$(ARCHES))
builders:   $(addprefix builder-,$(ARCHES))

# Build all per-arch builder images only (does not run toolchains up front; each
# builder-* still builds a missing toolchain artifact as needed).
builder-all: builders

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
			--build-arg ARCH_NAME=$* \
			--build-arg SYSROOT_NAME=$(call platform,$*,sysroot) \
			--build-arg BINUTILS_VERSION=$(BINUTILS_VERSION) \
			--build-arg GCC_VERSION=$(GCC_VERSION) \
			--target export \
			--output type=tar,dest=- . \
		| gzip > "$(ARTIFACTS_DIR)/toolchain-$*.tar.gz.tmp" && \
		mv "$(ARTIFACTS_DIR)/toolchain-$*.tar.gz.tmp" "$(ARTIFACTS_DIR)/toolchain-$*.tar.gz"'

# -------------------------------------------------------
# Layer 3: Per-architecture builder images
# Builds toolchain automatically only if artifact is missing.
# -------------------------------------------------------
builder-%: sysroot-%
	@if [ -f "$(ARTIFACTS_DIR)/toolchain-$*.tar.gz" ] && ! gzip -t "$(ARTIFACTS_DIR)/toolchain-$*.tar.gz" 2>/dev/null; then \
		echo "Corrupt toolchain archive (gzip -t failed); removing and rebuilding..."; \
		rm -f "$(ARTIFACTS_DIR)/toolchain-$*.tar.gz"; \
	fi
	@if [ ! -f $(ARTIFACTS_DIR)/toolchain-$*.tar.gz ]; then \
		echo "Toolchain artifact not found, building toolchain-$*..."; \
		$(MAKE) toolchain-$*; \
	fi
	docker buildx build --load \
		--platform=$(HOST_LINUX_PLATFORM) \
		-f builder/Dockerfile \
		--build-arg SYSROOT_IMAGE=$(IMAGE_PREFIX)-sysroot-$* \
		--build-arg SYSROOT_PLATFORM=$(call platform,$*,platform) \
		--build-arg HOST_PLATFORM=$(HOST_LINUX_PLATFORM) \
		--build-arg ARCH_NAME=$* \
		--build-arg SYSROOT_NAME=$(call platform,$*,sysroot) \
		--build-arg TARGET=$(call platform,$*,target) \
		-t $(BUILDER_TAG_$*) \
		.

# -------------------------------------------------------
# Cleanup
# -------------------------------------------------------
# Intermediate images only; keeps artifacts/ and final builder images.
clean:
	@for a in $(ARCHES); do \
		docker rmi $(IMAGE_PREFIX)-toolchain-sysroot-$$a 2>/dev/null || true; \
		docker rmi $(IMAGE_PREFIX)-sysroot-$$a 2>/dev/null || true; \
	done

clean-all: clean
	rm -rf $(ARTIFACTS_DIR)
