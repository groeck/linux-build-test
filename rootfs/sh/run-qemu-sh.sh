#!/bin/bash

PREFIX=sh4-linux-
ARCH=sh
rootfs=rootfs.ext2
PATH_SH=/opt/kernel/gcc-4.6.3-nolibc/sh4-linux/bin

PATH=${PATH_SH}:${PATH}

dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

patch_defconfig()
{
    local defconfig=$1

    # Drop command line overwrite
    sed -i -e '/CONFIG_CMDLINE/d' ${defconfig}
}

runkernel()
{
    local defconfig=$1
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Power down" "Boot successful" "Poweroff")

    echo -n "Building ${ARCH}:${defconfig} ... "

    dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig} "" fixup
    if [ $? -ne 0 ]
    then
	return 1
    fi

    echo -n "running ..."

    /opt/buildbot/bin/qemu-system-sh4 -M r2d -kernel ./arch/sh/boot/zImage \
	-drive file=${rootfs},format=raw,if=ide \
	-append "root=/dev/sda console=ttySC1,115200 noiotrap doreboot" \
	-serial null -serial stdio -net nic,model=rtl8139 -net user \
	-nographic -monitor null > ${logfile} 2>&1 &

    pid=$!
    dowait ${pid} ${logfile} automatic waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel rts7751r2dplus_defconfig
retcode=$?

exit ${retcode}
