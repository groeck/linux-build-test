#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-m68k}
PREFIX=m68k-linux-
ARCH=m68k
PATH_M68K=/opt/kernel/gcc-7.3.0-nolibc/m68k-linux/bin

PATH=${PATH_M68K}:${PATH}

patch_defconfig()
{
    local defconfig=$1
    local mach=$2

    if [[ "${mach}" = "mcf5208evb" ]]; then
	# Enable DEVTMPFS
	sed -i -e '/CONFIG_BLK_DEV_INITRD/d' ${defconfig}
	echo "CONFIG_BLK_DEV_INITRD=y" >> ${defconfig}
	sed -i -e '/CONFIG_DEVTMPFS/d' ${defconfig}
	echo "CONFIG_DEVTMPFS=y" >> ${defconfig}
	sed -i -e '/CONFIG_DEVTMPFS_MOUNT/d' ${defconfig}
	echo "CONFIG_DEVTMPFS_MOUNT=y" >> ${defconfig}

	# Specify initramfs file name
	sed -i -e '/CONFIG_INITRAMFS_SOURCE/d' ${defconfig}
	sed -i -e '/CONFIG_INITRAMFS_ROOT_UID/d' ${defconfig}
	sed -i -e '/CONFIG_INITRAMFS_ROOT_GID/d' ${defconfig}
	echo "CONFIG_INITRAMFS_SOURCE=\"rootfs.cpio\"" >> ${defconfig}
	echo "CONFIG_INITRAMFS_ROOT_UID=0" >> ${defconfig}
	echo "CONFIG_INITRAMFS_ROOT_GID=0" >> ${defconfig}
    fi
}

runkernel()
{
    local mach=$1
    local cpu=$2
    local defconfig=$3
    local rootfs=$4
    local pid
    local retcode
    local waitlist=("Rebooting" "Boot successful")
    local logfile=/tmp/runkernel-$$.log
    local build="${mach}:${cpu}:${defconfig}"
    local qemu="${QEMU}"

    if [[ "${rootfs}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":rootfs"
    fi

    echo -n "Building ${build} ... "

    dosetup -c "${defconfig}" -d -f "${mach}" "${rootfs}" "${defconfig}"
    if [ $? -ne 0 ]; then
	return 1
    fi

    if [[ "${rootfs}" == *cpio ]]; then
	if [[ "${mach}" = "q800" ]]; then
	    initcli="rdinit=/sbin/init"
	    diskcmd="-initrd ${rootfs}"
	else
	    # initrd is embedded in image
	    initcli=""
	    diskcmd=""
	fi
    else
	initcli="root=/dev/sda rw"
	diskcmd="-drive file=${rootfs},format=raw"
    fi

    echo -n "running ..."

    if [[ "${mach}" = "q800" ]]; then
	# q800 needs special qemu, which in turn does not support mcf5208evb
	qemu="${QEMU_V211_M68K_BIN}/qemu-system-m68k"
    fi

    [[ ${dodebug} -ne 0 ]] && set -x

    ${qemu} -M ${mach} \
	-kernel vmlinux -cpu ${cpu} \
	-no-reboot -nographic -monitor none \
	${diskcmd} \
	-append "${initcli} console=ttyS0,115200" \
	> ${logfile} 2>&1 &
    pid=$!

    [[ ${dodebug} -ne 0 ]] && set +x

    dowait ${pid} ${logfile} manual waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel mcf5208evb m5208 m5208evb_defconfig rootfs.cpio
runkernel q800 m68040 mac_defconfig rootfs-q800.cpio
runkernel q800 m68040 mac_defconfig rootfs.ext2

exit $?
