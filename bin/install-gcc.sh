#!/bin/bash

TOOLCHAIN_DIR="/opt/toolchains"

if [ -z "$1" ]; then
    echo "Need parameter"
    exit 1
fi

if [ -f /tmp/$1 ]; then
    f=/tmp/$1
elif [ -f $1 ]; then
    f=$1
else
    echo "$1 does not exist or is not a file"
    exit 1
fi

if [[ "$(dirname $f)" != "${TOOLCHAIN_DIR}" ]]; then
    sudo mv $f "${TOOLCHAIN_DIR}"
fi
sudo tar xf "${TOOLCHAIN_DIR}/$(basename $f)" -C /opt/kernel
