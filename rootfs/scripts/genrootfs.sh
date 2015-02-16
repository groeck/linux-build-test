#!/bin/bash
#
# Must run under fakeroot

tmprootfs=/tmp/rootfs.$$
progdir=$1
rootfs=$2
destdir=$(pwd)

rm -rf ${tmprootfs}
mkdir ${tmprootfs}

cd ${tmprootfs}

cpio -i < ${progdir}/${rootfs} >/dev/null 2>&1

(cd ${progdir}/../scripts/runtime; tar cf - .) | tar xf -

find . | cpio --quiet -o -H newc > ${destdir}/${rootfs} 2>/dev/null

rm -rf ${tmprootfs}

cd ${destdir}
