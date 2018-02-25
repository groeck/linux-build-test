#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

QEMU=${QEMU:-${QEMU_MASTER_BIN}/qemu-system-hppa}

PREFIX=hppa-linux-
ARCH=parisc
rootfs=rootfs.squashfs

rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
PATH_PARISC=/opt/kernel/hppa/gcc-7.3.0/bin
PATH=${PATH}:${PATH_PARISC}

patch_defconfig()
{
    local defconfig=$1
    # enable squashfs
    sed -i -e '/CONFIG_SQUASHFS/d' ${defconfig}
    echo "CONFIG_SQUASHFS=y" >>${defconfig}
}

runkernel()
{
    local defconfig=$1
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("reboot: Restarting system" "Boot successful" "Requesting system reboot")

    echo -n "Building ${ARCH}:${defconfig} ... "

    dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig} "" fixup
    if [ $? -ne 0 ]
    then
	return 1
    fi

    echo -n "running ..."

    ${QEMU} -kernel vmlinux -no-reboot \
	-drive file=${rootfs},format=raw,if=scsi \
	-append "root=/dev/sda console=ttyS0,115200" \
	-nographic -monitor null > ${logfile} 2>&1 &

    pid=$!
    dowait ${pid} ${logfile} automatic waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel defconfig
retcode=$?

exit ${retcode}
