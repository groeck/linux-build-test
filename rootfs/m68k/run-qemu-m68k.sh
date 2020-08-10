#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

machine=$1

QEMU=${QEMU:-${QEMU_V51_BIN}/qemu-system-m68k}
PREFIX=m68k-linux-
ARCH=m68k
PATH_M68K=/opt/kernel/gcc-7.3.0-nolibc/m68k-linux/bin

PATH=${PATH_M68K}:${PATH}

patch_defconfig()
{
    local defconfig=$1
    local mach=$2
    local rootfs="$(rootfsname rootfs-5208.cpio)"

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
	echo "CONFIG_INITRAMFS_SOURCE=\"${rootfs}\"" >> ${defconfig}
	echo "CONFIG_INITRAMFS_ROOT_UID=0" >> ${defconfig}
	echo "CONFIG_INITRAMFS_ROOT_GID=0" >> ${defconfig}

	# Boot parameters are not passed
	sed -i -e '/CONFIG_BOOTPARAM_STRING/d' ${defconfig}
	echo 'CONFIG_BOOTPARAM_STRING="panic=-1 console=ttyS0,115200"' >> ${defconfig}
    fi
}

runkernel()
{
    local mach=$1
    local cpu=$2
    local defconfig=$3
    local rootfs=$4
    local waitlist=("Rebooting" "Boot successful")
    local build="${mach}:${cpu}:${defconfig}"
    local qemu="${QEMU}"

    if [[ "${rootfs}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":rootfs"
    fi

    if ! match_params "${machine}@${mach}"; then
	echo "Skipping ${build} ... "
	return 0
    fi

    echo -n "Building ${build} ... "

    dosetup -c "${defconfig}" -d -f "${mach}" "${rootfs}" "${defconfig}"
    if [ $? -ne 0 ]; then
	return 1
    fi

    rootfs="$(rootfsname ${rootfs})"
    if [[ "${rootfs}" == *cpio ]]; then
	if [[ "${mach}" = "q800" ]]; then
	    initcli+=" rdinit=/sbin/init"
	    diskcmd="-initrd ${rootfs}"
	else
	    # initrd is embedded in image
	    diskcmd=""
	fi
    else
	initcli+=" root=/dev/sda rw"
	diskcmd="-snapshot -drive file=${rootfs},format=raw"
    fi

    execute manual waitlist[@] \
      ${qemu} -M ${mach} \
	-kernel vmlinux -cpu ${cpu} \
	-no-reboot -nographic -monitor none \
	${diskcmd} \
	-append "${initcli} console=ttyS0,115200"

    return $?
}

echo "Build reference: $(git describe)"
echo

retcode=0
runkernel mcf5208evb m5208 m5208evb_defconfig rootfs-5208.cpio
retcode=$((retcode + $?))
runkernel q800 m68040 mac_defconfig rootfs-68040.cpio
retcode=$((retcode + $?))
runkernel q800 m68040 mac_defconfig rootfs-68040.ext2
retcode=$((retcode + $?))

exit ${retcode}
