#!/bin/bash

PREFIX=or1k-linux-uclibc-
ARCH=openrisc
rootfs=busybox-openrisc.cpio
PATH_OR32=/opt/kernel/or1k/gcc-4.9.0/bin

PATH=${PATH_OR32}:${PATH}

dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

patch_defconfig()
{
    local defconfig=$1

    # Specify initramfs file name
    sed -i -e '/CONFIG_INITRAMFS_SOURCE/d' ${defconfig}
    echo "CONFIG_INITRAMFS_SOURCE=\"${rootfs}\"" >> ${defconfig}

    # We need to support initramfs gzip compression
    sed -i -e '/CONFIG_RD_GZIP/d' ${defconfig}
    echo "CONFIG_RD_GZIP=y" >> ${defconfig}
}

runkernel()
{
    local defconfig=$1
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("MACHINE RESTART" "Boot successful" "Rebooting")

    echo -n "Building ${ARCH}:${defconfig} ... "

    # Kernel assumes elf32-or32, but toolchain produces elf32-or1k.
    # Kludgy fix until we find a better solution.
    sed -i -e 's/elf32-or32/elf32-or1k/g' arch/openrisc/kernel/vmlinux.lds.S
    dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig} "" fixup
    retcode=$?
    sed -i -e 's/elf32-or1k/elf32-or32/g' arch/openrisc/kernel/vmlinux.lds.S
    if [ ${retcode} -ne 0 ]
    then
	return ${retcode}
    fi

    echo -n "running ..."

    /opt/buildbot/bin/qemu-system-or32 -cpu or1200 -M or32-sim \
    	-kernel vmlinux -nographic -serial stdio -monitor none \
	> ${logfile} 2>&1 &

    pid=$!
    dowait ${pid} ${logfile} manual waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel or1ksim_defconfig
retcode=$?

exit ${retcode}
