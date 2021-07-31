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

# Images built with gcc 10.3.0 fail to boot
PATH_MICROBLAZE="/opt/kernel/gcc-9.3.0-nolibc/microblaze-linux/bin"

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
    local waitlist=("Restarting system" "Boot successful" "Rebooting")
    local msg="${ARCH}:${mach}"

    if ! match_params "${machine}@${mach}"; then
	echo "Skipping ${msg} ... "
	return 0
    fi

    echo -n "Building ${msg} ... "

    if [[ ${linux_version_code} -lt $(kernel_version 4 14) ]]; then
	# Older kernels get a bad case of hiccup (hang during boot)
	# when enabling additional configuration options.
	fixup="noextras:${fixup}"
    fi

    if ! dosetup -F "${fixup}" "${rootfs}" "${defconfig}"; then
	return 1
    fi

    initcli+=" console=${console},115200"

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

# locking tests result in hard lockup

retcode=0
runkernel qemu_microblaze_defconfig petalogix-s3adsp1800 "nolocktests:net,default" ttyUL0
retcode=$((retcode + $?))
runkernel qemu_microblaze_ml605_defconfig petalogix-ml605 "nolocktests" ttyS0
retcode=$((retcode + $?))

exit ${retcode}
