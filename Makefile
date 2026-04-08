# GCC 15 Cross-Toolchain Build System
#
# Builds cross-compilers and per-architecture builder images.
#
# Layers:
#   1a. toolchain-sysroot-<arch> – minimal sysroot for GCC build (old glibc)
#   1b. builder-sysroot-<arch>   – target sysroot for builder (arbitrary base image)
#   2.  toolchain-<arch>         – builds GCC cross-compiler, exports tar.gz archive
#   3.  builder-<arch>           – host image with toolchain + sysroot + dependencies
#
# Examples:
#   make all                 # build toolchains then builders for all architectures
#   make builder-armhf       # build armhf builder (auto-builds toolchain if needed)
#   make toolchains          # build all toolchain archives only
#   make toolchain-armhf     # build one toolchain archive

ARCHES        := armhf amd64 arm64
IMAGE_PREFIX  := gcc15
ARTIFACTS_DIR := artifacts

# Suffix for published builder tags, e.g. dilshodm/ubuntu-builder-arm:12.04_12
DOCKER_RELEASE_FILE ?= DOCKER_RELEASE
DOCKER_RELEASE      ?= $(shell tr -d ' \t\n\r' < $(DOCKER_RELEASE_FILE) 2>/dev/null)
ifeq ($(DOCKER_RELEASE),)
$(error Set DOCKER_RELEASE=… on the command line, or create $(DOCKER_RELEASE_FILE) with the tag suffix)
endif

# Final docker image names (Ubuntu version matches toolchain / builder sysroot base)
BUILDER_TAG_armhf := dilshodm/ubuntu-builder-arm:12.04_$(DOCKER_RELEASE)
BUILDER_TAG_amd64 := dilshodm/ubuntu-builder-amd64:20.04_$(DOCKER_RELEASE)
BUILDER_TAG_arm64 := dilshodm/ubuntu-builder-arm64:20.04_$(DOCKER_RELEASE)

BINUTILS_VERSION ?= 2.45
GCC_VERSION      ?= 15.2.0

# Native linux/* platform for Ubuntu stages that run host binaries (toolchain + builder).
# Override if Make runs on a different arch than the Docker daemon (rare).
ifndef HOST_LINUX_PLATFORM
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

# Helper: extract a field from platforms.conf
platform = $(shell scripts/parse-platform.sh $(1) $(2))

# -------------------------------------------------------
# Phony targets
# -------------------------------------------------------
.PHONY: all toolchains builders clean
.PHONY: toolchain-sysroot-% builder-sysroot-% toolchain-% builder-%

all: toolchains builders

toolchains: $(addprefix toolchain-,$(ARCHES))
builders:   $(addprefix builder-,$(ARCHES))

# -------------------------------------------------------
# Layer 1a: Toolchain sysroot images (old glibc for GCC build)
# -------------------------------------------------------
toolchain-sysroot-%:
	docker build \
		--platform=$(call platform,$*,platform) \
		--build-arg BASE_IMAGE=$(call platform,$*,base_image) \
		-f sysroots/Dockerfile \
		-t $(IMAGE_PREFIX)-toolchain-sysroot-$* \
		sysroots/

# -------------------------------------------------------
# Layer 1b: Builder sysroot images (per-arch Dockerfile)
# -------------------------------------------------------
builder-sysroot-%:
	docker build \
		--platform=$(call platform,$*,platform) \
		-f $(call platform,$*,builder_sysroot_dockerfile) \
		-t $(IMAGE_PREFIX)-builder-sysroot-$* \
		builder-sysroots/

# -------------------------------------------------------
# Layer 2: Toolchain builds → tar.gz archives
# -------------------------------------------------------
toolchain-%: toolchain-sysroot-%
	mkdir -p $(ARTIFACTS_DIR)
	bash -c 'set -euo pipefail; \
		docker buildx build \
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
builder-%: builder-sysroot-%
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
		--build-arg SYSROOT_IMAGE=$(IMAGE_PREFIX)-builder-sysroot-$* \
		--build-arg SYSROOT_PLATFORM=$(call platform,$*,platform) \
		--build-arg HOST_PLATFORM=$(HOST_LINUX_PLATFORM) \
		--build-arg ARCH_NAME=$* \
		--build-arg SYSROOT_NAME=$(call platform,$*,sysroot) \
		--build-arg TARGET=$(call platform,$*,target) \
		-t $(BUILDER_TAG_$*) \
		-t $(IMAGE_PREFIX)-builder-$* \
		.

# -------------------------------------------------------
# Cleanup
# -------------------------------------------------------
clean:
	rm -rf $(ARTIFACTS_DIR)
