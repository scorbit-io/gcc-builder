#!/bin/bash
# Generate CMake toolchain files for all (or a specific) architecture.
# Produces a self-contained toolchain file that includes compiler, binutils,
# sysroot, dependency paths, and arch-specific linker flags.
#
# Usage: generate-cmake-toolchains.sh <toolchain_dir> [arch_name]

set -e

TOOLCHAIN_DIR="${1:-/opt/toolchain}"
ARCH_FILTER="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../platforms.conf"

mkdir -p "$TOOLCHAIN_DIR"

while IFS='|' read -r arch target sysroot platform base_image builder_sysroot_dockerfile cmake_proc cmake_flags rest; do
    [[ "$arch" =~ ^#.*$ ]] && continue
    [ -z "$arch" ] && continue
    [ -n "$ARCH_FILTER" ] && [ "$arch" != "$ARCH_FILTER" ] && continue

    SYSROOT_PATH="/opt/$sysroot"
    CROSS_PREFIX="/opt/cross/$target"
    CMAKE_FILE="${TOOLCHAIN_DIR}/${arch}.cmake"

    cat > "$CMAKE_FILE" <<EOF
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR $cmake_proc)

set(CMAKE_SYSROOT $SYSROOT_PATH)

# Compilers
set(CMAKE_C_COMPILER ${CROSS_PREFIX}/bin/${target}-gcc)
set(CMAKE_CXX_COMPILER ${CROSS_PREFIX}/bin/${target}-g++)
set(CMAKE_C_COMPILER_TARGET $target)
set(CMAKE_CXX_COMPILER_TARGET $target)

# Binutils
set(CMAKE_AR ${CROSS_PREFIX}/bin/${target}-ar)
set(CMAKE_RANLIB ${CROSS_PREFIX}/bin/${target}-ranlib)
set(CMAKE_STRIP ${CROSS_PREFIX}/bin/${target}-strip)
set(CMAKE_NM ${CROSS_PREFIX}/bin/${target}-nm)
set(CMAKE_OBJDUMP ${CROSS_PREFIX}/bin/${target}-objdump)
set(CMAKE_OBJCOPY ${CROSS_PREFIX}/bin/${target}-objcopy)
set(CMAKE_LINKER ${CROSS_PREFIX}/bin/${target}-ld)
EOF

    if [ -n "$cmake_flags" ]; then
        cat >> "$CMAKE_FILE" <<EOF

set(CMAKE_C_FLAGS_INIT "$cmake_flags")
set(CMAKE_CXX_FLAGS_INIT "$cmake_flags")
EOF
    fi

    # Link libgcc (and for C++, libstdc++) into the binary; glibc stays dynamic.
    cat >> "$CMAKE_FILE" <<'EOF'

string(APPEND CMAKE_C_FLAGS_INIT " -static-libgcc")
string(APPEND CMAKE_CXX_FLAGS_INIT " -static-libstdc++ -static-libgcc")
EOF

    # armhf: static libatomic, after static archives (e.g. libcrypto.a) on the link line.
    # Putting -latomic in *_LINKER_FLAGS_INIT runs it too early; unresolved __atomic_* from .a then fail.
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

# /usr/local is not in the linker's default sysroot search path; add it so bare
# -lpsl / -lssl / etc. flags resolve to <sysroot>/usr/local/lib.
string(APPEND CMAKE_EXE_LINKER_FLAGS_INIT    " -L\${CMAKE_SYSROOT}/usr/local/lib")
string(APPEND CMAKE_SHARED_LINKER_FLAGS_INIT " -L\${CMAKE_SYSROOT}/usr/local/lib")
string(APPEND CMAKE_MODULE_LINKER_FLAGS_INIT " -L\${CMAKE_SYSROOT}/usr/local/lib")

set(ENV{PKG_CONFIG_PATH}        "\${CMAKE_SYSROOT}/usr/local/lib/pkgconfig")
set(ENV{PKG_CONFIG_SYSROOT_DIR} "\${CMAKE_SYSROOT}")

# Skip compiler tests (cross-compiled binaries cannot run on host)
set(CMAKE_C_COMPILER_WORKS 1)
set(CMAKE_CXX_COMPILER_WORKS 1)
EOF

done < "$CONFIG_FILE"

echo "CMake toolchain files generated in $TOOLCHAIN_DIR"
