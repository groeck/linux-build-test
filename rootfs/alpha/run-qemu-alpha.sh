#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

option=$1

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-alpha}

PREFIX=alpha-linux-
ARCH=alpha

rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
PATH_ALPHA=/opt/kernel/gcc-10.2.0-nolibc/alpha-linux/bin

PATH=${PATH_ALPHA}:${PATH}

patch_defconfig()
{
    : # nothing to do
}

runkernel()
{
    local defconfig=$1
    local fixup=$2
    local rootfs=$3
    local waitlist=("Boot successful" "Rebooting" "Restarting system")
    local build="${ARCH}:${defconfig}"

    if [[ "${rootfs}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":${fixup}"
	build+=":rootfs"
    fi

   if ! match_params "${option}@${fixup}"; then
	echo "Skipping ${build} ... "
	return 0
    fi

    echo -n "Building ${build} ... "

    if ! checkskip "${build}" ; then
	return 0
    fi

    dosetup -F "${fixup}" -c "${defconfig}" "${rootfs}" "${defconfig}"
    if [ $? -ne 0 ]; then
	return 1
    fi

    execute auto waitlist[@] \
      ${QEMU} -M clipper \
	-kernel arch/alpha/boot/vmlinux -no-reboot \
	${extra_params} \
	-append "${initcli} console=ttyS0" \
	-m 128M -nographic -monitor null -serial stdio

    return $?
}

echo "Build reference: $(git describe)"
echo

# Notes:
# - E100 network tests (all of them) crash immediately
#   in __napi_poll() after enabling interrupts from e100_enable_irq().
# - usb-net fails with "usbnet: failed control transaction".

runkernel defconfig devtmpfs rootfs.cpio
retcode=$?
runkernel defconfig ide:net,e1000 rootfs.ext2
retcode=$((retcode + $?))
runkernel defconfig sdhci:mmc:net,ne2k_pci rootfs.ext2
retcode=$((retcode + $?))
runkernel defconfig usb-ohci:net,pcnet rootfs.ext2
retcode=$((retcode + $?))
runkernel defconfig usb-ehci:net,virtio-net rootfs.ext2
retcode=$((retcode + $?))
runkernel defconfig usb-xhci rootfs.ext2
retcode=$((retcode + $?))
runkernel defconfig usb-uas-ehci rootfs.ext2
retcode=$((retcode + $?))
runkernel defconfig usb-uas-xhci rootfs.ext2
retcode=$((retcode + $?))
runkernel defconfig "scsi[AM53C974]:net,tulip" rootfs.ext2
retcode=$((retcode + $?))
runkernel defconfig "scsi[DC395]:net,e1000-82545em" rootfs.ext2
retcode=$((retcode + $?))
runkernel defconfig "scsi[MEGASAS]:net,rtl8139" rootfs.ext2
retcode=$((retcode + $?))
runkernel defconfig "scsi[MEGASAS2]:net,e1000-82544gc" rootfs.ext2
retcode=$((retcode + $?))
runkernel defconfig "scsi[FUSION]" rootfs.ext2
retcode=$((retcode + $?))

if [[ ${runall} -ne 0 ]]; then
    # broken
    # CACHE TEST FAILED: host wrote 1, chip read 0.
    # CACHE TEST FAILED: chip wrote 2, host read 0.
    # sym0: CACHE INCORRECTLY CONFIGURED.
    # sym0: giving up ...
    # WARNING: CPU: 0 PID: 1 at ./include/linux/dma-mapping.h:541 ___free_dma_mem_cluster+0x184/0x1a0
    runkernel defconfig "scsi[53C810]" rootfs.ext2
    retcode=$((retcode + $?))
    # sym0: SCSI BUS has been reset.
    # sym0: unexpected disconnect
    runkernel defconfig "scsi[53C895A]" rootfs.ext2
    retcode=$((retcode + $?))
fi

runkernel defconfig nvme rootfs.ext2
retcode=$((retcode + $?))

exit ${retcode}
