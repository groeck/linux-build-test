#!/bin/bash

progdir=$(cd $(dirname "$0"); pwd)
. "${progdir}/../scripts/config.sh"
. "${progdir}/../scripts/common.sh"

parse_args "$@"
shift $((OPTIND - 1))

_fixup="$1"

QEMU=${QEMU:-${QEMU_V31_BIN}/qemu-system-riscv64}
PREFIX=riscv64-linux-
ARCH=riscv
PATH_RISCV=/opt/kernel/riscv64/gcc-7.3.0/bin

PATH=${PATH}:${PATH_RISCV}

patch_defconfig()
{
    local defconfig=$1
    local fixups=${2//:/ }
    local fixup

    echo "CONFIG_PCI_HOST_GENERIC=y" >> ${defconfig}
}

cached_config=""

runkernel()
{
    local mach=$1
    local defconfig=$2
    local fixup=$3
    local rootfs=$4
    local pid
    local waitlist=("Power off" "Boot successful" "Requesting system poweroff")
    local logfile="$(__mktemp)"
    local build="${ARCH}:${mach}:${defconfig}${fixup:+:${fixup}}"

    if [[ "${rootfs}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":rootfs"
    fi

    if ! match_params "${_fixup}@${fixup}"; then
	echo "Skipping ${build} ... "
	return 0
    fi

    echo -n "Building ${build} ... "

    if ! checkskip "${build}" ; then
	return 0
    fi

    if ! dosetup -c "${defconfig}" -F "${fixup}" "${rootfs}" "${defconfig}"; then
	if [[ __dosetup_rc -eq 2 ]]; then
	    return 0
	fi
	return 1
    fi

    echo -n "running ..."

    [[ ${dodebug} -ne 0 ]] && set -x

    ${QEMU} -M virt -m 512M -no-reboot \
	-bios "${progdir}/bbl" \
	-kernel vmlinux \
	-netdev user,id=net0 -device virtio-net-device,netdev=net0 \
	${extra_params} \
	-append "${initcli} console=ttyS0,115200" \
	-nographic -monitor none \
	> ${logfile} 2>&1 &
    pid=$!

    [[ ${dodebug} -ne 0 ]] && set +x

    dowait ${pid} ${logfile} automatic waitlist[@]
    return $?
}

echo "Build reference: $(git describe)"
echo

retcode=0
runkernel virt defconfig "" rootfs.cpio
retcode=$((retcode + $?))
runkernel virt defconfig virtio-blk rootfs.ext2
retcode=$((retcode + $?))
runkernel virt defconfig virtio rootfs.ext2
retcode=$((retcode + $?))
runkernel virt defconfig virtio-pci rootfs.ext2
retcode=$((retcode + $?))
runkernel virt defconfig mmc rootfs.ext2
retcode=$((retcode + $?))
runkernel virt defconfig nvme rootfs.ext2
retcode=$((retcode + $?))

if [[ ${runall} -ne 0 ]]; then
    runkernel virt defconfig usb-ohci rootfs.ext2
    retcode=$((${retcode} + $?))
fi

runkernel virt defconfig usb-ehci rootfs.ext2
retcode=$((${retcode} + $?))
runkernel virt defconfig usb-xhci rootfs.ext2
retcode=$((${retcode} + $?))
runkernel virt defconfig usb-uas-ehci rootfs.ext2
retcode=$((${retcode} + $?))
runkernel virt defconfig usb-uas-xhci rootfs.ext2
retcode=$((${retcode} + $?))
runkernel virt defconfig "scsi[53C810]" rootfs.ext2
retcode=$((${retcode} + $?))
runkernel virt defconfig "scsi[53C895A]" rootfs.ext2
retcode=$((${retcode} + $?))

if [[ ${runall} -ne 0 ]]; then
    # Does not instantiate
    runkernel virt defconfig "scsi[AM53C974]" rootfs.ext2
    retcode=$((${retcode} + $?))
    runkernel virt defconfig "scsi[DC395]" rootfs.ext2
    retcode=$((${retcode} + $?))
fi

runkernel virt defconfig "scsi[MEGASAS]" rootfs.ext2
retcode=$((${retcode} + $?))
runkernel virt defconfig "scsi[MEGASAS2]" rootfs.ext2
retcode=$((${retcode} + $?))
runkernel virt defconfig "scsi[FUSION]" rootfs.ext2
retcode=$((${retcode} + $?))
runkernel virt defconfig "scsi[virtio]" rootfs.ext2
retcode=$((${retcode} + $?))
runkernel virt defconfig "scsi[virtio-pci]" rootfs.ext2
retcode=$((${retcode} + $?))

exit ${retcode}
