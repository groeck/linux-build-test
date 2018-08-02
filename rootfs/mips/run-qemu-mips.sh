#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

config=$1
variant=$2

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-mips}

rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
PATH_MIPS=/opt/kernel/mips/gcc-5.4.0/usr/bin
PREFIX=mips-linux-

# machine specific information
rootfs=busybox-mips.ext3
ARCH=mips
KERNEL_IMAGE=vmlinux
QEMU_MACH=malta

PATH=${PATH_MIPS}:${PATH}

patch_defconfig()
{
    local defconfig=$1
    local fixup=$2

    # Enable DEVTMPFS
    sed -i -e '/CONFIG_DEVTMPFS/d' ${defconfig}
    echo "CONFIG_DEVTMPFS=y" >> ${defconfig}
    # Enable BLK_DEV_INITRD for initrd support
    # sed -i -e '/CONFIG_BLK_DEV_INITRD/d' ${defconfig}
    # echo "CONFIG_BLK_DEV_INITRD=y" >> ${defconfig}

    # Build a big endian image
    sed -i -e '/CONFIG_CPU_LITTLE_ENDIAN/d' ${defconfig}
    sed -i -e '/CONFIG_CPU_BIG_ENDIAN/d' ${defconfig}
    echo "CONFIG_CPU_BIG_ENDIAN=y" >> ${defconfig}

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
    local mountdir="/dev/sda"
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

    dosetup -f "${fixup}" "${rootfs}" "${defconfig}"
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

    [[ ${dodebug} -ne 0 ]] && set -x

    ${QEMU} -kernel ${KERNEL_IMAGE} -M ${QEMU_MACH} \
	-drive file=${rootfs},format=raw,if=ide \
	-vga cirrus -usb -device usb-wacom-tablet -no-reboot -m 128 \
	--append "root=${mountdir} rw mem=128M console=ttyS0 console=tty ${extracli} doreboot" \
	-nographic -monitor none > ${logfile} 2>&1 &
    pid=$!

    [[ ${dodebug} -ne 0 ]] && set +x

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
