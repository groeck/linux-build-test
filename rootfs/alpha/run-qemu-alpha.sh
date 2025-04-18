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

PATH_ALPHA="/opt/kernel/${DEFAULT_CC}/alpha-linux/bin"

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
    local build="${ARCH}:clipper:${defconfig}"

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
	-append "${initcli} console=ttyS0 earlycon=uart8250,io,0x3f8,115200n8" \
	-m 128M -nographic -monitor null -serial stdio

    return $?
}

build_reference "${PREFIX}gcc" "${QEMU}"

# Notes:
# - E100 network tests (all of them) crash immediately
#   in __napi_poll() after enabling interrupts from e100_enable_irq().
# - usb-net fails with "usbnet: failed control transaction".

runkernel defconfig devtmpfs:net=e1000 rootfs.cpio
retcode=$?
checkstate ${retcode}
runkernel defconfig devtmpfs:ide:net=e1000 rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig devtmpfs:sdhci-mmc:net=ne2k_pci rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig devtmpfs:usb-ohci:net=pcnet rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig devtmpfs:usb-ehci:net=virtio-net rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig devtmpfs:pci-bridge:usb-xhci:net=pcnet rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig devtmpfs:usb-uas-ehci:net=e1000 rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig devtmpfs:usb-uas-xhci:net=e1000 rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig "devtmpfs:pci-bridge:scsi[AM53C974]:net=tulip" rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig "devtmpfs:scsi[DC395]:net=e1000-82545em" rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig "devtmpfs:scsi[MEGASAS]:net=rtl8139" rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig "devtmpfs:scsi[MEGASAS2]:net=e1000-82544gc" rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig "devtmpfs:scsi[FUSION]:net=usb-ohci" rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}

if [[ ${runall} -ne 0 ]]; then
    # broken
    # CACHE TEST FAILED: host wrote 1, chip read 0.
    # CACHE TEST FAILED: chip wrote 2, host read 0.
    # sym0: CACHE INCORRECTLY CONFIGURED.
    # sym0: giving up ...
    # WARNING: CPU: 0 PID: 1 at ./include/linux/dma-mapping.h:541 ___free_dma_mem_cluster+0x184/0x1a0
    runkernel defconfig "devtmpfs:scsi[53C810]" rootfs.ext2
    retcode=$((retcode + $?))
    # sym0: SCSI BUS has been reset.
    # sym0: unexpected disconnect
    runkernel defconfig "devtmpfs:scsi[53C895A]" rootfs.ext2
    retcode=$((retcode + $?))
fi

runkernel defconfig devtmpfs:nvme:net=e1000 rootfs.ext2
retcode=$((retcode + $?))

exit ${retcode}
