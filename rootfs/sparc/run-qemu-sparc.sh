#!/bin/bash

PREFIX=sparc64-linux-
ARCH=sparc32
rootfs=hda.sqf
PATH_SPARC=/opt/kernel/gcc-4.6.3-nolibc/sparc64-linux/bin

PATH=${PATH_SPARC}:${PATH}

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

    if [ "${defconfig}" != "${cached_defconfig}" ]
    then
        dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig}
        if [ $? -ne 0 ]
        then
	    return 1
        fi
	cached_defconfig=${defconfig}
    fi

    echo -n "running ..."

    /opt/buildbot/bin/qemu-system-sparc -M ${mach} \
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

runkernel qemu_sparc_defconfig SS-5
retcode=$?
runkernel qemu_sparc_defconfig SS-20
retcode=$((${retcode} + $?))
runkernel qemu_sparc_defconfig SS-600MP
retcode=$((${retcode} + $?))
runkernel qemu_sparc_smp_defconfig SS-5
retcode=$((${retcode} + $?))
runkernel qemu_sparc_smp_defconfig SS-20
retcode=$((${retcode} + $?))
runkernel qemu_sparc_smp_defconfig SS-600MP
retcode=$((${retcode} + $?))

exit ${retcode}
