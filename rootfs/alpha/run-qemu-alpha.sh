#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-alpha}

PREFIX=alpha-linux-
ARCH=alpha
rootfs=busybox-alpha.cpio

rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
case "${rel}" in
v3.2|v3.4|v3.8)
	PATH_ALPHA=/opt/kernel/alpha/gcc-4.8.3/usr/bin
	;;
*)
	PATH_ALPHA=/opt/kernel/alpha/gcc-5.1.0/usr/bin
	;;
esac

PATH=${PATH_ALPHA}:${PATH}

patch_defconfig()
{
    local defconfig=$1

    # Enable BLK_DEV_INITRD
    sed -i -e '/CONFIG_BLK_DEV_INITRD/d' ${defconfig}
    echo "CONFIG_BLK_DEV_INITRD=y" >> ${defconfig}

    # Enable DEVTMPFS
    sed -i -e '/CONFIG_DEVTMPFS/d' ${defconfig}
    echo "CONFIG_DEVTMPFS=y" >> ${defconfig}
}

runkernel()
{
    local defconfig=$1
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Boot successful" "Rebooting" "Restarting system")

    echo -n "Building ${ARCH}:${defconfig} ... "

    dosetup ${ARCH} ${PREFIX} "KALLSYMS_EXTRA_PASS=1" ${rootfs} ${defconfig} "" fixup
    if [ $? -ne 0 ]
    then
	return 1
    fi

    echo -n "running ..."

    ${QEMU} -M clipper \
	-kernel arch/alpha/boot/vmlinux -no-reboot \
	-initrd ${rootfs} \
	-append 'rdinit=/sbin/init console=ttyS0 console=tty doreboot' \
	-m 128M -nographic -monitor null -serial stdio \
	> ${logfile} 2>&1 &

    pid=$!
    dowait ${pid} ${logfile} auto waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel defconfig
exit $?
