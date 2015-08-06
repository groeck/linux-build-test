#!/bin/bash

# machine specific information
# PATH_PPC=/opt/poky/1.4.0-1/sysroots/x86_64-pokysdk-linux/usr/bin/ppc64e5500-poky-linux
PATH_PPC=/opt/poky/1.5.1/sysroots/x86_64-pokysdk-linux/usr/bin/powerpc64-poky-linux
PATH_X86=/opt/poky/1.4.0-1/sysroots/x86_64-pokysdk-linux/usr/bin
PREFIX=powerpc64-poky-linux-
ARCH=powerpc

PATH=${PATH_PPC}:${PATH_X86}:${PATH}
dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

skip_34="powerpc:qemu_ppc64_e5500_defconfig powerpc:qemu_ppc64_e5500_smp_defconfig"
skip_310="powerpc:qemu_ppc64_e5500_defconfig powerpc:qemu_ppc64_e5500_smp_defconfig"
skip_312="powerpc:qemu_ppc64_e5500_defconfig powerpc:qemu_ppc64_e5500_smp_defconfig"
skip_314="powerpc:qemu_ppc64_e5500_defconfig powerpc:qemu_ppc64_e5500_smp_defconfig"

runkernel()
{
    local defconfig=$1
    local machine=$2
    local cpu=$3
    local kernel=$4
    local rootfs=$5
    local reboot=$6
    local dt=$7
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Restarting system" "Restarting" "Boot successful" "Rebooting")

    echo -n "Building ${ARCH}:${defconfig} ... "

    dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig}
    retcode=$?
    if [ ${retcode} -ne 0 ]
    then
        if [ ${retcode} -eq 2 ]
	then
	    return 0
	fi
	return 1
    fi

    echo -n "running ..."

    dt_cmd=""
    if [ -n "${dt}" ]
    then
        dt_cmd="-machine ${dt}"
    fi

    /opt/buildbot/bin/qemu-system-ppc64 -M ${machine} -cpu ${cpu} -m 1024 \
    	-kernel ${kernel} -initrd $(basename ${rootfs}) \
	-nographic -monitor null -no-reboot \
	--append "rdinit=/sbin/init console=tty console=ttyS0 doreboot" \
	${dt_cmd} -no-reboot > ${logfile} 2>&1 &

    pid=$!

    dowait ${pid} ${logfile} ${reboot} waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel qemu_ppc64_book3s_defconfig mac99 ppc64 vmlinux \
	busybox-powerpc64.img manual
retcode=$?
runkernel qemu_ppc64_book3s_smp_defconfig mac99 ppc64 vmlinux \
	busybox-powerpc64.img manual
retcode=$((${retcode} + $?))
runkernel qemu_ppc64_e5500_defconfig mpc8544ds e5500 arch/powerpc/boot/uImage \
	../ppc/busybox-ppc.cpio auto "dt_compatible=fsl,,P5020DS"
retcode=$((${retcode} + $?))
runkernel qemu_ppc64_e5500_smp_defconfig mpc8544ds e5500 arch/powerpc/boot/uImage \
	../ppc/busybox-ppc.cpio auto "dt_compatible=fsl,,P5020DS"
retcode=$((${retcode} + $?))

exit ${retcode}
