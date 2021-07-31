#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

machine=$1

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-microblazeel}
PREFIX=microblazeel-linux-
ARCH=microblaze
PATH_MICROBLAZE="/opt/kernel/microblazeel/gcc-4.9.1/usr/bin"

PATH="${PATH_MICROBLAZE}:${PATH}"

patch_defconfig()
{
    :
}

runkernel()
{
    local defconfig=$1
    local mach=$2
    local fixup=$3
    local console=$4
    local rootfs=$5
    local waitlist=("Restarting system" "Boot successful" "Rebooting")
    local msg="${ARCH}:${mach}"

    if ! match_params "${machine}@${mach}"; then
	echo "Skipping ${msg} ... "
	return 0
    fi

    echo -n "Building ${msg} ... "

    if ! dosetup -F "${fixup}" "${rootfs}" "${defconfig}"; then
	return 1
    fi

    execute manual waitlist[@] \
      ${QEMU} -M ${mach} -m 256 \
	-kernel arch/microblaze/boot/linux.bin -no-reboot \
	-initrd "$(rootfsname ${rootfs})" \
	-append "${initcli} console=${console},115200" \
	-monitor none -serial stdio -nographic

    return $?
}

echo "Build reference: $(git describe)"
echo

retcode=0
runkernel qemu_microblazeel_defconfig petalogix-s3adsp1800 "nolocktests:net,default" ttyUL0 rootfs.cpio
retcode=$((retcode + $?))
runkernel qemu_microblazeel_ml605_defconfig petalogix-ml605 "nolocktests" ttyS0 rootfs.cpio
retcode=$((retcode + $?))

exit ${retcode}
