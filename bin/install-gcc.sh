#!/bin/bash

TOOLCHAIN_DIR="/opt/toolchains"

if [ -z "$1" ]; then
    echo "Need file parameter"
    exit 1
fi

tfile="$(echo $1 | sed -e 's/x86_64-//' | sed -e 's/.tar.*//')"
if [[ "$1" == "${tfile}" ]] || [[ -z "${tfile}" ]]; then
    echo "$1: Bad tool archive name"
    exit 1
fi

if [ -f "/tmp/$1" ]; then
    f="/tmp/$1"
elif [ -f "$1" ]; then
    f="$1"
else
    echo "$1 does not exist or is not a file"
    exit 1
fi

if [[ "$(dirname $f)" != "${TOOLCHAIN_DIR}" ]]; then
    mv "$f" "${TOOLCHAIN_DIR}"
fi

basedir="/opt/kernel"
tdir="${basedir}/${tfile}"

if [[ "$1" != "${tfile}" ]] && [[ -n "${tfile}" ]] && [[ -d "${tdir}" ]]; then
	echo "Toolchain directory ${tdir} exists and will be removed prior to re-installation."
	rm -rf "${tdir}"
fi

tar xf "${TOOLCHAIN_DIR}/$(basename $f)" -C "${basedir}"
