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

skip_34="powerpc:qemu_ppc64_e5500_defconfig"
skip_310="powerpc:qemu_ppc64_e5500_defconfig"
skip_312="powerpc:qemu_ppc64_e5500_defconfig"
skip_314="powerpc:qemu_ppc64_e5500_defconfig"

patch_defconfig()
{
    local defconfig=$1
    local fixup=$2

    # Enable SMP as requested

    sed -i -e '/CONFIG_SMP/d' ${defconfig}
    sed -i -e '/CONFIG_NR_CPUS/d' ${defconfig}

    if [ "${fixup}" = "nosmp" ]
    then
        echo "# CONFIG_SMP is not set" >> ${defconfig}
    elif [ "${fixup}" = "smp4" ]
    then
        echo "CONFIG_SMP=y" >> ${defconfig}
        echo "CONFIG_NR_CPUS=4" >> ${defconfig}
    elif [ "${fixup}" = "smp" ]
    then
        echo "CONFIG_SMP=y" >> ${defconfig}
    fi
}

runkernel()
{
    local defconfig=$1
    local fixup=$2
    local machine=$3
    local cpu=$4
    local kernel=$5
    local rootfs=$6
    local reboot=$7
    local dt=$8
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Restarting system" "Restarting" "Boot successful" "Rebooting")

    echo -n "Building ${ARCH}:${fixup}:${defconfig} ... "

    dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig} "" ${fixup}
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
	${dt_cmd} > ${logfile} 2>&1 &

    pid=$!

    dowait ${pid} ${logfile} ${reboot} waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel qemu_ppc64_book3s_defconfig nosmp mac99 ppc64 vmlinux \
	busybox-powerpc64.img manual
retcode=$?
runkernel qemu_ppc64_book3s_defconfig smp4 mac99 ppc64 vmlinux \
	busybox-powerpc64.img manual
retcode=$((${retcode} + $?))
runkernel qemu_ppc64_e5500_defconfig nosmp mpc8544ds e5500 arch/powerpc/boot/uImage \
	../ppc/busybox-ppc.cpio auto "dt_compatible=fsl,,P5020DS"
retcode=$((${retcode} + $?))
runkernel qemu_ppc64_e5500_defconfig smp mpc8544ds e5500 arch/powerpc/boot/uImage \
	../ppc/busybox-ppc.cpio auto "dt_compatible=fsl,,P5020DS"
retcode=$((${retcode} + $?))

exit ${retcode}
