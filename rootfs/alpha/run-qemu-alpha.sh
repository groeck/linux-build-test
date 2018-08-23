#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-alpha}

PREFIX=alpha-linux-
ARCH=alpha

rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
PATH_ALPHA=/opt/kernel/gcc-6.4.0-nolibc/alpha-linux/bin

PATH=${PATH_ALPHA}:${PATH}

skip_316="alpha:defconfig:scsi[AM53C974]:rootfs \
	alpha:defconfig:scsi[DC395]:rootfs"

skip_318="alpha:defconfig:scsi[AM53C974]:rootfs \
	alpha:defconfig:scsi[DC395]:rootfs"

patch_defconfig()
{
    : # nothing to do
}

runkernel()
{
    local defconfig=$1
    local fixup=$2
    local rootfs=$3
    local pid
    local logfile="$(__mktemp)"
    local waitlist=("Boot successful" "Rebooting" "Restarting system")
    local build="${ARCH}:${defconfig}"

    if [[ "${rootfs}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":${fixup}"
	build+=":rootfs"
    fi

    echo -n "Building ${build} ... "

    if ! checkskip "${build}" ; then
	return 0
    fi

    dosetup -F "${fixup}" -c "${defconfig}" "${rootfs}" "${defconfig}"
    if [ $? -ne 0 ]; then
	return 1
    fi

    echo -n "running ..."

    [[ ${dodebug} -ne 0 ]] && set -x

    ${QEMU} -M clipper \
	-kernel arch/alpha/boot/vmlinux -no-reboot \
	${extra_params} \
	-append "${initcli} console=ttyS0" \
	-m 128M -nographic -monitor null -serial stdio \
	> ${logfile} 2>&1 &
    pid=$!

    [[ ${dodebug} -ne 0 ]] && set +x

    dowait ${pid} ${logfile} auto waitlist[@]
    return $?
}

echo "Build reference: $(git describe)"
echo

runkernel defconfig devtmpfs busybox-alpha.cpio
rv=$?
runkernel defconfig ata rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig mmc rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig usb-ohci rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig usb-ehci rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig usb-xhci rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig usb-uas-ehci rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig usb-uas-xhci rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig "scsi[AM53C974]" rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig "scsi[DC395]" rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig "scsi[MEGASAS]" rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig "scsi[MEGASAS2]" rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig "scsi[FUSION]" rootfs.ext2
retcode=$((${retcode} + $?))

if [[ ${runall} -ne 0 ]]; then
    # broken
    # CACHE TEST FAILED: host wrote 1, chip read 0.
    # CACHE TEST FAILED: chip wrote 2, host read 0.
    # sym0: CACHE INCORRECTLY CONFIGURED.
    # sym0: giving up ...
    # WARNING: CPU: 0 PID: 1 at ./include/linux/dma-mapping.h:541 ___free_dma_mem_cluster+0x184/0x1a0
    runkernel defconfig "scsi[53C810]" rootfs.ext2
    retcode=$((${retcode} + $?))
    # sym0: SCSI BUS has been reset.
    # sym0: unexpected disconnect
    runkernel defconfig "scsi[53C895A]" rootfs.ext2
    retcode=$((${retcode} + $?))
fi

runkernel defconfig nvme rootfs.ext2
retcode=$((${retcode} + $?))

exit ${rv}
