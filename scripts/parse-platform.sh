#!/bin/bash
# Parse a single field from platforms.conf for a given architecture.
# Usage: parse-platform.sh <arch_name> <field_name>
# Fields: target, sysroot, platform, base_image, sysroot_dockerfile, cmake_proc, cmake_flags

ARCH="$1"
FIELD="$2"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/../platforms.conf"

if [ -z "$ARCH" ] || [ -z "$FIELD" ]; then
    echo "Usage: parse-platform.sh <arch_name> <field_name>" >&2
    exit 1
fi

while IFS='|' read -r arch target sysroot platform base_image sysroot_dockerfile cmake_proc cmake_flags rest; do
    [[ "$arch" =~ ^#.*$ ]] && continue
    [ -z "$arch" ] && continue

    if [ "$arch" = "$ARCH" ]; then
        case "$FIELD" in
            target)                      echo "$target" ;;
            sysroot)                     echo "$sysroot" ;;
            platform)                    echo "$platform" ;;
            base_image)                  echo "$base_image" ;;
            sysroot_dockerfile)          echo "$sysroot_dockerfile" ;;
            cmake_proc)                  echo "$cmake_proc" ;;
            cmake_flags)                 echo "$cmake_flags" ;;
            *) echo "Unknown field: $FIELD" >&2; exit 1 ;;
        esac
        exit 0
    fi
done < "$CONFIG_FILE"

echo "Architecture '$ARCH' not found" >&2
exit 1
