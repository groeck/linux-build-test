#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

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
    local waitlist=("Power down" "Boot successful" "Poweroff")
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
	-append "${initcli} console=ttySC1,115200 noiotrap doreboot" \
	-serial null -serial stdio -net nic,model=rtl8139 -net user \
	-nographic -monitor null \
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
runkernel rts7751r2dplus_defconfig mmc rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel rts7751r2dplus_defconfig nvme rootfs.ext2.gz
retcode=$((retcode + $?))

if [[ ${runall} -ne 0 ]]; then
    # usb technically works. However, it defaults to ohci, which generates
    # a large number of warning tracebacks due to disabled interrupts and
    # missing DMA coherence masks.
    runkernel rts7751r2dplus_defconfig usb rootfs.ext2.gz
    retcode=$((retcode + $?))
fi

runkernel rts7751r2dplus_defconfig usb-xhci rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel rts7751r2dplus_defconfig usb-uas-xhci rootfs.ext2.gz
retcode=$((retcode + $?))

runkernel rts7751r2dplus_defconfig "scsi[53C810]" rootfs.ext2.gz
retcode=$((${retcode} + $?))
runkernel rts7751r2dplus_defconfig "scsi[53C895A]" rootfs.ext2.gz
retcode=$((retcode + $?))

if [[ ${runall} -ne 0 ]]; then
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
fi

runkernel rts7751r2dplus_defconfig "scsi[FUSION]" rootfs.ext2.gz
retcode=$((retcode + $?))

exit ${retcode}
