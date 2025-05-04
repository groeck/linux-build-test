#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

machine=$1

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-microblazeel}
PREFIX=microblazeel-linux-
ARCH=microblaze

if [[ ${linux_version_code} -ge $(kernel_version 6 1) ]]; then
    PATH_MICROBLAZE="/opt/kernel/${DEFAULT_CC}/microblazeel-linux/bin"
else
    # Images built with gcc 10.x+ fail to boot with older kernels
    PATH_MICROBLAZE="/opt/kernel/${DEFAULT_CC9}/microblazeel-linux/bin"
fi

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
    local msg="microblazeel:${mach}"

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	msg+=":initrd"
    else
	msg+=":rootfs"
    fi

    if ! match_params "${machine}@${mach}"; then
	echo "Skipping ${msg} ... "
	return 0
    fi

    echo -n "Building ${msg} ... "

    if ! dosetup -c "${defconfig}" -F "${fixup}" "${rootfs}" "${defconfig}"; then
	return 1
    fi

    execute manual waitlist[@] \
      ${QEMU} -M ${mach} -m 256 \
	-kernel arch/microblaze/boot/linux.bin -no-reboot \
	${extra_params} \
	-append "${initcli} console=${console},115200" \
	-monitor none -serial stdio -nographic

    return $?
}

build_reference "${PREFIX}gcc" "${QEMU}"

retcode=0
runkernel qemu_microblazeel_defconfig petalogix-s3adsp1800 \
		"nolocktests:net=default" ttyUL0 rootfs.cpio
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel qemu_microblazeel_defconfig petalogix-s3adsp1800 \
		"nolocktests:flash16:net=default" ttyUL0 rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel qemu_microblazeel_ml605_defconfig petalogix-ml605 \
		"nolocktests" ttyS0 rootfs.cpio
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel qemu_microblazeel_ml605_defconfig petalogix-ml605 \
		"nolocktests:flash32,11776K,5" ttyS0 rootfs.ext2
retcode=$((retcode + $?))

exit ${retcode}
