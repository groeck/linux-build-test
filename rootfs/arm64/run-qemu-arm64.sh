#!/bin/bash

build=$1
config=$2

PREFIX=aarch64-linux-
ARCH=arm64
rootfs=rootfs.arm64.cpio
PATH_ARM64=/opt/kernel/aarch64/gcc-4.9.1/usr/bin

PATH=${PATH_ARM64}:${PATH}

dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

patch_defconfig()
{
    local defconfig=$1
    local smp=$2

    sed -i -e '/CONFIG_SMP/d' ${defconfig}

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
    local smp=$2
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Restarting system" "Boot successful" "Rebooting")
    local pbuild="${ARCH}:${smp}:${defconfig}"

    if [ -n "${build}" -a "${build}" != "${smp}" ]
    then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    if [ -n "${config}" -a "${config}" != "${defconfig}" ]
    then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    echo -n "Building ${pbuild} ... "

    dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig} generic ${smp}
    if [ $? -ne 0 ]
    then
	return 1
    fi

    echo -n "running ..."

    /opt/buildbot/bin/qemu-system-aarch64 -machine virt -cpu cortex-a57 \
	-machine type=virt -nographic -smp 1 -m 512 \
	-kernel arch/arm64/boot/Image -initrd ${rootfs} -no-reboot \
	-append "console=ttyAMA0" > ${logfile} 2>&1 &

    pid=$!
    dowait ${pid} ${logfile} manual waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel defconfig smp
retcode=$?
runkernel defconfig nosmp
retcode=$((${retcode} + $?))

exit ${retcode}
