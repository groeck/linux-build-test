#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

config=$1
variant=$2

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-mips64}

rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
PATH_MIPS=/opt/kernel/gcc-4.9.0-nolibc/mips-linux/bin
PREFIX=mips-linux-
cpu="-cpu 5KEc"

# machine specific information
rootfs=core-image-minimal-qemumips64.ext3
ARCH=mips
KERNEL_IMAGE=vmlinux
QEMU_MACH=malta

PATH=${PATH_MIPS}:${PATH}

patch_defconfig()
{
    local defconfig=$1
    local fixups=${2//:/ }
    local fixup

    # Enable DEVTMPFS

    sed -i -e '/CONFIG_DEVTMPFS/d' ${defconfig}
    echo "CONFIG_DEVTMPFS=y" >> ${defconfig}
    echo "CONFIG_DEVTMPFS_MOUNT=y" >> ${defconfig}

    # 64 bit build
    echo "CONFIG_32BIT=n" >> ${defconfig}
    echo "CONFIG_CPU_MIPS32_R1=n" >> ${defconfig}
    echo "CONFIG_CPU_MIPS64_R1=y" >> ${defconfig}
    echo "CONFIG_64BIT=y" >> ${defconfig}

    # Build a big endian image
    echo "CONFIG_CPU_LITTLE_ENDIAN=n" >> ${defconfig}
    echo "CONFIG_CPU_BIG_ENDIAN=y" >> ${defconfig}

    for fixup in ${fixups}; do
	if [[ "${fixup}" == "smp" ]]; then
	    echo "CONFIG_MIPS_MT_SMP=y" >> ${defconfig}
	    echo "CONFIG_SCHED_SMT=y" >> ${defconfig}
	    echo "CONFIG_NR_CPUS=8" >> ${defconfig}
	elif [[ "${fixup}" == "nosmp" ]]; then
	    echo "CONFIG_MIPS_MT_SMP=n" >> ${defconfig}
	    echo "CONFIG_SCHED_SMT=n" >> ${defconfig}
	fi
    done
}

runkernel()
{
    local defconfig=$1
    local fixup=$2
    local pid
    local retcode
    local initcli="root=/dev/sda rw"
    local diskcmd="-drive file=${rootfs},format=raw,if=ide"
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Boot successful" "Rebooting")
    local build="mips64:${defconfig}:${fixup}"

    if [ -n "${config}" -a "${config}" != "${defconfig}" ]
    then
	echo "Skipping ${build} ... "
	return 0
    fi

    if [ -n "${variant}" -a "${variant}" != "${fixup}" ]
    then
	echo "Skipping ${build} ... "
	return 0
    fi

    echo -n "Building ${build} ... "

    dosetup -f "${fixup}" "${rootfs}" "${defconfig}"
    if [ $? -ne 0 ]
    then
	return 1
    fi

    echo -n "running ..."

    if ! common_diskcmd "${fixup##*:}" "${rootfs}"; then
	return 1
    fi

    [[ ${dodebug} -ne 0 ]] && set -x

    ${QEMU} -kernel ${KERNEL_IMAGE} -M ${QEMU_MACH} \
	${cpu} \
	${diskcmd} \
	-vga cirrus -no-reboot -m 128 \
	--append "${initcli} mem=128M console=ttyS0 console=tty ${extracli} doreboot" \
	-nographic > ${logfile} 2>&1 &
    pid=$!

    [[ ${dodebug} -ne 0 ]] && set +x

    dowait ${pid} ${logfile} automatic waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel malta_defconfig nosmp:ata
retcode=$?
runkernel malta_defconfig smp:ata
retcode=$((retcode + $?))

exit ${retcode}
