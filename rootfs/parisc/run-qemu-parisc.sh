#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

_machine=$1
_fixup=$2

# QEMU=${QEMU:-${QEMU_BIN}/qemu-system-hppa}
QEMU=${QEMU:-${QEMU_V82_BIN}/qemu-system-hppa}

PREFIX=hppa-linux-
ARCH=parisc

PATH_PARISC="/opt/kernel/${DEFAULT_CC}/hppa-linux/bin"
PATH=${PATH}:${PATH_PARISC}

patch_defconfig()
{
    local defconfig=$1

    # ATA
    enable_config ${defconfig} CONFIG_ATA CONFIG_PATA_CMD64X

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
    local cache="${config}:${fixup//smp*/smp}"

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":rootfs"
    fi

    if ! match_params "${_machine}@${machine}" "${_fixup}@${fixup}"; then
	echo "Skipping ${build} ... "
	return 0
    fi

    echo -n "Building ${build} ... "

    if ! dosetup -c "${cache}" -F "${fixup}" "${rootfs}" "${config}"; then
	if [[ __dosetup_rc -eq 2 ]]; then
	    return 0
	fi
	return 1
    fi

    execute automatic waitlist[@] \
      ${QEMU} -M ${machine} -kernel vmlinux -no-reboot \
	${extra_params} \
	-append "${initcli} console=ttyS0,115200 ${extracli}" \
	-nographic -monitor null

    return $?
}

echo "Build reference: $(git describe --match 'v*')"
echo

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
runkernel B160L generic-32bit_defconfig smp:net=e1000 rootfs.cpio.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel B160L generic-32bit_defconfig smp:net=e1000-82544gc:sdhci-mmc rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel B160L generic-32bit_defconfig smp:net=virtio-net:nvme rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel B160L generic-32bit_defconfig smp:net=usb-ohci:sata-cmd646 rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel B160L generic-32bit_defconfig smp:net=pcnet:scsi rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel B160L generic-32bit_defconfig "smp:net=pcnet:scsi[53C895A]" rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel B160L generic-32bit_defconfig "smp:net=rtl8139:scsi[DC395]" rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel B160L generic-32bit_defconfig "smp:net=tulip:scsi[AM53C974]" rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}

if [[ ${runall} -ne 0 ]]; then
    # Random crashes in sym_evaluate_dp(), called from sym_compute_residual()
    # (NULL pointer access). The problem is seen during shutdown. This is a
    # kernel bug, obviously, likely caused by timing differences. It is
    # possible if not likely that an interrupt is seen after the controller
    # was presumably disabled.
    runkernel B160L generic-32bit_defconfig "smp:scsi[53C810]" rootfs.ext2.gz
    retcode=$((retcode + $?))
    checkstate ${retcode}
    # panic: arch/parisc/kernel/pci-dma.c: pcxl_alloc_range() Too many pages to map.
    runkernel B160L generic-32bit_defconfig "smp:scsi[MEGASAS]" rootfs.ext2.gz
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel B160L generic-32bit_defconfig "smp:scsi[MEGASAS2]" rootfs.ext2.gz
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel B160L generic-32bit_defconfig "smp:scsi[FUSION]" rootfs.ext2.gz
    retcode=$((retcode + $?))
    checkstate ${retcode}
fi

# e1000 and e1000-82544gc don't work for C3700
# ne2k_pci hangs with spinlock recursion
runkernel C3700 generic-64bit_defconfig smp:net=pcnet rootfs.cpio.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel C3700 generic-64bit_defconfig smp:net=virtio-net:nvme rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel C3700 generic-64bit_defconfig smp:net=usb-ohci:sata-cmd646 rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel C3700 generic-64bit_defconfig smp:net=i82801:usb-uas-ehci rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel C3700 generic-64bit_defconfig smp:net=tulip:usb-xhci rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel C3700 generic-64bit_defconfig "smp:net=rtl8139:scsi[DC395]" rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel C3700 generic-64bit_defconfig smp:net=usb-xhci:sdhci-mmc rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}

# Run remaining tests with SMP disabled
runkernel B160L generic-32bit_defconfig nosmp:net=e1000:usb-ohci rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel B160L generic-32bit_defconfig nosmp:net=virtio-net:usb-ehci rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel B160L generic-32bit_defconfig nosmp:net=pcnet:usb-xhci rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel B160L generic-32bit_defconfig nosmp:net=usb-ohci:usb-uas-ehci rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel B160L generic-32bit_defconfig nosmp:net=rtl8139:usb-uas-xhci rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}

# duplicate some of the previous tests, with SMP disabled
runkernel B160L generic-32bit_defconfig nosmp:net=e1000 rootfs.cpio.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel B160L generic-32bit_defconfig nosmp:net=tulip:sdhci-mmc rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel B160L generic-32bit_defconfig nosmp:net=e1000:nvme rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}

exit ${retcode}
