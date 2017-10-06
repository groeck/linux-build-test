#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-sh4eb}
PREFIX=sh4-linux-
ARCH=sh
rootfs=busybox-sheb.img
PATH_SH=/opt/kernel/gcc-4.6.3-nolibc/sh4-linux/bin
# PATH_SH=/opt/kernel/sh4eb/gcc-4.8.3/usr/bin

PATH=${PATH_SH}:${PATH}

patch_defconfig()
{
    local defconfig=$1

    # Drop command line overwrite
    sed -i -e '/CONFIG_CMDLINE/d' ${defconfig}

    # Enable BLK_DEV_INITRD
    sed -i -e '/CONFIG_BLK_DEV_INITRD/d' ${defconfig}
    echo "CONFIG_BLK_DEV_INITRD=y" >> ${defconfig}

    # Enable DEVTMPFS
    sed -i -e '/CONFIG_DEVTMPFS/d' ${defconfig}
    echo "CONFIG_DEVTMPFS=y" >> ${defconfig}

    # Build a big endian image
    sed -i -e '/CONFIG_CPU_BIG_ENDIAN/d' ${defconfig}
    echo "CONFIG_CPU_BIG_ENDIAN=y" >> ${defconfig}
}

runkernel()
{
    local defconfig=$1
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Power down" "Boot successful" "Poweroff")

    echo -n "Building ${ARCH}:${defconfig} ... "

    dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig} "" fixup
    if [ $? -ne 0 ]
    then
	return 1
    fi

    echo -n "running ..."

    ${QEMU} -M r2d -kernel ./arch/sh/boot/zImage \
	-initrd ${rootfs} \
	-append "rdinit=/sbin/init console=ttySC1,115200 noiotrap doreboot" \
	-serial null -serial stdio -monitor null -nographic \
	> ${logfile} 2>&1 &

    pid=$!
    dowait ${pid} ${logfile} automatic waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel rts7751r2dplus_defconfig
retcode=$?

exit ${retcode}
