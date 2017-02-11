#!/bin/bash

config=$1
variant=$2

rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
case "${rel}" in
v3.2|v3.4)
	PATH_MIPS=/opt/kernel/gcc-4.6.3-nolibc/mips64-linux/bin
	PREFIX=mips64-linux-
	cpu=""
	;;
*)
	PATH_MIPS=/opt/kernel/gcc-4.9.0-nolibc/mips-linux/bin
	PREFIX=mips-linux-
	cpu="-cpu 5KEc"
	;;
esac

# machine specific information
rootfs=core-image-minimal-qemumips64.ext3
ARCH=mips
QEMU=${QEMU:-/opt/buildbot/qemu-install/v2.8/bin/qemu-system-mips64}
KERNEL_IMAGE=vmlinux
QEMU_MACH=malta

PATH=${PATH_MIPS}:${PATH}
dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

patch_defconfig()
{
    local defconfig=$1
    local fixup=$2

    # Enable DEVTMPFS

    sed -i -e '/CONFIG_DEVTMPFS/d' ${defconfig}
    echo "CONFIG_DEVTMPFS=y" >> ${defconfig}

    # 64 bit build

    sed -i -e '/CONFIG_CPU_MIPS/d' ${defconfig}
    sed -i -e '/CONFIG_32BIT/d' ${defconfig}
    sed -i -e '/CONFIG_64BIT/d' ${defconfig}
    echo "CONFIG_CPU_MIPS64_R1=y" >> ${defconfig}
    echo "CONFIG_64BIT=y" >> ${defconfig}

    # Build a big endian image

    sed -i -e '/CONFIG_CPU_LITTLE_ENDIAN/d' ${defconfig}
    sed -i -e '/CONFIG_CPU_BIG_ENDIAN/d' ${defconfig}
    echo "CONFIG_CPU_BIG_ENDIAN=y" >> ${defconfig}

    # Enable SMP if requested

    sed -i -e '/CONFIG_MIPS_MT_SMP/d' ${defconfig}
    sed -i -e '/CONFIG_SCHED_SMT/d' ${defconfig}
    sed -i -e '/CONFIG_NR_CPUS/d' ${defconfig}

    if [ "${fixup}" = "smp" ]
    then
        echo "CONFIG_MIPS_MT_SMP=y" >> ${defconfig}
        echo "CONFIG_SCHED_SMT=y" >> ${defconfig}
        echo "CONFIG_NR_CPUS=8" >> ${defconfig}
    fi
}

runkernel()
{
    local defconfig=$1
    local fixup=$2
    local pid
    local retcode
    local mountdir="/dev/sda"
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Boot successful" "Rebooting")
    local build="mips64:${defconfig}:${fixup}"

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

    # The actual configuration determines if the root file system
    # is /dev/sda (CONFIG_ATA) or /dev/hda (CONFIG_IDE).
    # CONFIG_ATA is enabled in kernel version 4.1 and later.
    grep "CONFIG_ATA=y" .config >/dev/null 2>&1
    if [ $? -ne 0 ]
    then
	mountdir="/dev/hda"
    fi

    echo -n "running ..."

    ${QEMU} -kernel ${KERNEL_IMAGE} -M ${QEMU_MACH} \
	${cpu} \
	-drive file=${rootfs},format=raw,if=ide \
	-vga cirrus -usb -usbdevice wacom-tablet -no-reboot -m 128 \
	--append "root=${mountdir} rw mem=128M console=ttyS0 console=tty doreboot" \
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
