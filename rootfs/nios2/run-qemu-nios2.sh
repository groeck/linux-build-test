#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

machine=$1
config=$2

# nios2 support was removed in qemu 9.1.
QEMU=${QEMU:-${QEMU_V90_BIN}/qemu-system-nios2}

PREFIX=nios2-linux-
ARCH=nios2
rootfs=rootfs.cpio
PATH_NIOS2="/opt/kernel/${DEFAULT_CC}/nios2-linux/bin"

PATH=${PATH_NIOS2}:${PATH}

patch_defconfig()
{
    local defconfig=$1
    local progdir=$(cd $(dirname $0); pwd)

    echo "CONFIG_NIOS2_PASS_CMDLINE=y" >> ${defconfig}
    echo "CONFIG_BLK_DEV_INITRD=y" >> ${defconfig}
}

runkernel()
{
    local mach=$1
    local defconfig=$2
    local dts=$3
    local retcode
    local waitlist=("Restarting system" "Boot successful" "Machine restart")
    local pbuild="${ARCH}:${mach}:${defconfig}:${dts}"
    local dtb

    if ! match_params "${machine}@${mach}" "${config}@${defconfig}"; then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    echo -n "Building ${pbuild} ... "

    # Disable all testing and debugging.
    # Note that lockdep and atomic sleep debugging are known to trigger
    # backtraces.
    dosetup -F nosecurity:nodebug:notests:nofs:noscsi:nonvme:nousb:nocd:novirt "${rootfs}" "${defconfig}"
    retcode=$?
    if [ ${retcode} -ne 0 ]
    then
	if [ ${retcode} -eq 2 ]
	then
	    return 0
	fi
	return 1
    fi

    dtb="$(gendtb "arch/nios2/boot/dts/${dts}")"

    execute manual waitlist[@] \
      ${QEMU} -M ${mach} \
	-kernel vmlinux -no-reboot \
	-dtb "${dtb}" \
	--append "rdinit=/sbin/init ${initcli} earlycon=uart8250,mmio32,0x18001600 console=ttyS0,115200" \
	-initrd "$(rootfsname ${rootfs})" \
	-nographic -monitor none

    return $?
}

build_reference "${PREFIX}gcc" "${QEMU}"

runkernel 10m50-ghrd 10m50_defconfig 10m50_devboard.dts
retcode=$?

exit ${retcode}
