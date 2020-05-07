#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

machine=$1
_fixup=$2
config=$3

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-sparc64}

PREFIX=sparc64-linux-
ARCH=sparc64
PATH_SPARC=/opt/kernel/sparc64/gcc-6.5.0/bin

PATH=${PATH_SPARC}:${PATH}

skip_316="sparc64:sun4u:smp:scsi[DC395]:cd
	sparc64:sun4u:smp:scsi[AM53C974]:hd"

patch_defconfig()
{
    local defconfig=$1
    local fixup=$2

    # enable ATA instead of IDE.
    echo "CONFIG_IDE=n" >> ${defconfig}
    echo "CONFIG_ATA=y" >> ${defconfig}
    # enable the ATA controller
    echo "CONFIG_PATA_CMD64X=y" >> ${defconfig}
}

runkernel()
{
    local defconfig=$1
    local mach=$2
    local fixup=$3
    local rootfs=$4
    local waitlist=("Power down" "Boot successful" "Poweroff")
    local build="${ARCH}:${mach}:${fixup}"

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	build+=":initrd"
    elif [[ "${rootfs%.gz}" == *iso ]]; then
	build+=":cd"
    else
	build+=":hd"
    fi

    if ! match_params "${machine}@${mach}" "${_fixup}@${fixup}" "${config}@${defconfig}"; then
	echo "Skipping ${build} ... "
	return 0
    fi

    echo -n "Building ${build} ... "

    if ! checkskip "${build}" ; then
	return 0
    fi

    if ! dosetup -c "${defconfig}:${fixup//smp*/smp}" -F "${fixup}" "${rootfs}" "${defconfig}"; then
	if [[ __dosetup_rc -eq 2 ]]; then
	    return 0
	fi
	return 1
    fi

    echo -n "running ..."

    # Explicitly select TI UltraSparc IIi. Non-TI CPUs (including the default
    # CPU for sun4v, Sun-UltraSparc-T1) result in a qemu crash or are stuck
    # in an endless loop at poweroff/reboot.
    execute automatic waitlist[@] \
      ${QEMU} -M ${mach} -cpu "TI UltraSparc IIi" \
	-m 512 \
	${extra_params} \
	-kernel arch/sparc/boot/image -no-reboot \
	-append "${initcli} console=ttyS0" \
	-nographic -monitor none

    return $?
}

echo "Build reference: $(git describe)"
echo

runkernel sparc64_defconfig sun4u smp rootfs.cpio.gz
retcode=$?
runkernel sparc64_defconfig sun4u smp:ata rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4u smp:ata rootfs.iso.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4u smp:ata rootfs.squashfs
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4u smp:sdhci:mmc rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4u smp:nvme rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4u smp:scsi[DC395] rootfs.iso.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4u smp:scsi[MEGASAS] rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4u smp:scsi[AM53C974] rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4u smp:usb-xhci rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4u smp:usb-uas-xhci rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4u smp:virtio-pci rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4v smp:ata rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4v smp:ata rootfs.iso.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4v smp:nvme rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4u nosmp:ata rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4v nosmp:ata rootfs.ext2.gz
retcode=$((retcode + $?))

exit ${retcode}
