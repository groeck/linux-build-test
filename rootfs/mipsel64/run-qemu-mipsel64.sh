#!/bin/bash

# machine specific information
rootfs=busybox-mips64el.cpio
PATH_MIPS=/opt/poky/1.3/sysroots/x86_64-pokysdk-linux/usr/bin/mips32-poky-linux
PATH_X86=/opt/poky/1.4.0-1/sysroots/x86_64-pokysdk-linux/usr/bin
PREFIX=mips-poky-linux-
ARCH=mips
QEMUCMD=/opt/buildbot/bin/qemu-system-mips64el
KERNEL_IMAGE=vmlinux
QEMU_MACH=malta

PATH=${PATH_MIPS}:${PATH_X86}:${PATH}
dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

runkernel()
{
    local defconfig=$1
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Boot successful" "Rebooting")

    echo -n "Building ${ARCH}:${defconfig} ... "

    dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig}
    if [ $? -ne 0 ]
    then
	return 1
    fi

    echo -n "running ..."

    ${QEMUCMD} -kernel ${KERNEL_IMAGE} -M ${QEMU_MACH} \
	-vga cirrus -no-reboot -m 128 \
	--append "rdinit=/sbin/init mem=128M console=ttyS0 console=tty doreboot" \
	-nographic > ${logfile} 2>&1 &

    pid=$!
    dowait ${pid} ${logfile} automatic waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel qemu_mipsel_malta64_defconfig
retcode=$?
runkernel qemu_mipsel_malta64_smp_defconfig
retcode=$((${retcode} + $?))

exit ${retcode}
