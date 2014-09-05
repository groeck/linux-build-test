#!/bin/bash

PREFIX=sparc64-linux-
ARCH=sparc32
rootfs=hda.sqf
PATH_SPARC=/opt/kernel/gcc-4.6.3-nolibc/sparc64-linux/bin

PATH=${PATH_SPARC}:${PATH}

dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

runkernel()
{
    local defconfig=$1
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Restarting system" "Boot successful" "Rebooting")

    echo -n "Building ${ARCH}:${defconfig} ... "

    dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig}
    if [ $? -ne 0 ]
    then
	return 1
    fi

    echo -n "running ..."

    /opt/buildbot/bin/qemu-system-sparc -cpu "Fujitsu MB86907" \
	-kernel arch/sparc/boot/image -hda hda.sqf -no-reboot \
	-append "root=/dev/sda rw init=/sbin/init.sh panic=1 console=ttyS0 doreboot" \
	-nographic > ${logfile} 2>&1 &

    pid=$!
    dowait ${pid} ${logfile} automatic waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel qemu_sparc_defconfig
retcode=$?
runkernel qemu_sparc_smp_defconfig
retcode=$((${retcode} + $?))

exit ${retcode}
