#!/bin/bash

# machine specific information
rootfs=core-image-minimal-qemux86.ext3
PATH_X86=/opt/poky/1.3/sysroots/x86_64-pokysdk-linux/usr/bin/x86_64-poky-linux
PREFIX=x86_64-poky-linux-
ARCH=x86
QEMUCMD=/opt/buildbot/bin/qemu-system-i386
KERNEL_IMAGE=arch/x86/boot/bzImage

PATH=${PATH_X86}:${PATH}

dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

runkernel()
{
    local defconfig=$1
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Restarting" "Boot successful" "Rebooting")

    echo -n "Building ${ARCH}:${defconfig} ... "

    dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig}
    if [ $? -ne 0 ]
    then
	return 1
    fi

    echo -n "running ..."

    ${QEMUCMD} -kernel ${KERNEL_IMAGE} -hda ${rootfs} -usb \
	-usbdevice wacom-tablet -no-reboot -m 128 \
	-cpu SandyBridge -nographic \
	--append "root=/dev/hda rw mem=128M vga=0 uvesafb.mode_option=640x480-32 oprofile.timer=1 console=ttyS0 console=tty doreboot" \
	> ${logfile} 2>&1 &

    pid=$!
    dowait ${pid} ${logfile} automatic waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel qemu_x86_pc_defconfig
retcode=$?
runkernel qemu_x86_pc_nosmp_defconfig
retcode=$((${retcode} + $?))

exit ${retcode}
