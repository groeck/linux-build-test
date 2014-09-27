#!/bin/bash

# machine specific information
rootfs=busybox-powerpc64.img
# PATH_PPC=/opt/poky/1.4.0-1/sysroots/x86_64-pokysdk-linux/usr/bin/ppc64e5500-poky-linux
PATH_PPC=/opt/poky/1.5.1/sysroots/x86_64-pokysdk-linux/usr/bin/powerpc64-poky-linux
PATH_X86=/opt/poky/1.4.0-1/sysroots/x86_64-pokysdk-linux/usr/bin
PREFIX=powerpc64-poky-linux-
ARCH=powerpc

PATH=${PATH_PPC}:${PATH_X86}:${PATH}
dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

runkernel()
{
    local defconfig=$1
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("System Halted", "Restarting" "Boot successful" "Rebooting")

    echo -n "Building ${ARCH}:${defconfig} ... "

    dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig}
    if [ $? -ne 0 ]
    then
	return 1
    fi

    echo -n "running ..."

    /opt/buildbot/bin/qemu-system-ppc64 -M mac99 -cpu ppc64 -m 1024 \
    	-kernel vmlinux -initrd busybox-powerpc64.img \
	-nographic -monitor null -no-reboot \
	--append "rdinit=/sbin/init console=tty console=ttyS0 doreboot" \
	> ${logfile} 2>&1 &

    pid=$!

    dowait ${pid} ${logfile} manual waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel qemu_ppc64_book3s_defconfig
retcode=$?
runkernel qemu_ppc64_book3s_smp_defconfig
retcode=$((${retcode} + $?))

exit ${retcode}
