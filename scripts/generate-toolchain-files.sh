#!/bin/bash
# Generate CMake toolchain files and shell environment files for all (or a specific) architecture.
#
# For each arch, produces:
#   <base_dir>/<arch>/toolchain.cmake  – self-contained CMake toolchain
#   <base_dir>/<arch>/toolchain.env    – shell env vars (source-able)
#
# Usage: generate-toolchain-files.sh <base_dir> [arch_name]

set -e

BASE_DIR="${1:-/opt}"
ARCH_FILTER="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../platforms.conf"

while IFS='|' read -r arch target sysroot platform base_image sysroot_dockerfile cmake_proc cmake_flags rest; do
    [[ "$arch" =~ ^#.*$ ]] && continue
    [ -z "$arch" ] && continue
    [ -n "$ARCH_FILTER" ] && [ "$arch" != "$ARCH_FILTER" ] && continue

    ARCH_DIR="${BASE_DIR}/${arch}"
    SYSROOT_PATH="${ARCH_DIR}/sysroot"
    TOOLCHAIN_DIR="${ARCH_DIR}/toolchain"
    CMAKE_FILE="${ARCH_DIR}/toolchain.cmake"
    ENV_FILE="${ARCH_DIR}/toolchain.env"

    mkdir -p "$ARCH_DIR"

    # ── CMake toolchain file ──────────────────────────────────────────

    cat > "$CMAKE_FILE" <<EOF
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR $cmake_proc)

set(CMAKE_SYSROOT $SYSROOT_PATH)

# Compilers
set(CMAKE_C_COMPILER ${TOOLCHAIN_DIR}/bin/${target}-gcc)
set(CMAKE_CXX_COMPILER ${TOOLCHAIN_DIR}/bin/${target}-g++)
set(CMAKE_C_COMPILER_TARGET $target)
set(CMAKE_CXX_COMPILER_TARGET $target)

# Binutils
set(CMAKE_AR ${TOOLCHAIN_DIR}/bin/${target}-ar)
set(CMAKE_RANLIB ${TOOLCHAIN_DIR}/bin/${target}-ranlib)
set(CMAKE_STRIP ${TOOLCHAIN_DIR}/bin/${target}-strip)
set(CMAKE_NM ${TOOLCHAIN_DIR}/bin/${target}-nm)
set(CMAKE_OBJDUMP ${TOOLCHAIN_DIR}/bin/${target}-objdump)
set(CMAKE_OBJCOPY ${TOOLCHAIN_DIR}/bin/${target}-objcopy)
set(CMAKE_LINKER ${TOOLCHAIN_DIR}/bin/${target}-ld)
EOF

    if [ -n "$cmake_flags" ]; then
        cat >> "$CMAKE_FILE" <<EOF

set(CMAKE_C_FLAGS_INIT "$cmake_flags")
set(CMAKE_CXX_FLAGS_INIT "$cmake_flags")
EOF
    fi

    cat >> "$CMAKE_FILE" <<'EOF'

string(APPEND CMAKE_C_FLAGS_INIT " -static-libgcc")
string(APPEND CMAKE_CXX_FLAGS_INIT " -static-libstdc++ -static-libgcc")
EOF

    if [ "$arch" = "armhf" ]; then
        cat >> "$CMAKE_FILE" <<'EOF'

string(APPEND CMAKE_C_STANDARD_LIBRARIES " -Wl,-Bstatic -latomic -Wl,-Bdynamic")
string(APPEND CMAKE_CXX_STANDARD_LIBRARIES " -Wl,-Bstatic -latomic -Wl,-Bdynamic")
EOF
    fi

    cat >> "$CMAKE_FILE" <<EOF

# Search paths
set(CMAKE_FIND_ROOT_PATH $SYSROOT_PATH)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)

string(APPEND CMAKE_EXE_LINKER_FLAGS_INIT    " -L\${CMAKE_SYSROOT}/usr/local/lib")
string(APPEND CMAKE_SHARED_LINKER_FLAGS_INIT " -L\${CMAKE_SYSROOT}/usr/local/lib")
string(APPEND CMAKE_MODULE_LINKER_FLAGS_INIT " -L\${CMAKE_SYSROOT}/usr/local/lib")

set(ENV{PKG_CONFIG_PATH}        "\${CMAKE_SYSROOT}/usr/local/lib/pkgconfig")
set(ENV{PKG_CONFIG_SYSROOT_DIR} "\${CMAKE_SYSROOT}")

set(CMAKE_C_COMPILER_WORKS 1)
set(CMAKE_CXX_COMPILER_WORKS 1)
EOF

    # ── Shell environment file ────────────────────────────────────────

    cat > "$ENV_FILE" <<EOF
# Cross-compilation environment for ${arch} (${target})
# Source this file:  source /opt/${arch}/toolchain.env

export ARCH_NAME=${arch}
export CROSS_TARGET=${target}
export SYSROOT=${SYSROOT_PATH}
export CMAKE_TOOLCHAIN_FILE=${CMAKE_FILE}

export CC=${target}-gcc
export CXX=${target}-g++
export AR=${target}-ar
export RANLIB=${target}-ranlib
export STRIP=${target}-strip
export NM=${target}-nm
export LD=${target}-ld
export OBJCOPY=${target}-objcopy
export OBJDUMP=${target}-objdump

export PATH=${TOOLCHAIN_DIR}/bin:\${PATH}

export PKG_CONFIG_PATH=${SYSROOT_PATH}/usr/local/lib/pkgconfig
export PKG_CONFIG_SYSROOT_DIR=${SYSROOT_PATH}

export CFLAGS="-static-libgcc"
export CXXFLAGS="-static-libstdc++ -static-libgcc"
EOF

    if [ "$arch" = "armhf" ]; then
        cat >> "$ENV_FILE" <<'EOF'

export LIBS="${LIBS:+$LIBS }-Wl,-Bstatic -latomic -Wl,-Bdynamic"
EOF
    fi

done < "$CONFIG_FILE"

echo "Toolchain files generated under $BASE_DIR"
