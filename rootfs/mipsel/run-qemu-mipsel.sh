#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

_cpu=$1
config=$2
variant=$3

rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
PATH_MIPS=/opt/kernel/gcc-9.3.0-nolibc/mips-linux/bin
QEMU=${QEMU:-${QEMU_BIN}/qemu-system-mipsel}
PREFIX=mips-linux-

# machine specific information
ARCH=mips
KERNEL_IMAGE=vmlinux
QEMU_MACH=malta

PATH=${PATH_MIPS}:${PATH}

skip_316="mipsel:M14Kc:malta_defconfig:nocd:smp:scsi[DC395]:rootfs \
	mipsel:24Kf:malta_defconfig:nocd:smp:scsi[AM53C974]:rootfs \
	mipsel:mips32r6-generic:malta_qemu_32r6_defconfig:nocd:smp:ide:rootfs"

patch_defconfig()
{
    local defconfig=$1
    local fixups=${2//:/ }
    local fixup

    for fixup in ${fixups}; do
	if [[ "${fixup}" == "smp" ]]; then
	    echo "CONFIG_MIPS_MT_SMP=y" >> ${defconfig}
	elif [[ "${fixup}" == "nosmp" ]]; then
	    echo "CONFIG_MIPS_MT_SMP=n" >> ${defconfig}
	fi
    done
}

runkernel()
{
    local cpu=$1
    local defconfig=$2
    local fixup="$3"
    local rootfs=$4
    local waitlist=("Boot successful" "Rebooting")
    local build="mipsel:${cpu}:${defconfig}:${fixup}"
    local buildconfig="${defconfig}:${fixup//smp*/smp}"

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":rootfs"
    fi

    if ! match_params "${_cpu}@${cpu}" "${config}@${defconfig}" "${variant}@${fixup}"; then
	echo "Skipping ${build} ... "
	return 0
    fi

    echo -n "Building ${build} ... "

    if ! checkskip "${build}" ; then
	return 0
    fi

    if ! dosetup -c "${buildconfig}" -F "${fixup}" "${rootfs}" "${defconfig}"; then
	if [[ __dosetup_rc -eq 2 ]]; then
	    return 0
	fi
	return 1
    fi

    execute automatic waitlist[@] \
      ${QEMU} -kernel ${KERNEL_IMAGE} -M ${QEMU_MACH} -cpu ${cpu} \
	-vga cirrus -no-reboot \
	${extra_params} \
	--append "${initcli} console=ttyS0 ${extracli}" \
	-nographic

    return $?
}

echo "Build reference: $(git describe)"
echo

# Most images fail to instantiate CD ROM because there is an insufficient
# amount of DMA memory.

runkernel 24Kf malta_defconfig nocd:smp rootfs.cpio.gz
retcode=$?
runkernel 24Kf malta_defconfig nocd:smp:ide rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))

if [[ ${runall} -ne 0 ]]; then
    # Kernel bug detected[#1]:
    # Workqueue: nvme-reset-wq nvme_reset_work
    runkernel 24Kf malta_defconfig nocd:smp:nvme rootfs-mipselr1.ext2.gz
    retcode=$((retcode + $?))
fi

runkernel 24Kf malta_defconfig nocd:smp:usb-xhci rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))
runkernel 24Kf malta_defconfig nocd:smp:usb-ehci rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))
runkernel 24Kc malta_defconfig nocd:smp:usb-uas-xhci rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))
runkernel 24KEc malta_defconfig nocd:smp:sdhci:mmc rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))
runkernel 34Kf malta_defconfig nocd:smp:scsi[53C810] rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))
runkernel 74Kf malta_defconfig nocd:smp:scsi[53C895A] rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))
runkernel M14Kc malta_defconfig nocd:smp:scsi[DC395] rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))
runkernel 24Kf malta_defconfig nocd:smp:scsi[AM53C974] rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))
runkernel 24Kf malta_defconfig nocd:smp:scsi[MEGASAS] rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))
runkernel 24Kf malta_defconfig nocd:smp:scsi[MEGASAS2] rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))
runkernel 24Kf malta_defconfig nocd:smp:scsi[FUSION] rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))

runkernel mips32r6-generic malta_qemu_32r6_defconfig nocd:smp:ide rootfs-mipselr6.ext2.gz
retcode=$((retcode + $?))

runkernel 24Kf malta_defconfig nosmp rootfs.cpio.gz
retcode=$((retcode + $?))
runkernel 24Kf malta_defconfig nosmp:ide rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))

exit ${retcode}
