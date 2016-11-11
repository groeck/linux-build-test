#!/bin/bash

QEMU=/opt/buildbot/qemu-install/v2.7/bin/qemu-system-microblazeel
PREFIX=microblazeel-linux-
ARCH=microblaze
rootfs=busybox-microblazeel.cpio
PATH_MICROBLAZE=/opt/kernel/microblazeel/gcc-4.9.1/usr/bin

PATH=${PATH_MICROBLAZE}:${PATH}

dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

runkernel()
{
    local defconfig=$1
    local pid
    local retcode
    local waitlist=("Machine restart" "Boot successful" "Rebooting")
    local logfile=/tmp/runkernel-$$.log

    echo -n "Building ${ARCH}:${defconfig} ... "

    dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig} dynamic
    if [ $? -ne 0 ]
    then
	return 1
    fi

    echo -n "running ..."

    ${QEMU} -M petalogix-s3adsp1800 \
	-kernel arch/microblaze/boot/linux.bin -no-reboot -nographic \
	> ${logfile} 2>&1 &

    pid=$!

    dowait ${pid} ${logfile} manual waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel qemu_microblazeel_defconfig

exit $?
