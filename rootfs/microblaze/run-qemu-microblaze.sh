#!/bin/bash

PREFIX=microblaze-linux-
ARCH=microblaze
rootfs=rootfs.cpio
PATH_MICROBLAZE=/opt/kernel/gcc-4.8.0-nolibc/microblaze-linux/bin

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

    /opt/buildbot/bin/qemu-system-microblaze -M petalogix-s3adsp1800 \
	-kernel arch/microblaze/boot/linux.bin -no-reboot \
	-append "console=ttyUL0,115200" -nographic \
	> ${logfile} 2>&1 &

    pid=$!

    dowait ${pid} ${logfile} manual waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel qemu_microblaze_defconfig

exit $?
