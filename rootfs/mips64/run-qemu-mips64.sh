#!/bin/bash

# machine specific information
rootfs=core-image-minimal-qemumips64.ext3
PATH_MIPS=/opt/kernel/gcc-4.6.3-nolibc/mips64-linux/bin
PREFIX=mips64-linux-
ARCH=mips
QEMUCMD=/opt/buildbot/bin/qemu-system-mips64
KERNEL_IMAGE=vmlinux
QEMU_MACH=malta

PATH=${PATH_MIPS}:${PATH}
dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

runkernel()
{
    local defconfig=$1
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Boot successful" "Rebooting")

    echo -n "Building mips64:${defconfig} ... "

    dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig}
    if [ $? -ne 0 ]
    then
	return 1
    fi

    echo -n "running ..."

    ${QEMUCMD} -kernel ${KERNEL_IMAGE} -M ${QEMU_MACH} -hda ${rootfs} \
	-vga cirrus -usb -usbdevice wacom-tablet -no-reboot -m 128 \
	--append "root=/dev/hda rw mem=128M console=ttyS0 console=tty doreboot" \
	-nographic > ${logfile} 2>&1 &

    pid=$!

    dowait ${pid} ${logfile} automatic waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel qemu_mips_malta64_defconfig
retcode=$?
runkernel qemu_mips_malta64_smp_defconfig
retcode=$((${retcode} + $?))

exit ${retcode}
