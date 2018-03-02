#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-sh4eb}
PREFIX=sh4-linux-
ARCH=sh
PATH_SH=/opt/kernel/gcc-4.6.3-nolibc/sh4-linux/bin
# PATH_SH=/opt/kernel/sh4eb/gcc-4.8.3/usr/bin

PATH=${PATH_SH}:${PATH}

patch_defconfig()
{
    local defconfig=$1

    # Drop command line overwrite
    sed -i -e '/CONFIG_CMDLINE/d' ${defconfig}

    # Enable BLK_DEV_INITRD
    sed -i -e '/CONFIG_BLK_DEV_INITRD/d' ${defconfig}
    echo "CONFIG_BLK_DEV_INITRD=y" >> ${defconfig}

    # Enable DEVTMPFS
    sed -i -e '/CONFIG_DEVTMPFS/d' ${defconfig}
    echo "CONFIG_DEVTMPFS=y" >> ${defconfig}
    echo "CONFIG_DEVTMPFS_MOUNT=y" >> ${defconfig}

    # Build a big endian image
    sed -i -e '/CONFIG_CPU_BIG_ENDIAN/d' ${defconfig}
    echo "CONFIG_CPU_BIG_ENDIAN=y" >> ${defconfig}
}

cached_config=""

runkernel()
{
    local defconfig=$1
    local rootfs=$2
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Restarting system" "Boot successful" "Requesting system reboot")
    local build="${ARCH}:${defconfig}"

    if [[ "${rootfs}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":rootfs"
    fi

    echo -n "Building ${build} ... "

    if [ "${cached_config}" != "${defconfig}" ]; then
	dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig} "" fixup
	if [ $? -ne 0 ]; then
	    return 1
	fi
	cached_config="${defconfig}"
    else
	setup_rootfs ${rootfs} ""
    fi

    echo -n "running ..."

    if [[ "${rootfs}" == *cpio ]]; then
	initcli="rdinit=/sbin/init"
	diskcmd="-initrd ${rootfs}"
    else
	local hddev="sda"
	grep -q CONFIG_IDE=y .config >/dev/null 2>&1
	[ $? -eq 0 ] && hddev="hda"
	initcli="root=/dev/${hddev} rw"
	diskcmd="-drive file=${rootfs},if=ide,format=raw"
    fi

    ${QEMU} -M r2d -kernel ./arch/sh/boot/zImage \
	${diskcmd} \
	-append "${initcli} console=ttySC1,115200 noiotrap" \
	-serial null -serial stdio -monitor null -nographic \
	-no-reboot \
	> ${logfile} 2>&1 &

    pid=$!
    dowait ${pid} ${logfile} automatic waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel rts7751r2dplus_defconfig rootfs.cpio
retcode=$?
runkernel rts7751r2dplus_defconfig rootfs.ext2
retcode=$((${retcode} + $?))

exit ${retcode}
