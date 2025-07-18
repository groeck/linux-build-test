#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

config=$1
variant=$2

QEMU="${QEMU:-${QEMU_BIN}/qemu-system-loongarch64}"

# loongarch needs gcc 13.x+ when using binutils 2.40.
PATH_LOONGARCH="/opt/kernel/${DEFAULT_CC13}/loongarch64-linux-gnu/bin"

PREFIX=loongarch64-linux-gnu-

# machine specific information
ARCH=loongarch
PATH=${PATH_LOONGARCH}:${PATH}

# Called from dosetup() to patch the configuration file.
patch_defconfig()
{
    local defconfig=$1
    local fixups=${2//:/ }
    local fixup

    # pointless, waste of time to build
    disable_config "${defconfig}" CONFIG_DRM_AMDGPU
    disable_config "${defconfig}" CONFIG_DRM_RADEON

    # Needed for TPM tests
    enable_config "${defconfig}" CONFIG_TCG_TPM CONFIG_TCG_TIS
}

runkernel()
{
    local defconfig=$1
    local mach=$2
    local rootfs=$3
    local fixup=$4
    local waitlist=("Restarting system" "Boot successful" "Rebooting")
    local build="loongarch:${mach}:${defconfig}:${fixup}"
    local buildconfig="${defconfig}:${fixup%::*}"
    local wait="automatic"
    local mem

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	build+=":initrd"
    elif [[ "${rootfs%.gz}" == *iso ]]; then
	build+=":cd"
    else
	build+=":${rootfs##*.}"
    fi

    build="${build//+(:)/:}"

    if ! match_params "${config}@${defconfig}" "${variant}@${fixup}"; then
	echo "Skipping ${build} ... "
	return 0
    fi

    echo -n "Building ${build} ... "

    if ! checkskip "${build}"; then
	return 0;
    fi

    if ! dosetup -c "${buildconfig}" -F "${fixup:-fixup}" "${rootfs}" "${defconfig}"; then
	# echo "dosetup returned ${__dosetup_rc}"
	if [[ __dosetup_rc -eq 2 ]]; then
	    return 0
	fi
	return 1
    fi

    case ${mach} in
    *)
	;;
    esac

    execute ${wait} waitlist[@] \
      ${QEMU} -M ${mach} -cpu la464 -kernel arch/loongarch/boot/vmlinuz.efi \
	-smp 2 -no-reboot -m 4G \
	${extra_params} \
	--append "${initcli} console=ttyS0,115200 earlycon=uart8250,mmio,0x1fe001e0,115200n8" \
	-nographic -serial stdio -monitor none

    return $?
}

build_reference "${PREFIX}gcc" "${QEMU}"

__runkernel_common()
{
    local prefix="$1:"

    if [[ ${linux_version_code} -le $(kernel_version 6 1) && "${runall}" -eq 0 ]]; then
	# nodebug to reduce boot time
	nodebug="nodebug:"
	# lock tests result in traceback, sometimes hang with endless
	# traceback at do_vint+0x80/0xb4
	nodebug+="nolocktests:"
	prefix+="${nodebug}"
    fi

    runkernel defconfig virt rootfs.cpio "${prefix}::efi:net=default"
    retcode=$?
    checkstate ${retcode}
    if [[ ${linux_version_code} -ge $(kernel_version 6 6) ]]; then
	# Note: tpm needs qemu v9.1+ and Linux kernel v6.6+
	runkernel defconfig virt rootfs.cpio "${prefix}:tpm-tis-device:efi:net=default"
	retcode=$((retcode + $?))
	checkstate ${retcode}
    fi
    runkernel defconfig virt rootfs.ext2 "${prefix}:efi:nvme:net=default"
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel defconfig virt rootfs.ext2 "${prefix}:efi:usb-xhci:net=default"
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel defconfig virt rootfs.btrfs "${prefix}:efi:scsi[FUSION]:net=default"
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel defconfig virt rootfs.ext2 "${prefix}:efi:scsi[MEGASAS]:net=default:fstest=xfs"
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel defconfig virt rootfs.squashfs "${prefix}:efi:sdhci-mmc:net=default"
    retcode=$((retcode + $?))
    
    return ${retcode}
}
