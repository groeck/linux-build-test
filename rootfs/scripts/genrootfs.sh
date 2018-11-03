#!/bin/bash
#
# Must run under fakeroot

tmprootfs="$(mktemp -d)"
progdir="$1"
rootfs="$2"

inprefix=""
outprefix=""
if [[ "${rootfs}" != /* ]]; then
    # If the rootfs path name is relative, assume implied copy
    # from ${progdir} to $(pwd).
    inprefix="${progdir}"
    outprefix="$(pwd)"
fi

rm -rf "${tmprootfs}"
mkdir "${tmprootfs}"
cd "${tmprootfs}"

cpio -i < "${inprefix}/${rootfs}" >/dev/null 2>&1

(cd ${progdir}/../scripts/runtime; tar cf - .) | tar xf -

find . | cpio --quiet -o -H newc > "${outprefix}/${rootfs}" 2>/dev/null

rm -rf ${tmprootfs}
