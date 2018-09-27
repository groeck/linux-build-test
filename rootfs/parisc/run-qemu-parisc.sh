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

PATH_PARISC=/opt/kernel/hppa/gcc-7.3.0/bin
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
    local defconfig=$1
    local fixup=$2
    local rootfs=$3
    local pid
    local logfile="$(__mktemp)"
    local waitlist=("reboot: Restarting system" "Boot successful" "Requesting system reboot")
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

    dosetup -c "${cache}" -F "${fixup}" "${rootfs}" "${defconfig}"
    if [ $? -ne 0 ]; then
	return 1
    fi

    rootfs="${rootfs%.gz}"

    echo -n "running ..."

    [[ ${dodebug} -ne 0 ]] && set -x

    ${QEMU} -kernel vmlinux -no-reboot \
	${extra_params} \
	-append "${initcli} console=ttyS0,115200 ${extracli}" \
	-nographic -monitor null > ${logfile} 2>&1 &
    pid=$!

    [[ ${dodebug} -ne 0 ]] && set +x

    dowait ${pid} ${logfile} automatic waitlist[@]
    return $?
}

echo "Build reference: $(git describe)"
echo

# run initial set of tests with SMP enabled.
# Multi-core boots take a long time to boot, so don't test with more
# than one CPU until qemu has been improved.

retcode=0
runkernel defconfig smp rootfs.cpio.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig smp:mmc rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig smp:nvme rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig smp:sata-cmd646 rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig smp:scsi rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig "smp:scsi[53C895A]" rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig "smp:scsi[DC395]" rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig "smp:scsi[AM53C974]" rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}

if [[ ${runall} -ne 0 ]]; then
    # panic: arch/parisc/kernel/pci-dma.c: pcxl_alloc_range() Too many pages to map.
    runkernel defconfig "smp:scsi[MEGASAS]" rootfs.ext2.gz
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel defconfig "smp:scsi[MEGASAS2]" rootfs.ext2.gz
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel defconfig "smp:scsi[FUSION]" rootfs.ext2.gz
    retcode=$((retcode + $?))
    checkstate ${retcode}
fi

# Run remaining tests with SMP disabled
runkernel defconfig nosmp:usb-ohci rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig nosmp:usb-ehci rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig nosmp:usb-xhci rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig nosmp:usb-uas-ehci rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig nosmp:usb-uas-xhci rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}

# duplicate some of the previous tests, with SMP disabled
runkernel defconfig nosmp rootfs.cpio.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig nosmp:mmc rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig nosmp:nvme rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}

exit ${retcode}
