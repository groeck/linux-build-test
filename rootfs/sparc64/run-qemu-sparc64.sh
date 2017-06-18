#!/bin/bash

machine=$1
smpflag=$2
config=$3

PREFIX=sparc64-linux-
ARCH=sparc64
rootfs=simple-root-filesystem-sparc.ext3
PATH_SPARC=/opt/kernel/gcc-4.9.0-nolibc/sparc64-linux/bin

QEMU=${QEMU:-/opt/buildbot/qemu-install/v2.9/bin/qemu-system-sparc64}

PATH=${PATH_SPARC}:${PATH}

dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

cached_defconfig=""

patch_defconfig()
{
    local defconfig=$1
    local smp=$2

    # Configure SMP as requested, enable DEVTMPFS, and enable VIRTIO

    sed -i -e '/CONFIG_SMP/d' ${defconfig}
    sed -i -e '/CONFIG_DEVTMPFS/d' ${defconfig}
    sed -i -e '/VIRTIO/d' ${defconfig}
    echo "
CONFIG_DEVTMPFS=y
CONFIG_VIRTIO=y
CONFIG_VIRTIO_PCI=y
CONFIG_VIRTIO_BLK=y
CONFIG_VIRTIO_NET=y
CONFIG_VIRTIO_BALLOON=y
CONFIG_VIRTIO_CONSOLE=y
CONFIG_SCSI_VIRTIO=y
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
    local cpu="$3"
    local smp=$4
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Restarting system" "Boot successful" "Rebooting")
    local build=${ARCH}:${mach}:${smp}:${defconfig}

    if [ -n "${machine}" -a "${machine}" != "${mach}" ]
    then
	echo "Skipping ${build} ... "
	return 0
    fi

    if [ -n "${smpflag}" -a "${smpflag}" != "${smp}" ]
    then
	echo "Skipping ${build} ... "
	return 0
    fi

    if [ -n "${config}" -a "${config}" != "${defconfig}" ]
    then
	echo "Skipping ${build} ... "
	return 0
    fi

    echo -n "Building ${build} ... "

    if [ "${defconfig}_${smp}" != "${cached_defconfig}" ]
    then
	dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig} "" ${smp}
	if [ $? -ne 0 ]
	then
	    return 1
	fi
	cached_defconfig="${defconfig}_${smp}"
    fi

    echo -n "running ..."

    ${QEMU} -M ${mach} -cpu "${cpu}" \
	-m 512 \
	-drive file=${rootfs},if=none,id=hd,format=raw \
	-device virtio-blk-pci,disable-modern=on,drive=hd \
	-device virtio-net-pci,disable-modern=on \
	-kernel arch/sparc/boot/image -no-reboot \
	-append "root=/dev/vda init=/sbin/init.sh console=ttyS0 doreboot" \
	-nographic > ${logfile} 2>&1 &

    pid=$!
    dowait ${pid} ${logfile} manual waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel sparc64_defconfig sun4u "TI UltraSparc IIi" smp
retcode=$?
runkernel sparc64_defconfig sun4v "Fujitsu Sparc64 IV" smp
retcode=$((${retcode} + $?))
runkernel sparc64_defconfig sun4u "TI UltraSparc IIi" nosmp
retcode=$((${retcode} + $?))
runkernel sparc64_defconfig sun4v "Fujitsu Sparc64 IV" nosmp
retcode=$((${retcode} + $?))

exit ${retcode}
