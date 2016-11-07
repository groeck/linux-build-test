#!/bin/bash

_cpu=$1
config=$2
variant=$3

rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
case "${rel}" in
v3.2|v3.4|v3.10|v3.12|v3.14|v3.16)
	PATH_MIPS=/opt/poky/1.3/sysroots/x86_64-pokysdk-linux/usr/bin/mips32-poky-linux
	;;
*)
	PATH_MIPS=/opt/poky/2.0/sysroots/x86_64-pokysdk-linux/usr/bin/mips-poky-linux
	;;
esac

# machine specific information
rootfs=busybox-mipsel.cpio
PREFIX=mips-poky-linux-
ARCH=mips
QEMUCMD=/opt/buildbot/qemu-install/v2.7/bin/qemu-system-mipsel
KERNEL_IMAGE=vmlinux
QEMU_MACH=malta

PATH=${PATH_MIPS}:${PATH}
dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

patch_defconfig()
{
    local defconfig=$1
    local fixup=$2

    # Enable DEVTMPFS and BLK_DEV_INITRD for initrd support
    # DEVTMPFS needs to be explicitly enabled for v3.14 and older kernels.
    sed -i -e '/CONFIG_DEVTMPFS/d' ${defconfig}
    echo "CONFIG_DEVTMPFS=y" >> ${defconfig}
    sed -i -e '/CONFIG_BLK_DEV_INITRD/d' ${defconfig}
    echo "CONFIG_BLK_DEV_INITRD=y" >> ${defconfig}

    sed -i -e '/CONFIG_MIPS_MT_SMP/d' ${defconfig}
    if [ "${fixup}" = "smp" ]
    then
        echo "CONFIG_MIPS_MT_SMP=y" >> ${defconfig}
    fi
}

runkernel()
{
    local cpu=$1
    local defconfig=$2
    local fixup=$3
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Boot successful" "Rebooting")
    local build="mipsel:${cpu}:${defconfig}:${fixup}"

    if [ -n "${_cpu}" -a "${_cpu}" != "${cpu}" ]
    then
	echo "Skipping ${build} ... "
	return 0
    fi

    if [ -n "${config}" -a "${config}" != "${defconfig}" ]
    then
	echo "Skipping ${build} ... "
	return 0
    fi

    if [ -n "${variant}" -a "${variant}" != "${fixup}" ]
    then
	echo "Skipping ${build} ... "
	return 0
    fi

    echo -n "Building ${build} ... "

    dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig} "" ${fixup}
    if [ $? -ne 0 ]
    then
	return 1
    fi

    echo -n "running ..."

    ${QEMUCMD} -kernel ${KERNEL_IMAGE} -M ${QEMU_MACH} -cpu ${cpu} \
	-initrd ${rootfs} \
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

runkernel 24Kf malta_defconfig nosmp
retcode=$?
runkernel 24Kf malta_defconfig smp
retcode=$((${retcode} + $?))
# No root file system available
# runkernel mips32r6-generic malta_qemu_32r6_defconfig smp
# retcode=$((${retcode} + $?))

exit ${retcode}
