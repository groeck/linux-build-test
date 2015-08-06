#!/bin/bash

PREFIX=sparc64-linux-
ARCH=sparc64
rootfs=simple-root-filesystem-sparc.ext3
PATH_SPARC=/opt/kernel/gcc-4.6.3-nolibc/sparc64-linux/bin

PATH=${PATH_SPARC}:${PATH}

dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

cached_defconfig=""

runkernel()
{
    local defconfig=$1
    local machine=$2
    local cpu="$3"
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Restarting system" "Boot successful" "Rebooting")

    echo -n "Building ${ARCH}:${machine}:${defconfig} ... "

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

    /opt/buildbot/bin/qemu-system-sparc64 -M ${machine} -cpu "${cpu}" \
	-m 512 \
	-drive file=${rootfs},if=virtio \
	-net nic,model=virtio \
	-kernel arch/sparc/boot/image -no-reboot \
	-append "root=/dev/vda init=/sbin/init.sh console=ttyS0 doreboot" \
	-nographic > ${logfile} 2>&1 &

    pid=$!
    dowait ${pid} ${logfile} manual waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel qemu_sparc_smp_defconfig sun4u "TI UltraSparc IIi"
retcode=$?
runkernel qemu_sparc_smp_defconfig sun4v "Fujitsu Sparc64 IV"
retcode=$((${retcode} + $?))
runkernel qemu_sparc_nosmp_defconfig sun4u "TI UltraSparc IIi"
retcode=$((${retcode} + $?))
runkernel qemu_sparc_nosmp_defconfig sun4v "Fujitsu Sparc64 IV"
retcode=$((${retcode} + $?))

exit ${retcode}
