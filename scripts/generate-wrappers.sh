#!/bin/bash
# Generate wrapper scripts for all (or a specific) architecture
# Usage: generate-wrappers.sh <wrapper_dir> [arch_name]

set -e

WRAPPER_DIR="${1:-/opt/wrappers}"
ARCH_FILTER="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../platforms.conf"

mkdir -p "$WRAPPER_DIR"

# Read all platforms from config and generate wrappers
while IFS='|' read -r arch target sysroot platform base_image builder_base_image cmake_proc cmake_flags rest; do
    # Skip comments and empty lines
    [[ "$arch" =~ ^#.*$ ]] && continue
    [ -z "$arch" ] && continue
    [ -n "$ARCH_FILTER" ] && [ "$arch" != "$ARCH_FILTER" ] && continue
    
    SYSROOT_PATH="/opt/$sysroot"
    
    # Generate GCC wrapper
    cat > "${WRAPPER_DIR}/${arch}-gcc" <<EOF
#!/bin/sh
exec /opt/cross/$target/bin/$target-gcc --sysroot=$SYSROOT_PATH "\$@"
EOF
    
    # Generate G++ wrapper
    cat > "${WRAPPER_DIR}/${arch}-g++" <<EOF
#!/bin/sh
exec /opt/cross/$target/bin/$target-g++ --sysroot=$SYSROOT_PATH "\$@"
EOF
    
    chmod +x "${WRAPPER_DIR}/${arch}-gcc" "${WRAPPER_DIR}/${arch}-g++"
done < "$CONFIG_FILE"

echo "Wrapper scripts generated in $WRAPPER_DIR"

