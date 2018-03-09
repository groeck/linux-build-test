#!/bin/bash

_cpu=$1
config=$2
variant=$3

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
case "${rel}" in
v3.2)
	PATH_MIPS=/opt/poky/1.3/sysroots/x86_64-pokysdk-linux/usr/bin/mips32-poky-linux
	QEMU=${QEMU:-${QEMU_V29_BIN}/qemu-system-mipsel}
	PREFIX=mips-poky-linux-
	;;
*)
	PATH_MIPS=/opt/kernel/gcc-7.3.0-nolibc/mips-linux/bin
	QEMU=${QEMU:-${QEMU_BIN}/qemu-system-mipsel}
	PREFIX=mips-linux-
	;;
esac

# machine specific information
ARCH=mips
KERNEL_IMAGE=vmlinux
QEMU_MACH=malta

PATH=${PATH_MIPS}:${PATH}

patch_defconfig()
{
    local defconfig=$1
    local fixup=$2

    # Enable DEVTMPFS and BLK_DEV_INITRD for initrd support
    # DEVTMPFS needs to be explicitly enabled for v3.14 and older kernels.
    sed -i -e '/CONFIG_DEVTMPFS/d' ${defconfig}
    echo "CONFIG_DEVTMPFS=y" >> ${defconfig}
    echo "CONFIG_DEVTMPFS_MOUNT=y" >> ${defconfig}
    sed -i -e '/CONFIG_BLK_DEV_INITRD/d' ${defconfig}
    echo "CONFIG_BLK_DEV_INITRD=y" >> ${defconfig}

    sed -i -e '/CONFIG_MIPS_MT_SMP/d' ${defconfig}
    if [ "${fixup}" = "smp" ]
    then
        echo "CONFIG_MIPS_MT_SMP=y" >> ${defconfig}
    fi
}

cached_config=""

runkernel()
{
    local cpu=$1
    local defconfig=$2
    local rootfs=$3
    local fixup=$4
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Boot successful" "Rebooting")
    local build="mipsel:${cpu}:${defconfig}:${fixup}"
    local buildconfig="${defconfig}:${fixup}"

    if [[ "${rootfs}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":rootfs"
    fi

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

    if [ "${cached_config}" != "${buildconfig}" ]; then
	dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig} "" ${fixup}
	retcode=$?
	if [ ${retcode} -ne 0 ]; then
	    if [ ${retcode} -eq 2 ]; then
		return 0
	    fi
	    return 1
	fi
	cached_config="${buildconfig}"
    else
	setup_rootfs ${rootfs} ""
    fi

    echo -n "running ..."

    if [[ "${rootfs}" == *cpio ]]; then
	initcli="rdinit=/sbin/init"
	diskcmd="-initrd ${rootfs}"
    else
	local hddev="hda"
	grep -q CONFIG_ATA=y .config >/dev/null 2>&1
	[ $? -eq 0 ] && hddev="sda"
	initcli="root=/dev/${hddev} rw"
	diskcmd="-drive file=${rootfs},if=ide,format=raw"
    fi

    ${QEMU} -kernel ${KERNEL_IMAGE} -M ${QEMU_MACH} -cpu ${cpu} \
	${diskcmd} \
	-vga cirrus -no-reboot -m 128 \
	--append "${initcli} mem=128M console=ttyS0 doreboot" \
	-nographic > ${logfile} 2>&1 &

    pid=$!
    dowait ${pid} ${logfile} automatic waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel 24Kf malta_defconfig busybox-mipsel.cpio nosmp
retcode=$?
runkernel 24Kf malta_defconfig busybox-mipsel.cpio smp
retcode=$((${retcode} + $?))
runkernel 24Kf malta_defconfig rootfs-mipselr1.ext2 smp
retcode=$((${retcode} + $?))
runkernel mips32r6-generic malta_qemu_32r6_defconfig rootfs-mipselr6.ext2 smp
retcode=$((${retcode} + $?))

exit ${retcode}
