#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

machine=$1

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-microblaze}
PREFIX=microblaze-linux-
ARCH=microblaze
rootfs=rootfs.cpio
PATH_MICROBLAZE=/opt/kernel/gcc-4.8.0-nolibc/microblaze-linux/bin

PATH=${PATH_MICROBLAZE}:${PATH}

runkernel()
{
    local defconfig=$1
    local mach=$2
    local console=$3
    local waitlist=("Restarting system" "Boot successful" "Rebooting")

    if ! match_params "${machine}@${mach}"; then
	echo "Skipping ${ARCH}:${defconfig} ... "
	return 0
    fi

    echo -n "Building ${ARCH}:${defconfig} ... "

    dosetup -d "${rootfs}" "${defconfig}"
    if [ $? -ne 0 ]; then
	return 1
    fi

    initcli+=" rdinit=/sbin/init console=${console},115200"

    execute manual waitlist[@] \
      ${QEMU} -M ${mach} -m 256 \
	-kernel arch/microblaze/boot/linux.bin -no-reboot \
	-initrd "$(rootfsname ${rootfs})" \
	-append "${initcli}" \
	-monitor none -serial stdio -nographic

    return $?
}

echo "Build reference: $(git describe)"
echo

retcode=0
runkernel qemu_microblaze_defconfig petalogix-s3adsp1800 ttyUL0
retcode=$((retcode + $?))
runkernel qemu_microblaze_ml605_defconfig petalogix-ml605 ttyS0
retcode=$((retcode + $?))

exit ${retcode}
