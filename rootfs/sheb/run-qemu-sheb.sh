#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-sh4eb}
# PREFIX=sh4-linux-
PREFIX=sh4eb-linux-
ARCH=sh
DISPARCH=sheb

skip_414="sheb:rts7751r2dplus_defconfig:flash16,2304K,3:rootfs"
skip_419="sheb:rts7751r2dplus_defconfig:flash16,2304K,3:rootfs"
skip_54="sheb:rts7751r2dplus_defconfig:flash16,2304K,3:rootfs"
skip_510="sheb:rts7751r2dplus_defconfig:flash16,2304K,3:rootfs"
skip_515="sheb:rts7751r2dplus_defconfig:flash16,2304K,3:rootfs"
skip_61="sheb:rts7751r2dplus_defconfig:flash16,2304K,3:rootfs"

if [[ ${linux_version_code} -lt $(kernel_version 5 10) ]]; then
    # boot tests hang with gcc 9.x and later (including 11.4.0)
    # for kernels older than v5.10 when using recent binutils
    # (2.37 or later).
    # Use gcc 11.3.0 with binutils 2.32 instead.
    PATH_SH=/opt/kernel/gcc-11.3.0-2.32-nolibc/sh4eb-linux/bin
else
    PATH_SH=/opt/kernel/${DEFAULT_CC}/sh4eb-linux/bin
fi

PATH=${PATH_SH}:${PATH}

patch_defconfig()
{
    local defconfig=$1

    # Drop command line overwrite
    sed -i -e '/CONFIG_CMDLINE/d' ${defconfig}

    # Enable MTD_BLOCK to be able to boot from flash
    echo "CONFIG_MTD_BLOCK=y" >> ${defconfig}

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

runkernel()
{
    local defconfig=$1
    local fixup=$2
    local rootfs=$3
    local waitlist=("Restarting system" "Boot successful" "Requesting system reboot")
    local build="${DISPARCH}:${defconfig}"

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":${fixup}:rootfs"
    fi

    echo -n "Building ${build} ... "

    if ! checkskip "${build}" ; then
	return 0
    fi

    # Do not use -F: If we do, sheb will fail to run in ToT Linux
    if ! dosetup -c "${defconfig}" -f fixup "${rootfs}" "${defconfig}"; then
	return 1
    fi

    rootfs="$(rootfsname ${rootfs})"
    if ! common_diskcmd "${fixup}" "${rootfs}"; then
	return 1
    fi

    execute automatic waitlist[@] \
      ${QEMU} -M r2d -kernel ./arch/sh/boot/zImage \
	-snapshot \
	${diskcmd} \
	-append "${initcli} console=ttySC1,115200 noiotrap" \
	-serial null -serial stdio -monitor null -nographic \
	-no-reboot

    return $?
}

echo "Build reference: $(git describe --match 'v*')"
echo

retcode=0

runkernel rts7751r2dplus_defconfig "" rootfs.cpio
retcode=$((retcode + $?))
runkernel rts7751r2dplus_defconfig ata rootfs.ext2
retcode=$((retcode + $?))

runkernel rts7751r2dplus_defconfig flash16,2304K,3 rootfs.ext2
retcode=$((retcode + $?))

if [[ ${runall} -ne 0 ]]; then
    # The following are most likely PCI bus endianness translation issues.
    #
    # sdhci-pci 0000:00:01.0: SDHCI controller found [1b36:0007] (rev 0)
    # sdhci-pci 0000:00:01.0: enabling device (0000 -> 0002)
    # mmc0: Unknown controller version (36). You may experience problems.
    # mmc0: SDHCI controller on PCI [0000:00:01.0] using PIO
    # MMC card does not instantiate.
    runkernel rts7751r2dplus_defconfig sdhci-mmc rootfs.ext2
    retcode=$((retcode + $?))
    # nvme nvme0: pci function 0000:00:01.0
    # nvme 0000:00:01.0: enabling device (0000 -> 0002)
    # nvme nvme0: Minimum device page size 1048576 too large for host (4096)
    runkernel rts7751r2dplus_defconfig nvme rootfs.ext2
    retcode=$((retcode + $?))
    # sm501 sm501: incorrect device id a0000105
    # sm501: probe of sm501 failed with error -22
    runkernel rts7751r2dplus_defconfig usb rootfs.ext2
    retcode=$((retcode + $?))
    # xhci_hcd 0000:00:01.0: can't setup: -12
    # xhci_hcd 0000:00:01.0: USB bus 1 deregistered
    runkernel rts7751r2dplus_defconfig usb-xhci rootfs.ext2
    retcode=$((retcode + $?))
    runkernel rts7751r2dplus_defconfig usb-uas-xhci rootfs.ext2
    retcode=$((retcode + $?))
    runkernel rts7751r2dplus_defconfig usb-ehci rootfs.ext2
    retcode=$((retcode + $?))
    runkernel rts7751r2dplus_defconfig usb-ohci rootfs.ext2
    retcode=$((retcode + $?))
    # sym0: CACHE INCORRECTLY CONFIGURED.
    # sym0: giving up ...
    runkernel rts7751r2dplus_defconfig "scsi[53C810]" rootfs.ext2
    retcode=$((${retcode} + $?))
    runkernel rts7751r2dplus_defconfig "scsi[53C895A]" rootfs.ext2
    retcode=$((retcode + $?))
    # hang (scsi command aborts/timeouts)
    # sd 0:0:0:0: Device offlined - not ready after error recovery
    runkernel rts7751r2dplus_defconfig "scsi[DC395]" rootfs.ext2
    retcode=$((retcode + $?))
    # sd 0:0:0:0: Device offlined - not ready after error recovery
    runkernel rts7751r2dplus_defconfig "scsi[AM53C974]" rootfs.ext2
    retcode=$((retcode + $?))
    # Hang after "megaraid_sas 0000:00:01.0: Waiting for FW to come to ready state"
    runkernel rts7751r2dplus_defconfig "scsi[MEGASAS]" rootfs.ext2
    retcode=$((retcode + $?))
    # megaraid_sas 0000:00:01.0: Waiting for FW to come to ready state^M
    # megaraid_sas 0000:00:01.0: FW in FAULT state, Fault code:0x30000 subcode:0x5000 func:megasas_transition_to_ready^M
    runkernel rts7751r2dplus_defconfig "scsi[MEGASAS2]" rootfs.ext2
    retcode=$((retcode + $?))
    # mptbase: ioc0: ERROR - Enable Diagnostic mode FAILED! (00h)
    runkernel rts7751r2dplus_defconfig "scsi[FUSION]" rootfs.ext2
    retcode=$((retcode + $?))
fi


exit ${retcode}
