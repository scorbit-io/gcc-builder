#!/bin/bash
ARCH="${ARCH:-arm64}"
if [ -f "/opt/$ARCH/toolchain.env" ]; then
    source "/opt/$ARCH/toolchain.env"
else
    echo "Error: Unknown architecture '$ARCH' (no /opt/$ARCH/toolchain.env)" >&2
    exit 1
fi
exec "$@"
