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

    # Build a big endian image
    echo "CONFIG_CPU_LITTLE_ENDIAN=n" >> ${defconfig}
    echo "CONFIG_CPU_BIG_ENDIAN=y" >> ${defconfig}

    # DEVTMPFS
    echo "CONFIG_DEVTMPFS=y" >> ${defconfig}
    echo "CONFIG_DEVTMPFS_MOUNT=y" >> ${defconfig}

    # BLK_DEV_INITRD
    echo "CONFIG_BLK_DEV_INITRD=y" >> ${defconfig}

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
    local fixup=$2
    local rootfs=$3
    local pid
    local retcode
    local logfile=$(mktemp)
    local waitlist=("Restarting system" "Boot successful" "Requesting system reboot")
    local build="${ARCH}:${defconfig}"

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":${fixup}:rootfs"
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

    if ! common_diskcmd "${fixup##*:}" "${rootfs}"; then
	return 1
    fi

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

retcode=0

runkernel rts7751r2dplus_defconfig "" rootfs.cpio.gz
retcode=$((retcode + $?))
runkernel rts7751r2dplus_defconfig ata rootfs.ext2.gz
retcode=$((retcode + $?))

if [[ ${runall} -ne 0 ]]; then
    # Most likely those are all PCI bus endianness translation issues.
    # SD card does not instantiate
    runkernel rts7751r2dplus_defconfig mmc rootfs.ext2.gz
    retcode=$((retcode + $?))
    # nvme nvme0: Device not ready; aborting initialisation
    # nvme nvme0: Removing after probe failure status: -19
    runkernel rts7751r2dplus_defconfig nvme rootfs.ext2.gz
    retcode=$((retcode + $?))
    # sm501 sm501: incorrect device id a0000105
    # sm501: probe of sm501 failed with error -22
    runkernel rts7751r2dplus_defconfig usb rootfs.ext2.gz
    retcode=$((retcode + $?))
    # xhci_hcd 0000:00:01.0: can't setup: -12
    # xhci_hcd 0000:00:01.0: USB bus 1 deregistered
    runkernel rts7751r2dplus_defconfig usb-xhci rootfs.ext2.gz
    retcode=$((retcode + $?))
    runkernel rts7751r2dplus_defconfig usb-uas-xhci rootfs.ext2.gz
    retcode=$((retcode + $?))
    # sym0: CACHE INCORRECTLY CONFIGURED.
    # sym0: giving up ...
    runkernel rts7751r2dplus_defconfig "scsi[53C810]" rootfs.ext2.gz
    retcode=$((${retcode} + $?))
    runkernel rts7751r2dplus_defconfig "scsi[53C895A]" rootfs.ext2.gz
    retcode=$((retcode + $?))
    # hang (scsi command aborts/timeouts)
    runkernel rts7751r2dplus_defconfig "scsi[DC395]" rootfs.ext2.gz
    retcode=$((retcode + $?))
    runkernel rts7751r2dplus_defconfig "scsi[AM53C974]" rootfs.ext2.gz
    retcode=$((retcode + $?))
    # Hang after "megaraid_sas 0000:00:01.0: Waiting for FW to come to ready state"
    runkernel rts7751r2dplus_defconfig "scsi[MEGASAS]" rootfs.ext2.gz
    retcode=$((retcode + $?))
    runkernel rts7751r2dplus_defconfig "scsi[MEGASAS2]" rootfs.ext2.gz
    retcode=$((retcode + $?))
    # mptbase: ioc0: ERROR - Enable Diagnostic mode FAILED! (00h)
    runkernel rts7751r2dplus_defconfig "scsi[FUSION]" rootfs.ext2.gz
    retcode=$((retcode + $?))
fi


exit ${retcode}
