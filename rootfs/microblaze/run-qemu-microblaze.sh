#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

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
    local pid
    local waitlist=("Restarting system" "Boot successful" "Rebooting")
    local logfile="$(__mktemp)"

    echo -n "Building ${ARCH}:${defconfig} ... "

    dosetup -d "${rootfs}" "${defconfig}"
    if [ $? -ne 0 ]; then
	return 1
    fi

    echo -n "running ..."

    initcli+=" rdinit=/sbin/init console=${console},115200"
    [[ ${dodebug} -ne 0 ]] && set -x
    ${QEMU} -M ${mach} -m 256 \
	-kernel arch/microblaze/boot/linux.bin -no-reboot \
	-initrd "$(rootfsname ${rootfs})" \
	-append "${initcli}" \
	-monitor none -serial stdio -nographic \
	> ${logfile} 2>&1 &
    pid=$!
    [[ ${dodebug} -ne 0 ]] && set +x

    dowait ${pid} ${logfile} manual waitlist[@]
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
