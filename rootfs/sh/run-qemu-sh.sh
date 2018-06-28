#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-sh4}

PREFIX=sh4-linux-
ARCH=sh

PATH_SH=/opt/kernel/sh4/gcc-5.3.0/usr/bin

PATH=${PATH_SH}:${PATH}

patch_defconfig()
{
    local defconfig=$1

    # Drop command line overwrite
    sed -i -e '/CONFIG_CMDLINE/d' ${defconfig}

    # Enable DEVTMPFS
    echo "CONFIG_DEVTMPFS=y" >> ${defconfig}
    echo "CONFIG_DEVTMPFS_MOUNT=y" >> ${defconfig}

    # Enable BLK_DEV_INITRD
    echo "CONFIG_BLK_DEV_INITRD=y" >> ${defconfig}
}

cached_config=""

runkernel()
{
    local defconfig=$1
    local rootfs=$2
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Power down" "Boot successful" "Poweroff")
    local build="${ARCH}:${defconfig}"

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":rootfs"
    fi

    echo -n "Building ${build} ... "

    if [ "${cached_config}" != "${defconfig}" ]; then
	dosetup -f fixup "${rootfs}" "${defconfig}"
	if [ $? -ne 0 ]; then
	    return 1
	fi
	cached_config="${defconfig}"
    else
	setup_rootfs "${rootfs}"
    fi

    if [[ "${rootfs}" == *.gz ]]; then
	gunzip -f "${rootfs}"
	rootfs="${rootfs%.gz}"
    fi

    echo -n "running ..."

    if [[ "${rootfs}" == *cpio ]]; then
	initcli="rdinit=/sbin/init"
	diskcmd="-initrd ${rootfs}"
    else
	initcli="root=/dev/sda"
	diskcmd="-drive file=${rootfs},if=ide,format=raw"
    fi

    ${QEMU} -M r2d -kernel ./arch/sh/boot/zImage \
	${diskcmd} \
	-append "${initcli} console=ttySC1,115200 noiotrap doreboot" \
	-serial null -serial stdio -net nic,model=rtl8139 -net user \
	-nographic -monitor null \
	> ${logfile} 2>&1 &

    pid=$!
    dowait ${pid} ${logfile} automatic waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

retcode=0
runkernel rts7751r2dplus_defconfig rootfs.cpio.gz
retcode=$((retcode + $?))
runkernel rts7751r2dplus_defconfig rootfs.ext2.gz
retcode=$((retcode + $?))

exit ${retcode}
