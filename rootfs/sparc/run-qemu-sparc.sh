#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

machine=$1
variant=$2

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-sparc}
PREFIX=sparc64-linux-
ARCH=sparc32

PATH_SPARC=/opt/kernel/sparc64/gcc-6.5.0/bin

PATH=${PATH_SPARC}:${PATH}

patch_defconfig()
{
    local defconfig=$1
    local fixups=${2//:/ }
    local fixup

    # Common root file system needs to have TMPFS enabled.
    echo "CONFIG_TMPFS=y" >> ${defconfig}
    # We won't test btrfs. Drop it to reduce image size.
    echo "CONFIG_BTRFS_FS=n" >> ${defconfig}
    # enable ethernet interface
    echo "CONFIG_NET_VENDOR_SUN=y" >> ${defconfig}
    echo "CONFIG_HAPPYMEAL=y" >> ${defconfig}
    # We don't currently test IPv6 so drop it to reduce image size
    echo "CONFIG_IPV6=n" >> ${defconfig}

    for fixup in ${fixups}; do
	case "${fixup}" in
	*)
	    ;;
	esac
    done
}

runkernel()
{
    local defconfig=$1
    local mach=$2
    local cpu=$3
    local fixup=$4
    local rootfs=$5
    local waitlist=("Restarting system" "Boot successful" "Rebooting")
    local build="${ARCH}:${mach}:${fixup}"
    local config="${defconfig}:${fixup//smp*/smp}"

    if [[ "${rootfs}" == *cpio ]]; then
	build+=":initrd"
    elif [[ "${rootfs%.gz}" == *iso ]]; then
	build+=":cd"
    else
	build+=":hd"
    fi

    if ! match_params "${machine}@${mach}" "${variant}@${fixup}"; then
	echo "Skipping ${build} ... "
	return 0
    fi

    echo -n "Building ${build} ... "

    # novirt:nousb:noscsi to reduce image size
    if ! dosetup -c "${config}" -F "novirt:nousb:noscsi:${fixup}" "${rootfs}" "${defconfig}"; then
	if [[ __dosetup_rc -eq 2 ]]; then
	    return 0
	fi
	return 1
    fi

    if [[ "${fixup/noapc}" != "${fixup}" ]]; then
	initcli+=" apc=noidle"
    fi

    execute automatic waitlist[@] \
      ${QEMU} -M ${mach} \
	-kernel arch/sparc/boot/zImage -no-reboot \
	${cpu:+-cpu "${cpu}"} \
	${extra_params} \
	-append "${initcli} console=ttyS0" \
	-nographic -monitor none

    return $?
}

echo "Build reference: $(git describe)"
echo

# Override CPU on systems which set TI-MicroSparc-I by default.
# On those systems, the new root file system stalls when loading
# run.sh with endless faults and no fault reason.
runkernel sparc32_defconfig SPARCClassic "Fujitsu-MB86904" nosmp:scsi:net,default rootfs.ext2
retcode=$?
runkernel sparc32_defconfig SPARCbook "Fujitsu-MB86904" nosmp:scsi:net,default rootfs.iso
retcode=$((retcode + $?))
runkernel sparc32_defconfig LX "Fujitsu-MB86904" nosmp:noapc:scsi:net,default rootfs.sqf
retcode=$((retcode + $?))
runkernel sparc32_defconfig SS-4 "" nosmp:net,default rootfs.cpio
retcode=$((retcode + $?))
runkernel sparc32_defconfig SS-5 "" nosmp:scsi:net,default rootfs.ext2
retcode=$((retcode + $?))
runkernel sparc32_defconfig SS-10 "" nosmp:scsi:net,default rootfs.iso
retcode=$((retcode + $?))
runkernel sparc32_defconfig SS-20 "" nosmp:scsi:net,default rootfs.sqf
retcode=$((retcode + $?))
runkernel sparc32_defconfig SS-600MP "" nosmp:scsi:net,default rootfs.ext2
retcode=$((retcode + $?))
runkernel sparc32_defconfig Voyager "" nosmp:noapc:scsi:net,default rootfs.ext2
retcode=$((retcode + $?))
runkernel sparc32_defconfig SS-4 "" smp:scsi:net,default rootfs.ext2
retcode=$((retcode + $?))
runkernel sparc32_defconfig SS-5 "" smp:scsi:net,default rootfs.iso
retcode=$((retcode + $?))
runkernel sparc32_defconfig SS-10 "" smp:scsi:net,default rootfs.sqf
retcode=$((retcode + $?))
runkernel sparc32_defconfig SS-20 "" smp:scsi:net,default rootfs.ext2
retcode=$((retcode + $?))
runkernel sparc32_defconfig SS-600MP "" smp:scsi:net,default rootfs.ext2
retcode=$((retcode + $?))
runkernel sparc32_defconfig Voyager "" smp:noapc:scsi:net,default rootfs.ext2
retcode=$((retcode + $?))

exit ${retcode}
