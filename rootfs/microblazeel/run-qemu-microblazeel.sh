#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

machine=$1

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-microblazeel}
PREFIX=microblazeel-linux-
ARCH=microblaze
PATH_MICROBLAZE=/opt/kernel/microblazeel/gcc-4.9.1/usr/bin

PATH=${PATH_MICROBLAZE}:${PATH}

runkernel()
{
    local defconfig=$1
    local mach=$2
    local console=$3
    local rootfs=$4
    local waitlist=("Restarting system" "Boot successful" "Rebooting")

    if ! match_params "${machine}@${mach}"; then
	echo "Skipping ${ARCH}:${defconfig} ... "
	return 0
    fi

    echo -n "Building ${ARCH}:${mach}:${defconfig} ... "

    dosetup -d "${rootfs}" "${defconfig}"
    if [ $? -ne 0 ]; then
	return 1
    fi

    execute manual waitlist[@] \
      ${QEMU} -M ${mach} -m 256 \
	-kernel arch/microblaze/boot/linux.bin -no-reboot \
	-initrd "$(rootfsname ${rootfs})" \
	-append "${initcli} rdinit=/sbin/init console=${console},115200" \
	-monitor none -serial stdio -nographic

    return $?
}

echo "Build reference: $(git describe)"
echo

retcode=0
runkernel qemu_microblazeel_defconfig petalogix-s3adsp1800 ttyUL0 rootfs.cpio
retcode=$((retcode + $?))
runkernel qemu_microblazeel_ml605_defconfig petalogix-ml605 ttyS0 rootfs.cpio
retcode=$((retcode + $?))

exit ${retcode}
