#!/bin/bash

PREFIX=xtensa-linux-
ARCH=xtensa
rootfs=busybox-xtensa.cpio
PATH_XTENSA=/opt/kernel/xtensa/gcc-4.8.3-dc232b/usr/bin

PATH=${PATH_XTENSA}:${PATH}

dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

cached_defconfig=""

runkernel()
{
    local defconfig=$1
    local mach=$2
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Restarting system" "Boot successful" "Rebooting")

    echo -n "Building ${ARCH}:${mach}:${defconfig} ... "

    if [ "${cached_defconfig}" != "${defconfig}" ]
    then
        dosetup ${ARCH} ${PREFIX} "bootdir-y=boot-elf" ${rootfs} ${defconfig}
        if [ $? -ne 0 ]
        then
	    return 1
        fi
	cached_defconfig=${defconfig}
    fi

    echo -n "running ..."

    /opt/buildbot/bin/qemu-system-xtensa -cpu dc232b -M ${mach} \
	-kernel arch/xtensa/boot/Image.elf -no-reboot \
	 -append 'rdinit=/sbin/init console=ttyS0 console=tty' \
	-m 128M -nographic -monitor null -serial stdio \
	> ${logfile} 2>&1 &

    pid=$!
    dowait ${pid} ${logfile} manual waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel qemu_xtensa_defconfig lx60
retcode=$?
runkernel qemu_xtensa_defconfig lx200
retcode=$((${retcode} + $?))
runkernel qemu_xtensa_defconfig kc705
retcode=$((${retcode} + $?))
runkernel qemu_xtensa_defconfig ml605
retcode=$((${retcode} + $?))

exit ${retcode}
