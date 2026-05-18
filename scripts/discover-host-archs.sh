#!/bin/bash
# Discover host arch suffixes (amd64, arm64) for a release and image name.
# Usage: discover-host-archs.sh <release> <image-basename>
#   e.g. discover-host-archs.sh 4 gcc-builder
# Prints one arch per line (sorted). Exits 1 if none found.

set -euo pipefail

RELEASE="${1:?release required}"
IMAGE_BASE="${2:?image basename required (e.g. gcc-builder)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

if [ -f .env ]; then
    # shellcheck disable=SC1091
    set -a
    # shellcheck source=/dev/null
    . ./.env
    set +a
fi

PREFIX=""
if [ -n "${DOCKER_USER:-}" ]; then
    PREFIX="${DOCKER_USER}/"
fi

archs=()

add_arch() {
    local a="$1"
    local x
    [ -n "$a" ] || return
    if [ ${#archs[@]} -gt 0 ]; then
        for x in "${archs[@]}"; do
            if [ "$x" = "$a" ]; then
                return
            fi
        done
    fi
    archs+=("$a")
}

tag_prefix="${PREFIX}${IMAGE_BASE}:${RELEASE}-"

# Local docker images already built or pulled.
while IFS= read -r ref; do
    case "$ref" in
        "${tag_prefix}"*)
            add_arch "${ref#${tag_prefix}}"
            ;;
    esac
done < <(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null || true)

# Artifact directories: artifacts/linux-amd64/ -> amd64
for dir in "$REPO_ROOT"/artifacts/linux-*/; do
    [ -d "$dir" ] || continue
    slug=$(basename "$dir")
    arch="${slug#linux-}"
    case "$IMAGE_BASE" in
        gcc-builder)
            if [ -f "${dir}toolchain-armhf.tar.gz" ]; then
                add_arch "$arch"
            fi
            ;;
        gcc-builder-musl)
            if [ -f "${dir}musl-toolchain-armhf.tar.gz" ]; then
                add_arch "$arch"
            fi
            ;;
        python-builder)
            add_arch "$arch"
            ;;
        *)
            echo "Unknown image basename: $IMAGE_BASE" >&2
            exit 1
            ;;
    esac
done

if [ ${#archs[@]} -eq 0 ]; then
    echo "No host archs found for ${PREFIX}${IMAGE_BASE}:${RELEASE}-*" >&2
    echo "Build and push per-arch tags (make all && make push) or check DOCKER_RELEASE." >&2
    exit 1
fi

# shellcheck disable=SC2145
printf '%s\n' "${archs[@]}" | sort -u
