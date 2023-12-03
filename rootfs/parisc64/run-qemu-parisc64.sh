#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

_machine=$1
_fixup=$2

QEMU=${QEMU:-${QEMU_V82_BIN}/qemu-system-hppa}

PREFIX=hppa64-linux-
PREFIX32=hppa-linux-
ARCH=parisc64

PATH_PARISC64="/opt/kernel/${DEFAULT_CC12}/hppa64-linux/bin"
PATH_PARISC32="/opt/kernel/${DEFAULT_CC12}/hppa-linux/bin"
PATH=${PATH}:${PATH_PARISC64}:${PATH_PARISC32}

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
	-nographic -monitor null

    return $?
}

echo "Build reference: $(git describe --match 'v*')"
echo

# Network test notes:
# i82550:
#   crashes with
#	arch/parisc/kernel/pci-dma.c: pcxl_alloc_range() Too many pages to map
# ne2k_pci:
#   Fails with
#	"Dino 0x00810000: stuck interrupt 2"
#   and/or
#	"NETDEV WATCHDOG: eth0 (ne2k-pci): transmit queue 0 timed out"
#   and/or
#	hang with spinlock recursion
#
# pci-bridge fails to instantiate after
#	"WARNING: CPU: 0 PID: 1 at drivers/parisc/dino.c:608 0x10120988"
#
# e1000, e1000-82544gc: fail to enable interface

retcode=0
runkernel C3700 generic-64bit_defconfig ::net=pcnet rootfs.cpio
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel C3700 generic-64bit_defconfig ::net=virtio-net:nvme rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel C3700 generic-64bit_defconfig ::net=tulip:sata-cmd646 rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel C3700 generic-64bit_defconfig ::net=i82801:usb-uas-ehci rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel C3700 generic-64bit_defconfig "::net=rtl8139:scsi[DC395]" rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel C3700 generic-64bit_defconfig "::net=tulip:scsi[AM53C974]" rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel C3700 generic-64bit_defconfig ::net=usb-xhci:sdhci-mmc rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel C3700 generic-64bit_defconfig ::net=virtio-net:usb-ehci rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel C3700 generic-64bit_defconfig ::net=pcnet:usb-xhci rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}

if [[ ${runall} -ne 0 ]]; then
    # Unstable, may result in hung task crash in usb_start_wait_urb/usb_kill_urb
    # during shutdown, possibly/likely due to net=usb-ohci problems
    runkernel C3700 generic-64bit_defconfig ::net=usb-ohci:sata-cmd646 rootfs.ext2
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel C3700 generic-64bit_defconfig ::net=usb-ohci:usb-uas-ehci rootfs.ext2
    retcode=$((retcode + $?))
    checkstate ${retcode}
fi

runkernel C3700 generic-64bit_defconfig ::net=tulip:usb-uas-ehci rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel C3700 generic-64bit_defconfig ::net=rtl8139:usb-uas-xhci rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}

exit ${retcode}
