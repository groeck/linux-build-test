#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-sh4eb}
# PREFIX=sh4-linux-
PREFIX=sh4eb-linux-
ARCH=sh
# PATH_SH=/opt/kernel/gcc-4.6.3-nolibc/sh4-linux/bin
# PATH_SH=/opt/kernel/gcc-7.3.0-nolibc/sh4-linux/bin
PATH_SH=/opt/kernel/sh4eb/gcc-6.3.0/usr/bin

PATH=${PATH_SH}:${PATH}

patch_defconfig()
{
    local defconfig=$1

    # Drop command line overwrite
    sed -i -e '/CONFIG_CMDLINE/d' ${defconfig}

    # Enable BLK_DEV_INITRD
    echo "CONFIG_BLK_DEV_INITRD=y" >> ${defconfig}

    # Enable DEVTMPFS
    echo "CONFIG_DEVTMPFS=y" >> ${defconfig}
    echo "CONFIG_DEVTMPFS_MOUNT=y" >> ${defconfig}

    # Build a big endian image
    echo "CONFIG_CPU_LITTLE_ENDIAN=n" >> ${defconfig}
    echo "CONFIG_CPU_BIG_ENDIAN=y" >> ${defconfig}

    # NVME support
    echo "CONFIG_BLK_DEV_NVME=y" >> ${defconfig}

    # USB support
    echo "CONFIG_USB=y" >> ${defconfig}
    echo "CONFIG_USB_XHCI_HCD=y" >> ${defconfig}
    echo "CONFIG_USB_STORAGE=y" >> ${defconfig}
    echo "CONFIG_USB_UAS=y" >> ${defconfig}

    # MMC/SDHCI support
    echo "CONFIG_MMC=y" >> ${defconfig}
    echo "CONFIG_MMC_SDHCI=y" >> ${defconfig}
    echo "CONFIG_MMC_SDHCI_PCI=y" >> ${defconfig}

    # SCSI controller drivers
    echo "CONFIG_SCSI_DC395x=y" >> ${defconfig}
    echo "CONFIG_SCSI_AM53C974=y" >> ${defconfig}
    echo "CONFIG_MEGARAID_SAS=y" >> ${defconfig}
    echo "CONFIG_SCSI_SYM53C8XX_2=y" >> ${defconfig}
    echo "CONFIG_FUSION=y" >> ${defconfig}
    echo "CONFIG_FUSION_SAS=y" >> ${defconfig}
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

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	build+=":initrd"
	initcli="rdinit=/sbin/init"
	diskcmd="-initrd ${rootfs%.gz}"
    else
	build+=":rootfs"
	initcli="root=/dev/sda rw"
	diskcmd="-drive file=${rootfs%.gz},if=ide,format=raw"
    fi

    echo -n "Building ${build} ... "

    if [ "${cached_config}" != "${defconfig}" ]; then
	if ! dosetup -f fixup "${rootfs}" "${defconfig}"; then
	    return 1
	fi
	cached_config="${defconfig}"
    else
	setup_rootfs "${rootfs}"
    fi

    rootfs="${rootfs%.gz}"

    echo -n "running ..."

    [[ ${dodebug} -ne 0 ]] && set -x

    ${QEMU} -M r2d -kernel ./arch/sh/boot/zImage \
	${diskcmd} \
	-append "${initcli} console=ttySC1,115200 noiotrap" \
	-serial null -serial stdio -monitor null -nographic \
	-no-reboot \
	> ${logfile} 2>&1 &
    pid=$!

    [[ ${dodebug} -ne 0 ]] && set +x

    dowait ${pid} ${logfile} automatic waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel rts7751r2dplus_defconfig rootfs.cpio.gz
retcode=$?
runkernel rts7751r2dplus_defconfig rootfs.ext2.gz
retcode=$((${retcode} + $?))

exit ${retcode}
