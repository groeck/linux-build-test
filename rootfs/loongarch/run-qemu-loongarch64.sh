#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

config=$1
variant=$2

QEMU="${QEMU:-${QEMU_BIN}/qemu-system-loongarch64}"

PATH_LOONGARCH="/opt/kernel/gcc-12.2.0-2.39-nolibc/loongarch64-linux-gnu/bin"

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
}

runkernel()
{
    local defconfig=$1
    local mach=$2
    local rootfs=$3
    local fixup=$4
    local waitlist=("Restarting system" "Boot successful" "Rebooting")
    local build="loongarch:${defconfig}:${fixup}"
    local buildconfig="${defconfig}:${fixup%::*}"
    local wait="automatic"
    local mem

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	build+=":initrd"
    elif [[ "${rootfs%.gz}" == *iso ]]; then
	build+=":cd"
    else
	build+=":rootfs"
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
	--append "${initcli} console=ttyS0,115200" \
	-nographic -serial stdio -monitor none

    return $?
}

echo "Build reference: $(git describe --match 'v*')"
echo

# nodebug to reduce boot time (it is already bad because EFI
# takes forever to initialize)
# lock tests result in traceback, sometimes hang with endless
# traceback at do_vint+0x80/0xb4
runkernel defconfig virt rootfs.cpio "nodebug:nolocktests::efi:net,default"
retcode=$?
runkernel defconfig virt rootfs.ext2 "nodebug:nolocktests::efi:nvme:net,default"
retcode=$((retcode + $?))
runkernel defconfig virt rootfs.ext2 "nodebug:nolocktests::efi:usb-xhci:net,default"
retcode=$((retcode + $?))
runkernel defconfig virt rootfs.ext2 "nodebug:nolocktests::efi:scsi[FUSION]:net,default"
retcode=$((retcode + $?))
runkernel defconfig virt rootfs.ext2 "nodebug:nolocktests::efi:scsi[MEGASAS]:net,default"
retcode=$((retcode + $?))

exit ${retcode}
