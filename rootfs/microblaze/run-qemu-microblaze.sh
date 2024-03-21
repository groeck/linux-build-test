#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

machine=$1

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-microblaze}
PREFIX=microblaze-linux-
ARCH=microblaze

if [[ ${linux_version_code} -ge $(kernel_version 6 1) ]]; then
    PATH_MICROBLAZE="/opt/kernel/${DEFAULT_CC}/microblaze-linux/bin"
else
    # Images built with gcc 11.x+ fail to boot with old kernels
    PATH_MICROBLAZE="/opt/kernel/${DEFAULT_CC9}/microblaze-linux/bin"
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
    local msg="${ARCH}:${mach}"

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

    if ! checkskip "${msg}" ; then
        return 0
    fi

    if ! dosetup -c "${defconfig}" -F "${fixup}" "${rootfs}" "${defconfig}"; then
	return 1
    fi

    initcli+=" console=${console},115200"

    execute manual waitlist[@] \
      ${QEMU} -M ${mach} -m 256 \
	-kernel arch/microblaze/boot/linux.bin -no-reboot \
	${extra_params} \
	-append "${initcli}" \
	-monitor none -serial stdio -nographic

    return $?
}

echo "Build reference: $(git describe --match 'v*')"
echo

# locking tests result in hard lockup

retcode=0
runkernel qemu_microblaze_defconfig petalogix-s3adsp1800 \
		"nolocktests:net=default" ttyUL0 rootfs.cpio
retcode=$((retcode + $?))
runkernel qemu_microblaze_defconfig petalogix-s3adsp1800 \
		"nolocktests:flash16:net=default" ttyUL0 rootfs.ext2
retcode=$((retcode + $?))
runkernel qemu_microblaze_ml605_defconfig petalogix-ml605 \
		"nolocktests" ttyS0 rootfs.cpio
retcode=$((retcode + $?))
runkernel qemu_microblaze_ml605_defconfig petalogix-ml605 \
		"nolocktests:flash32,11776K,5" ttyS0 rootfs.ext2
retcode=$((retcode + $?))

exit ${retcode}
