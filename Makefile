# GCC 15 Cross-Toolchain Build System
#
# Builds cross-compilers and per-architecture builder images.
#
# Layers:
#   1. sysroot-<arch>   – minimal target-platform filesystem (headers + libc)
#   2. toolchain-<arch> – builds GCC cross-compiler, exports tar.gz archive
#   3. builder-<arch>   – host image with toolchain installed + sysroot copied
#
# Examples:
#   make all                 # build everything for all architectures
#   make builder-armhf       # build only the armhf builder (and its deps)
#   make toolchains          # build all toolchain archives
#   make -j3 sysroots        # build all sysroots in parallel

ARCHES        := armhf amd64 arm64
IMAGE_PREFIX  := gcc15
ARTIFACTS_DIR := artifacts

BINUTILS_VERSION ?= 2.45
GCC_VERSION      ?= 15.2.0

# Helper: extract a field from platforms.conf
platform = $(shell scripts/parse-platform.sh $(1) $(2))

# -------------------------------------------------------
# Phony targets
# -------------------------------------------------------
.PHONY: all sysroots toolchains builders clean
.PHONY: sysroot-% toolchain-% builder-%

all: builders

sysroots:   $(addprefix sysroot-,$(ARCHES))
toolchains: $(addprefix toolchain-,$(ARCHES))
builders:   $(addprefix builder-,$(ARCHES))

# -------------------------------------------------------
# Layer 1: Sysroot images
# -------------------------------------------------------
sysroot-%:
	docker build \
		--platform=$(call platform,$*,platform) \
		-f sysroots/$*.Dockerfile \
		-t $(IMAGE_PREFIX)-sysroot-$* \
		sysroots/

# -------------------------------------------------------
# Layer 2: Toolchain builds → tar.gz archives
# -------------------------------------------------------
toolchain-%: sysroot-%
	mkdir -p $(ARTIFACTS_DIR)
	docker buildx build \
		-f toolchain/Dockerfile \
		--build-arg SYSROOT_IMAGE=$(IMAGE_PREFIX)-sysroot-$* \
		--build-arg ARCH_NAME=$* \
		--build-arg SYSROOT_NAME=$(call platform,$*,sysroot) \
		--build-arg BINUTILS_VERSION=$(BINUTILS_VERSION) \
		--build-arg GCC_VERSION=$(GCC_VERSION) \
		--target export \
		--output type=tar,dest=- . | gzip > $(ARTIFACTS_DIR)/toolchain-$*.tar.gz

# -------------------------------------------------------
# Layer 3: Per-architecture builder images
# -------------------------------------------------------
builder-%: toolchain-%
	docker build \
		-f builder/Dockerfile \
		--build-arg SYSROOT_IMAGE=$(IMAGE_PREFIX)-sysroot-$* \
		--build-arg ARCH_NAME=$* \
		--build-arg SYSROOT_NAME=$(call platform,$*,sysroot) \
		--build-arg TARGET=$(call platform,$*,target) \
		-t $(IMAGE_PREFIX)-builder-$* \
		.

# -------------------------------------------------------
# Cleanup
# -------------------------------------------------------
clean:
	rm -rf $(ARTIFACTS_DIR)
