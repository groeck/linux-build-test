#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

QEMU=${QEMU:-${QEMU_V211_BIN}/qemu-system-m68k}
PREFIX=m68k-linux-
ARCH=m68k
rootfs=rootfs.cpio
PATH_M68K=/opt/kernel/gcc-4.9.0-nolibc/m68k-linux/bin

PATH=${PATH_M68K}:${PATH}

patch_defconfig()
{
    local defconfig=$1
    local mach=$2

    echo "Patching ${defconfig}" >/tmp/patchlog

    # Enable DEVTMPFS

    sed -i -e '/CONFIG_BLK_DEV_INITRD/d' ${defconfig}
    echo "CONFIG_BLK_DEV_INITRD=y" >> ${defconfig}
    sed -i -e '/CONFIG_DEVTMPFS/d' ${defconfig}
    echo "CONFIG_DEVTMPFS=y" >> ${defconfig}
    sed -i -e '/CONFIG_DEVTMPFS_MOUNT/d' ${defconfig}
    echo "CONFIG_DEVTMPFS_MOUNT=y" >> ${defconfig}

    # Specify initramfs file name
    sed -i -e '/CONFIG_INITRAMFS_SOURCE/d' ${defconfig}
    sed -i -e '/CONFIG_INITRAMFS_ROOT_UID/d' ${defconfig}
    sed -i -e '/CONFIG_INITRAMFS_ROOT_GID/d' ${defconfig}
    echo "CONFIG_INITRAMFS_SOURCE=\"${rootfs}\"" >> ${defconfig}
    echo "CONFIG_INITRAMFS_ROOT_UID=0" >> ${defconfig}
    echo "CONFIG_INITRAMFS_ROOT_GID=0" >> ${defconfig}
}

runkernel()
{
    local mach=$1
    local cpu=$2
    local defconfig=$3
    local pid
    local retcode
    local waitlist=("Rebooting" "Boot successful")
    local logfile=/tmp/runkernel-$$.log

    echo -n "Building ${ARCH}:${mach}:${cpu}:${defconfig} ... "

    dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig} dynamic ${mach}
    if [ $? -ne 0 ]
    then
	return 1
    fi

    echo -n "running ..."

    ${QEMU} -M ${mach} \
	-kernel vmlinux -cpu ${cpu} \
	-no-reboot -nographic -monitor none \
	-append "console=ttyS0,115200" \
	> ${logfile} 2>&1 &

    pid=$!

    dowait ${pid} ${logfile} manual waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel mcf5208evb m5208 m5208evb_defconfig

exit $?
