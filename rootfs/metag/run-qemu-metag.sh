#!/bin/bash

PREFIX=metag-unknown-linux-uclibc-
ARCH=metag
rootfs=busybox-metag.cpio
PATH_METAG=/opt/kernel/metag/gcc-4.2.4/usr/bin

PATH=${PATH_METAG}:${PATH}

dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

runkernel()
{
    local defconfig=$1
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Restarting system" "Boot successful" \
    		    "Rebooting" "Restarting system")

    echo -n "Building ${ARCH}:${defconfig} ... "

    dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig}
    if [ $? -ne 0 ]
    then
	return 1
    fi

    echo -n "running ..."

    /opt/buildbot/bin/qemu-system-meta -display none \
	-kernel vmlinux -device da,exit_threads=1 \
	-chardev stdio,id=chan1 -chardev pty,id=chan2 \
	-append "rdinit=/sbin/init doreboot" > ${logfile} 2>&1 &

    pid=$!
    dowait ${pid} ${logfile} automatic waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel qemu_metag_defconfig
exit $?
