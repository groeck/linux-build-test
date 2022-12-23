#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

_fixup=$1

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-hppa}

PREFIX=hppa-linux-
ARCH=parisc

PATH_PARISC="/opt/kernel/${DEFAULT_CC}/hppa-linux/bin"
PATH=${PATH}:${PATH_PARISC}

patch_defconfig()
{
    local defconfig=$1

    # ATA
    echo "CONFIG_ATA=y" >> ${defconfig}
    echo "CONFIG_PATA_CMD64X=y" >> ${defconfig}
}

runkernel()
{
    local defconfig="generic-32bit_defconfig"
    local fixup=$1
    local rootfs=$2
    local waitlist=("reboot: Restarting system" "Boot successful" "SeaBIOS wants SYSTEM RESET")

    # pcnet tests need v5.4 or later kernels. On older kernels,
    # the pcnet driver does not clear its rx buffer ring
    # which causes random qemu hiccups.
    if [[ ${linux_version_code} -lt $(kernel_version 5 4) ]]; then
        fixup="$(echo ${fixup} | sed -e 's/net,pcnet/net,rtl8139/')"
    fi

    local build="${ARCH}:${defconfig}${fixup:+:${fixup}}"
    local cache="${defconfig}:${fixup//smp*/smp}"

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":rootfs"
    fi

    if ! match_params "${_fixup}@${fixup}"; then
	echo "Skipping ${build} ... "
	return 0
    fi

    echo -n "Building ${build} ... "

    if ! dosetup -c "${cache}" -F "${fixup}" "${rootfs}" "${defconfig}"; then
	if [[ __dosetup_rc -eq 2 ]]; then
	    return 0
	fi
	return 1
    fi

    execute automatic waitlist[@] \
      ${QEMU} -kernel vmlinux -no-reboot \
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
runkernel smp:net,e1000 rootfs.cpio.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel smp:net,e1000-82544gc:sdhci:mmc rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel smp:net,virtio-net:nvme rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel smp:net,usb-ohci:sata-cmd646 rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel smp:net,pcnet:scsi rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel "smp:net,pcnet:scsi[53C895A]" rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel "smp:net,rtl8139:scsi[DC395]" rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel "smp:net,tulip:scsi[AM53C974]" rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}

if [[ ${runall} -ne 0 ]]; then
    # Random crashes in sym_evaluate_dp(), called from sym_compute_residual()
    # (NULL pointer access). The probem is seen during shutdown. This is a
    # kernel bug, obviously, likely caused by timing differences. It is
    # possible if not likely that an interrupt is seen after the controller
    # was presumably disabled.
    runkernel "smp:scsi[53C810]" rootfs.ext2.gz
    retcode=$((retcode + $?))
    checkstate ${retcode}
    # panic: arch/parisc/kernel/pci-dma.c: pcxl_alloc_range() Too many pages to map.
    runkernel "smp:scsi[MEGASAS]" rootfs.ext2.gz
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel "smp:scsi[MEGASAS2]" rootfs.ext2.gz
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel "smp:scsi[FUSION]" rootfs.ext2.gz
    retcode=$((retcode + $?))
    checkstate ${retcode}
fi

# Run remaining tests with SMP disabled
runkernel nosmp:net,e1000:usb-ohci rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel nosmp:net,virtio-net:usb-ehci rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel nosmp:net,pcnet:usb-xhci rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel nosmp:net,usb-ohci:usb-uas-ehci rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel nosmp:net,rtl8139:usb-uas-xhci rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}

# duplicate some of the previous tests, with SMP disabled
runkernel nosmp:net,e1000 rootfs.cpio.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel nosmp:net,tulip:sdhci:mmc rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel nosmp:net,e1000:nvme rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}

exit ${retcode}
