#!/bin/bash

config=$1
variant=$2

# machine specific information
rootfs=busybox-mipsel.cpio
PATH_MIPS=/opt/poky/1.3/sysroots/x86_64-pokysdk-linux/usr/bin/mips32-poky-linux
PATH_X86=/opt/poky/1.4.0-1/sysroots/x86_64-pokysdk-linux/usr/bin
PREFIX=mips-poky-linux-
ARCH=mips
QEMUCMD=/opt/buildbot/bin/qemu-system-mipsel
KERNEL_IMAGE=vmlinux
QEMU_MACH=malta

PATH=${PATH_MIPS}:${PATH_X86}:${PATH}
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
    local defconfig=$1
    local fixup=$2
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Boot successful" "Rebooting")
    local build="${ARCH}:${defconfig}:${fixup}"

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

    ${QEMUCMD} -kernel ${KERNEL_IMAGE} -M ${QEMU_MACH} \
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

runkernel malta_defconfig nosmp
retcode=$?
runkernel malta_defconfig smp
retcode=$((${retcode} + $?))

exit ${retcode}
