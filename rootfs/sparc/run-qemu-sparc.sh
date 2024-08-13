#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

machine=$1
variant=$2

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-sparc}
PREFIX=sparc-linux-
ARCH=sparc32

PATH_SPARC=/opt/kernel/${DEFAULT_CC}/sparc-linux/bin

PATH=${PATH_SPARC}:${PATH}

patch_defconfig()
{
    local defconfig=$1
    local fixups=${2//:/ }
    local fixup

    # Common root file system needs to have TMPFS enabled.
    enable_config ${defconfig} CONFIG_TMPFS
    # We won't test btrfs. Drop it to reduce image size.
    disable_config ${defconfig} CONFIG_BTRFS_FS
    # We do test squashfs, so enable it explicitly
    enable_config ${defconfig} CONFIG_SQUASHFS
    # enable ethernet interface
    enable_config ${defconfig} CONFIG_NET_VENDOR_SUN
    enable_config ${defconfig} CONFIG_HAPPYMEAL
    # We don't currently test the following so drop to reduce image size
    disable_config ${defconfig} CONFIG_IPV6 CONFIG_WIRELESS
    disable_config ${defconfig} CONFIG_HWMON CONFIG_NETWORK_FILESYSTEMS CONFIG_KGDB
    disable_config ${defconfig} CONFIG_UTS_NS CONFIG_IPC_NS
    disable_config ${defconfig} CONFIG_PID_NS CONFIG_NET_NS
    # Try to optimize for size
    enable_config ${defconfig} CONFIG_CC_OPTIMIZE_FOR_SIZE

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

    # no*: options to reduce image size
    if ! dosetup -c "${config}" -F "nofs:nonet:nonvme:novirt:nousb:noscsi:${fixup}" "${rootfs}" "${defconfig}"; then
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

build_reference "${PREFIX}gcc" "${QEMU}"

# Override CPU on systems which set TI-MicroSparc-I by default.
# On those systems, the new root file system stalls when loading
# run.sh with endless faults and no fault reason.
runkernel sparc32_defconfig SPARCClassic "Fujitsu-MB86904" nosmp:scsi:net=default rootfs.ext2
retcode=$?
checkstate ${retcode}
runkernel sparc32_defconfig SPARCbook "Fujitsu-MB86904" nosmp:scsi:net=default rootfs.iso
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel sparc32_defconfig LX "Fujitsu-MB86904" nosmp:noapc:scsi:net=default rootfs.sqf
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel sparc32_defconfig SS-4 "" nosmp:net=default rootfs.cpio
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel sparc32_defconfig SS-5 "" nosmp:scsi:net=default rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel sparc32_defconfig SS-10 "" nosmp:scsi:net=default rootfs.iso
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel sparc32_defconfig SS-20 "" nosmp:scsi:net=default rootfs.sqf
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel sparc32_defconfig SS-600MP "" nosmp:scsi:net=default rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel sparc32_defconfig Voyager "" nosmp:noapc:scsi:net=default rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel sparc32_defconfig SS-4 "" smp:scsi:net=default rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel sparc32_defconfig SS-5 "" smp:scsi:net=default rootfs.iso
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel sparc32_defconfig SS-10 "" smp:scsi:net=default rootfs.sqf
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel sparc32_defconfig SS-20 "" smp:scsi:net=default rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel sparc32_defconfig SS-600MP "" smp:scsi:net=default rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel sparc32_defconfig Voyager "" smp:noapc:scsi:net=default rootfs.ext2
retcode=$((retcode + $?))

exit ${retcode}
