#!/bin/bash

QEMU=/opt/buildbot/qemu-install/v2.8/bin/qemu-system-sparc
PREFIX=sparc64-linux-
ARCH=sparc32
rootfs=hda.sqf
PATH_SPARC=/opt/kernel/gcc-4.6.3-nolibc/sparc64-linux/bin

PATH=${PATH_SPARC}:${PATH}

dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

cached_defconfig=""

patch_defconfig()
{
    local defconfig=$1
    local smp=$2

    # Enable SQUASHFS and DEVTMPFS, and set SMP as needed.

    sed -i -e '/CONFIG_SQUASHFS/d' ${defconfig}
    sed -i -e '/CONFIG_SMP/d' ${defconfig}
    sed -i -e '/CONFIG_DEVTMPFS/d' ${defconfig}

    echo "CONFIG_SQUASHFS=y" >> ${defconfig}
    echo "CONFIG_DEVTMPFS=y" >> ${defconfig}

    if [ "${smp}" = "nosmp" ]
    then
	echo "# CONFIG_SMP is not set" >> ${defconfig}
    else
	echo "CONFIG_SMP=y" >> ${defconfig}
    fi
}

runkernel()
{
    local defconfig=$1
    local mach=$2
    local smp=$3
    local noapcflag=$4
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Restarting system" "Boot successful" "Rebooting")
    local apc=""

    echo -n "Building ${ARCH}:${mach}:${smp}:${defconfig} ... "

    if [ "${defconfig}_${smp}" != "${cached_defconfig}" ]
    then
        dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig} "" ${smp}
        if [ $? -ne 0 ]
        then
	    return 1
        fi
	cached_defconfig="${defconfig}_${smp}"
    fi

    if [ -n "${noapcflag}" ]
    then
	apc="apc=noidle"
    fi

    echo -n "running ..."

    ${QEMU} -M ${mach} \
	-kernel arch/sparc/boot/image -no-reboot \
	-drive file=hda.sqf,if=scsi,format=raw \
	-append "root=/dev/sda rw init=/sbin/init.sh panic=1 console=ttyS0 ${apc} doreboot" \
	-nographic > ${logfile} 2>&1 &

    pid=$!
    dowait ${pid} ${logfile} automatic waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel sparc32_defconfig SPARCClassic nosmp
retcode=$?
runkernel sparc32_defconfig SPARCbook nosmp
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig SS-4 nosmp
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig SS-5 nosmp
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig SS-10 nosmp
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig SS-20 nosmp
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig SS-600MP nosmp
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig LX nosmp noapc
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig Voyager nosmp noapc
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig SPARCClassic smp
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig SPARCbook smp
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig SS-4 smp
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig SS-5 smp
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig SS-10 smp
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig SS-20 smp
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig SS-600MP smp
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig LX smp noapc
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig Voyager smp noapc
retcode=$((${retcode} + $?))

exit ${retcode}
