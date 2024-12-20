#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

_fixup="$1"

# Kernels are unstable (crash randomly) with upstream qemu v7.2.
# Requires local qemu build with offending patch reverted.
QEMU=${QEMU:-${QEMU_BIN}/qemu-system-sh4}


PREFIX=sh4-linux-
ARCH=sh

errlog="/tmp/err-sh.log"

PATH_SH=/opt/kernel/${DEFAULT_CC}/sh4-linux/bin

PATH=${PATH_SH}:${PATH}

patch_defconfig()
{
    local defconfig=$1

    # Drop command line overwrites
    # Note: We can not use disable_config here since the
    # options must be completely removed.
    sed -i -e '/CONFIG_CMDLINE/d' ${defconfig}
    # enable CMDLINE_FROM_BOOTLOADER instead if it exists (v6.10+)
    enable_config ${defconfig} CONFIG_CMDLINE_FROM_BOOTLOADER

    # Enable MTD_BLOCK to be able to boot from flash
    enable_config ${defconfig} CONFIG_MTD_BLOCK
}

runkernel()
{
    local defconfig=$1
    local fixup=$2
    local rootfs=$3
    local waitlist=("Power down" "Boot successful" "Poweroff")
    local build="${ARCH}:${defconfig}:${fixup}"

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

    # 'nofs' is needed to avoid enabling btrfs, which in turn enables raid6,
    # which sometimes hangs in emulation, depending on code alignment.
    if ! dosetup -c "${defconfig}" -F "${fixup}:nofs:nodebug" "${rootfs}" "${defconfig}"; then
	return 1
    fi

    initcli+=" console=ttySC1,115200 noiotrap"

    if [[ ${dodebug} -eq 2 ]]; then
	extra_params+=" -d int,mmu,in_asm,guest_errors,unimp,pcall -D ${errlog}"
    fi

    execute automatic waitlist[@] \
      ${QEMU} -M r2d -kernel ./arch/sh/boot/zImage \
	-no-reboot \
	${extra_params} \
	-append "${initcli}" \
	-serial null -serial stdio \
	-nographic -monitor null

    return ${rv}
}

build_reference "${PREFIX}gcc" "${QEMU}"

# Network test notes:
# - e1000, and variants crash with unaligned fixup in e1000_io_write
# - pcnet crashes with unaligned access in pcnet32_probe1
# - ne2k_pci crashes with null pointer access in ne2k_pci_init_one()
#	The crash is seen when executing the first inb() and are
#	likely because r2d does not support i/o ports and does not set
#	sh_io_port_base.
retcode=0
runkernel rts7751r2dplus_defconfig "net=rtl8139" rootfs.cpio.gz
retcode=$((retcode + $?))
runkernel rts7751r2dplus_defconfig flash16,2304K,3:net=usb-ohci rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel rts7751r2dplus_defconfig ata:net=virtio-net rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel rts7751r2dplus_defconfig sdhci-mmc:net=i82801 rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel rts7751r2dplus_defconfig nvme:net=tulip rootfs.ext2.gz
retcode=$((retcode + $?))

runkernel rts7751r2dplus_defconfig usb:net=i82550 rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel rts7751r2dplus_defconfig usb-hub:net=rtl8139 rootfs.ext2.gz
retcode=$((retcode + $?))

runkernel rts7751r2dplus_defconfig usb-ohci:net=i82557a rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel rts7751r2dplus_defconfig usb-ehci:net=i82562 rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel rts7751r2dplus_defconfig usb-xhci:net=rtl8139 rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel rts7751r2dplus_defconfig usb-uas-ehci:net=rtl8139 rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel rts7751r2dplus_defconfig usb-uas-xhci:net=rtl8139 rootfs.ext2.gz
retcode=$((retcode + $?))

runkernel rts7751r2dplus_defconfig "scsi[53C810]:net=rtl8139" rootfs.ext2.gz
retcode=$((${retcode} + $?))
runkernel rts7751r2dplus_defconfig "scsi[53C895A]:net=rtl8139" rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel rts7751r2dplus_defconfig "scsi[DC395]:net=rtl8139" rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel rts7751r2dplus_defconfig "scsi[AM53C974]:net=rtl8139" rootfs.ext2.gz
retcode=$((retcode + $?))

if [[ ${runall} -ne 0 ]]; then
    # Hang after "megaraid_sas 0000:00:01.0: Waiting for FW to come to ready state"
    runkernel rts7751r2dplus_defconfig "scsi[MEGASAS]" rootfs.ext2.gz
    retcode=$((retcode + $?))
    runkernel rts7751r2dplus_defconfig "scsi[MEGASAS2]" rootfs.ext2.gz
    retcode=$((retcode + $?))
fi

runkernel rts7751r2dplus_defconfig "scsi[FUSION]:net=rtl8139" rootfs.ext2.gz
retcode=$((retcode + $?))

exit ${retcode}
