#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

machine=$1
smpflag=$2
config=$3

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-sparc64}

PREFIX=sparc64-linux-
ARCH=sparc64
rootfs="rootfs.ext2.gz"
PATH_SPARC=/opt/kernel/gcc-6.4.0-nolibc/sparc64-linux/bin

PATH=${PATH_SPARC}:${PATH}

patch_defconfig()
{
    local defconfig=$1
    local smp=$2

    # Configure SMP as requested, enable DEVTMPFS,
    # and enable ATA instead of IDE.

    sed -i -e '/CONFIG_SMP/d' ${defconfig}
    sed -i -e '/CONFIG_DEVTMPFS/d' ${defconfig}
    sed -i -e '/IDE/d' ${defconfig}
    echo "
CONFIG_DEVTMPFS=y
CONFIG_DEVTMPFS_MOUNT=y
CONFIG_ATA=y
CONFIG_PATA_CMD64X=y
    " >> ${defconfig}

    if [ "${smp}" = "nosmp" ]
    then
	echo "# CONFIG_SMP is not set" >> ${defconfig}
    else
	echo "CONFIG_SMP=y" >> ${defconfig}
    fi
}

runkernel()
{
    local defconfig=$1
    local mach=$2
    local smp=$3
    local pid
    local logfile="$(__mktemp)"
    local waitlist=("Power down" "Boot successful" "Poweroff")
    local build=${ARCH}:${mach}:${smp}:${defconfig}

    if ! match_params "${machine}@${mach}" "${smpflag}@${smp}" "${config}@${defconfig}"; then
	echo "Skipping ${build} ... "
	return 0
    fi

    echo -n "Building ${build} ... "

    if ! dosetup -c "${defconfig}:${smp}" -f "${smp}" "${rootfs}" "${defconfig}"; then
	return 1
    fi

    echo -n "running ..."

    [[ ${dodebug} -ne 0 ]] && set -x

    # Explicitly select TI UltraSparc IIi. Non-TI CPUs (including the default
    # CPU for sun4v, Sun-UltraSparc-T1) result in a qemu crash or are stuck
    # in an endless loop at poweroff/reboot.
    ${QEMU} -M ${mach} -cpu "TI UltraSparc IIi" \
	-m 512 \
	-drive file=${rootfs%.gz},if=ide,format=raw \
	-kernel arch/sparc/boot/image -no-reboot \
	-append "root=/dev/sda console=ttyS0" \
	-nographic -monitor none > ${logfile} 2>&1 &
    pid=$!

    [[ ${dodebug} -ne 0 ]] && set +x

    dowait ${pid} ${logfile} automatic waitlist[@]
    return $?
}

echo "Build reference: $(git describe)"
echo

runkernel sparc64_defconfig sun4u smp
retcode=$?
runkernel sparc64_defconfig sun4v smp
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4u nosmp
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4v nosmp
retcode=$((retcode + $?))

exit ${retcode}
