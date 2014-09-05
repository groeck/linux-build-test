#!/bin/bash

PREFIX=arm-poky-linux-gnueabi-
ARCH=arm
rootfs=core-image-minimal-qemuarm.ext3
# PATH_ARM=/opt/poky/1.3/sysroots/x86_64-pokysdk-linux/usr/bin/armv5te-poky-linux-gnueabi
PATH_ARM=/opt/poky/1.4.2/sysroots/x86_64-pokysdk-linux/usr/bin/armv7a-vfp-neon-poky-linux-gnueabi

PATH=${PATH_ARM}:${PATH}

dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

runkernel()
{
    local defconfig=$1
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Boot successful" "Rebooting" "Restarting")

    echo -n "Building ${ARCH}:${defconfig} ... "

    dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig}
    if [ $? -ne 0 ]
    then
	return 1
    fi

    echo -n "running ..."

    if [ "${defconfig}" = "qemu_arm_versatile_defconfig" ]
    then
      /opt/buildbot/bin/qemu-system-arm  -M versatilepb \
	-kernel arch/arm/boot/zImage \
	-drive file=${rootfs},if=scsi -no-reboot \
	-m 128 \
	--append "root=/dev/sda rw mem=128M console=ttyAMA0,115200 console=tty doreboot" \
	-nographic > ${logfile} 2>&1 & 
      pid=$!
    else
      /opt/buildbot/bin/qemu-system-arm -M vexpress-a9 \
	-kernel arch/arm/boot/zImage \
	-drive file=${rootfs},if=sd -no-reboot \
	-append "root=/dev/mmcblk0 rw console=ttyAMA0,115200 console=tty1 doreboot" \
	-nographic > ${logfile} 2>&1 &
      pid=$!
    fi

    pid=$!
    dowait ${pid} ${logfile} auto waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel qemu_arm_versatile_defconfig
retcode=$?
runkernel qemu_arm_vexpress_defconfig
retcode=$((${retcode} + $?))

exit ${retcode}
