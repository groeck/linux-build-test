#!/bin/bash

PREFIX=alpha-linux-
ARCH=alpha
rootfs=busybox-alpha.cpio
PATH_ALPHA=/opt/kernel/alpha/gcc-4.8.3/usr/bin

PATH=${PATH_ALPHA}:${PATH}

dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

runkernel()
{
    local defconfig=$1
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Boot successful" "Rebooting" "Restarting system")

    echo -n "Building ${ARCH}:${defconfig} ... "

    dosetup ${ARCH} ${PREFIX} "KALLSYMS_EXTRA_PASS=1" ${rootfs} ${defconfig}
    if [ $? -ne 0 ]
    then
	return 1
    fi

    echo -n "running ..."

    /opt/buildbot/bin/qemu-system-alpha -M clipper \
	-kernel arch/alpha/boot/vmlinux -no-reboot \
	-initrd ${rootfs} \
	-append 'rdinit=/sbin/init console=ttyS0 console=tty doreboot' \
	-m 128M -nographic -monitor null -serial stdio \
	> ${logfile} 2>&1 &

    pid=$!
    dowait ${pid} ${logfile} auto waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel qemu_alpha_defconfig
exit $?
