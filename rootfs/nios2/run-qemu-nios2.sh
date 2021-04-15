#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

machine=$1
config=$2

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-nios2}

PREFIX=nios2-linux-
ARCH=nios2
rootfs=rootfs.cpio
PATH_NIOS2=/opt/kernel/gcc-10.3.0-nolibc/nios2-linux/bin

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

    if ! match_params "${machine}@${mach}" "${config}@${defconfig}"; then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    echo -n "Building ${pbuild} ... "

    dosetup -f fixup "${rootfs}" "${defconfig}"
    retcode=$?
    if [ ${retcode} -ne 0 ]
    then
	if [ ${retcode} -eq 2 ]
	then
	    return 0
	fi
	return 1
    fi

    dts="arch/nios2/boot/dts/${dts}"
    dtb=$(echo ${dts} | sed -e 's/\.dts/\.dtb/')
    dtc -I dts -O dtb ${dts} -o ${dtb} >/dev/null 2>&1

    execute manual waitlist[@] \
      ${QEMU} -M ${mach} \
	-kernel vmlinux -no-reboot \
	-dtb ${dtb} \
	--append "rdinit=/sbin/init ${initcli} earlycon=uart8250,mmio32,0x18001600 console=ttyS0,115200" \
	-initrd "$(rootfsname ${rootfs})" \
	-nographic -monitor none

    return $?
}

echo "Build reference: $(git describe)"
echo

runkernel 10m50-ghrd 10m50_defconfig 10m50_devboard.dts
retcode=$?

exit ${retcode}
