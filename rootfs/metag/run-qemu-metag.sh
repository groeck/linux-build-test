#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

QEMU=${QEMU:-${QEMU_METAG_BIN}/qemu-system-meta}

PREFIX=metag-unknown-linux-uclibc-
ARCH=metag
rootfs=busybox-metag.cpio
PATH_METAG=/opt/kernel/metag/gcc-4.2.4/usr/bin

PATH=${PATH_METAG}:${PATH}

patch_defconfig()
{
    local defconfig=$1

    # Enable BLK_DEV_INITRD, and append the initramfs to the kernel
    sed -i -e '/CONFIG_BLK_DEV_INITRD/d' ${defconfig}
    echo "CONFIG_BLK_DEV_INITRD=y" >> ${defconfig}
    sed -i -e '/CONFIG_INITRAMFS_SOURCE/d' ${defconfig}
    echo "CONFIG_INITRAMFS_SOURCE=\"$(rootfsname ${rootfs})\"" >> ${defconfig}


    # Enable DEVTMPFS
    sed -i -e '/CONFIG_DEVTMPFS/d' ${defconfig}
    echo "CONFIG_DEVTMPFS=y" >> ${defconfig}
}

runkernel()
{
    local defconfig=$1
    local retcode
    local waitlist=("Restarting system" "Boot successful" \
    		    "Rebooting" "Restarting system")

    echo -n "Building ${ARCH}:${defconfig} ... "

    dosetup -f fixup "${rootfs}" "${defconfig}"
    retcode=$?
    if [ ${retcode} -eq 2 ]
    then
	return 0
    fi
    if [ ${retcode} -ne 0 ]
    then
	return 1
    fi

    echo -n "running ..."

    execute automatic waitlist[@] \
      ${QEMU} -display none \
	-kernel vmlinux -device da,exit_threads=1 \
	-chardev stdio,id=chan1 -chardev pty,id=chan2 \
	-append "rdinit=/sbin/init doreboot"

    return $?
}

echo "Build reference: $(git describe)"
echo

runkernel meta2_defconfig
rv=$?
runkernel tz1090_defconfig
rv=$((${rv} + $?))

exit ${rv}
