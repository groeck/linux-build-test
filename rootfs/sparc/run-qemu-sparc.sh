#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

machine=$1
smpflag=$2

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-sparc}
PREFIX=sparc64-linux-
ARCH=sparc32
rootfs=hda.sqf

rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
PATH_SPARC=/opt/kernel/gcc-6.4.0-nolibc/sparc64-linux/bin

PATH=${PATH_SPARC}:${PATH}

patch_defconfig()
{
    local defconfig=$1
    local smp=$2

    # Enable SQUASHFS and DEVTMPFS, and set SMP as needed.

    sed -i -e '/CONFIG_SQUASHFS/d' ${defconfig}
    sed -i -e '/CONFIG_SMP/d' ${defconfig}
    sed -i -e '/CONFIG_DEVTMPFS/d' ${defconfig}

    echo "CONFIG_SQUASHFS=y" >> ${defconfig}
    echo "CONFIG_DEVTMPFS=y" >> ${defconfig}

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
    local noapcflag=$4
    local pid
    local logfile="$(__mktemp)"
    local waitlist=("Restarting system" "Boot successful" "Rebooting")
    local apc=""
    local build="${ARCH}:${mach}:${smp}:${defconfig}"

    if ! match_params "${machine}@${mach}" "${smpflag}@${smp}"; then
	echo "Skipping ${build} ... "
	return 0
    fi

    echo -n "Building ${build} ... "

    if ! dosetup -c "${defconfig}:${smp}" -f "${smp}" "${rootfs}" "${defconfig}"; then
	return 1
    fi

    if [ -n "${noapcflag}" ]
    then
	apc="apc=noidle"
    fi

    echo -n "running ..."

    [[ ${dodebug} -ne 0 ]] && set -x

    ${QEMU} -M ${mach} \
	-kernel arch/sparc/boot/image -no-reboot \
	-snapshot \
	-drive "file=$(rootfsname ${rootfs}),if=scsi,format=raw" \
	-append "root=/dev/sda rw init=/sbin/init.sh panic=1 console=ttyS0 ${apc} doreboot" \
	-nographic > ${logfile} 2>&1 &
    pid=$!

    [[ ${dodebug} -ne 0 ]] && set +x

    dowait ${pid} ${logfile} automatic waitlist[@]
    return $?
}

echo "Build reference: $(git describe)"
echo

runkernel sparc32_defconfig SPARCClassic nosmp
retcode=$?
runkernel sparc32_defconfig SPARCbook nosmp
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig SS-4 nosmp
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig SS-5 nosmp
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig SS-10 nosmp
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig SS-20 nosmp
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig SS-600MP nosmp
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig LX nosmp noapc
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig Voyager nosmp noapc
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig SPARCClassic smp
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig SPARCbook smp
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig SS-4 smp
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig SS-5 smp
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig SS-10 smp
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig SS-20 smp
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig SS-600MP smp
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig LX smp noapc
retcode=$((${retcode} + $?))
runkernel sparc32_defconfig Voyager smp noapc
retcode=$((${retcode} + $?))

exit ${retcode}
