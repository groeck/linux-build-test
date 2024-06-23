#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

_machine=$1
_fixup=$2

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-hppa}

PREFIX=hppa-linux-
ARCH=parisc

PATH_PARISC="/opt/kernel/${DEFAULT_CC}/hppa-linux/bin"
PATH=${PATH}:${PATH_PARISC}

patch_defconfig()
{
    local defconfig=$1

    # ATA
    enable_config ${defconfig} CONFIG_ATA CONFIG_PATA_CMD64X

    # file systems
    echo "CONFIG_F2FS_FS=y" >> ${defconfig}

    # Disable for now until warning messages have been fixed
    disable_config "${defconfig}" CONFIG_PROVE_LOCKING CONFIG_DEBUG_LOCKDEP CONFIG_DEBUG_LOCK_ALLOC CONFIG_DEBUG_WW_MUTEX_SLOWPATH
}

runkernel()
{
    local machine=$1
    local config=$2
    local fixup=$3
    local rootfs=$4
    local waitlist=("reboot: Restarting system" "Boot successful" "SeaBIOS wants SYSTEM RESET")

    # pcnet tests need v5.4 or later kernels. On older kernels,
    # the pcnet driver does not clear its rx buffer ring
    # which causes random qemu hiccups.
    if [[ ${linux_version_code} -lt $(kernel_version 5 4) ]]; then
        fixup="$(echo ${fixup} | sed -e 's/net=pcnet/net=rtl8139/')"
    fi

    local build="${ARCH}:${machine}${fixup:+:${fixup}}"

    if [[ "${rootfs}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":${rootfs##*.}"
    fi

    build="${build//+(:)/:}"

    if ! match_params "${_machine}@${machine}" "${_fixup}@${fixup}"; then
	echo "Skipping ${build} ... "
	return 0
    fi

    echo -n "Building ${build} ... "

    if ! dosetup -c "${config}${fixup%::*}" -F "${fixup}" "${rootfs}" "${config}"; then
	if [[ __dosetup_rc -eq 2 ]]; then
	    return 0
	fi
	return 1
    fi

    execute automatic waitlist[@] \
      ${QEMU} -M ${machine} -kernel vmlinux -no-reboot \
	${extra_params} \
	-append "${initcli} console=ttyS0,115200 ${extracli}" \
	-nographic -monitor null -serial stdio

    return $?
}

build_reference "${PREFIX}gcc" "${QEMU}"

# run initial set of tests with SMP enabled.
# Multi-core boots take a long time to boot, so don't test with more
# than one CPU until qemu has been improved.

# Network test notes:
# i82550:
#   crashes with
#	arch/parisc/kernel/pci-dma.c: pcxl_alloc_range() Too many pages to map
# ne2k_pci:
#   Fails with
#	"Dino 0x00810000: stuck interrupt 2"
#   and
#	"NETDEV WATCHDOG: eth0 (ne2k-pci): transmit queue 0 timed out"
#
# pci-bridge fails to instantiate after
#	"WARNING: CPU: 0 PID: 1 at drivers/parisc/dino.c:608 0x10120988"

retcode=0
runkernel B160L generic-32bit_defconfig ::net=e1000 rootfs.cpio
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel B160L generic-32bit_defconfig ::net=e1000-82544gc:sdhci-mmc rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel B160L generic-32bit_defconfig ::net=virtio-net:nvme rootfs.ext4
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel B160L generic-32bit_defconfig ::net=usb-ohci:sata-cmd646 rootfs.btrfs
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel B160L generic-32bit_defconfig ::net=pcnet:scsi rootfs.f2fs
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel B160L generic-32bit_defconfig "::net=pcnet:scsi[53C895A]" rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel B160L generic-32bit_defconfig "::net=rtl8139:scsi[DC395]" rootfs.ext4
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel B160L generic-32bit_defconfig "::net=tulip:scsi[AM53C974]" rootfs.btrfs
retcode=$((retcode + $?))
checkstate ${retcode}

if [[ ${runall} -ne 0 ]]; then
    # Random crashes in sym_evaluate_dp(), called from sym_compute_residual()
    # (NULL pointer access). The problem is seen during shutdown. This is a
    # kernel bug, obviously, likely caused by timing differences. It is
    # possible if not likely that an interrupt is seen after the controller
    # was presumably disabled.
    runkernel B160L generic-32bit_defconfig "::scsi[53C810]" rootfs.ext2
    retcode=$((retcode + $?))
    checkstate ${retcode}
    # panic: arch/parisc/kernel/pci-dma.c: pcxl_alloc_range() Too many pages to map.
    runkernel B160L generic-32bit_defconfig "::scsi[MEGASAS]" rootfs.ext2
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel B160L generic-32bit_defconfig "::scsi[MEGASAS2]" rootfs.ext2
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel B160L generic-32bit_defconfig "::scsi[FUSION]" rootfs.ext2
    retcode=$((retcode + $?))
    checkstate ${retcode}
fi

# Run remaining tests with C3700 platform using the 32-bit configuration
# Note: e1000 doesn't work with C3700
runkernel C3700 generic-32bit_defconfig "::net=tulip:scsi[AM53C974]" rootfs.btrfs
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel C3700 generic-32bit_defconfig "::net=tulip:scsi[DC395]" rootfs.f2fs
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel C3700 generic-32bit_defconfig ::net=tulip:usb-ohci rootfs.f2fs
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel C3700 generic-32bit_defconfig ::net=virtio-net:usb-ehci rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel C3700 generic-32bit_defconfig ::net=pcnet:usb-xhci rootfs.ext4
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel C3700 generic-32bit_defconfig ::net=usb-ohci:usb-uas-ehci rootfs.btrfs
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel C3700 generic-32bit_defconfig ::net=rtl8139:usb-uas-xhci rootfs.f2fs
retcode=$((retcode + $?))
checkstate ${retcode}

exit ${retcode}
