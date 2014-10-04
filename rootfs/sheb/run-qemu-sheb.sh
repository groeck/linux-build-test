#!/bin/bash

PREFIX=sh4-linux-
ARCH=sh
rootfs=busybox-sheb.img
PATH_SH=/opt/kernel/gcc-4.6.3-nolibc/sh4-linux/bin
# PATH_SH=/opt/kernel/sh4eb/gcc-4.8.3/usr/bin

PATH=${PATH_SH}:${PATH}

dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

runkernel()
{
    local defconfig=$1
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Power down" "Boot successful" "Poweroff")

    echo -n "Building ${ARCH}:${defconfig} ... "

    dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig}
    if [ $? -ne 0 ]
    then
	return 1
    fi

    echo -n "running ..."

    /opt/buildbot/bin/qemu-system-sh4eb -M r2d -kernel ./arch/sh/boot/zImage \
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

runkernel qemu_sheb_defconfig
retcode=$?

exit ${retcode}
