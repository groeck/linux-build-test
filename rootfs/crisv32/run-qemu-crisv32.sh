#!/bin/bash

QEMU=/opt/buildbot/qemu-install/v2.7/bin/qemu-system-cris
PREFIX=crisv32-linux-
ARCH=cris
rootfs=busybox-cris.cpio
PATH_CRIS=/opt/kernel/crisv32/gcc-4.9.2/usr/bin

PATH=${PATH_CRIS}:${PATH}

dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

runkernel()
{
    local defconfig=$1
    local pid
    local retcode
    local waitlist=("Requesting system reboot" "Boot successful" "reboot: Restarting system")
    local logfile=/tmp/runkernel-$$.log

    echo -n "Building ${ARCH}:${defconfig} ... "

    dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig} dynamic
    if [ $? -ne 0 ]
    then
	return 1
    fi

    echo -n "running ..."

    ${QEMU} -serial stdio -kernel vmlinux \
    	-no-reboot -monitor none -nographic \
	-append "console=ttyS0,115200,N,8 rdinit=/sbin/init" \
	> ${logfile} 2>&1 &

    pid=$!

    dowait ${pid} ${logfile} automatic waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel qemu_crisv32_defconfig

exit $?
