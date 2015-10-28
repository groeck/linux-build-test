#!/bin/bash

PREFIX=s390x-linux-
ARCH=s390
rootfs=busybox-s390.cpio
PATH_SH=/opt/kernel/gcc-4.6.3-nolibc/s390x-linux/bin

PATH=${PATH_SH}:${PATH}

dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

runkernel()
{
    local defconfig=$1
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Rebooting" "Boot successful" "Requesting system reboot")

    echo -n "Building ${ARCH}:${defconfig} ... "

    dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig}
    if [ $? -ne 0 ]
    then
	return 1
    fi

    echo -n "running ..."

    /opt/buildbot/bin/qemu-system-s390x -kernel vmlinux \
        -initrd ${rootfs} \
	-append "rdinit=/sbin/init doreboot" \
	-m 256 \
	-nographic -monitor null --no-reboot > ${logfile} 2>&1 &

    pid=$!
    dowait ${pid} ${logfile} manual waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel qemu_s390_defconfig
retcode=$?

exit ${retcode}
