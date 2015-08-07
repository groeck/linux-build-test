#!/bin/bash

# machine specific information
PATH_MIPS=/opt/poky/1.3/sysroots/x86_64-pokysdk-linux/usr/bin/mips32-poky-linux
PATH_X86=/opt/poky/1.4.0-1/sysroots/x86_64-pokysdk-linux/usr/bin
PREFIX=mips-poky-linux-
ARCH=mips

PATH=${PATH_MIPS}:${PATH_X86}:${PATH}
dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

# Called from dosetup() to patch the configuration file.
patch_defconfig()
{
    local defconfig=$1

    sed -i -e '/CONFIG_DEVTMPFS/d' ${defconfig}
    echo "CONFIG_DEVTMPFS=y" >> ${defconfig}
}

runkernel()
{
    local defconfig=$1
    local mach=$2
    local rootfs=$3
    local fixup=$4
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Boot successful" "Rebooting")

    echo -n "Building ${ARCH}:${defconfig} ... "

    dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig} "" ${fixup}
    retcode=$?
    if [ ${retcode} -ne 0 ]
    then
	if [ ${retcode} -eq 2 ]
	then
	    return 0
	fi
	return 1
    fi

    echo -n "running ..."

    if [ "${rootfs}" = "busybox-mips64el.cpio" ]
    then
        /opt/buildbot/bin/qemu-system-mips64el -M ${mach} \
	    -kernel vmlinux -vga cirrus -no-reboot -m 128 \
	    --append "rdinit=/sbin/init mem=128M console=ttyS0 console=tty doreboot" \
	    -nographic > ${logfile} 2>&1 &
    	pid=$!
    else
        /opt/buildbot/bin/qemu-system-mips64el -M ${mach} \
	    -kernel vmlinux -no-reboot -m 128 \
	    --append "root=/dev/hda rw console=ttyS0 doreboot" \
	    -hda ${rootfs} \
	    -nographic -serial stdio -monitor null > ${logfile} 2>&1 &
    	pid=$!
    fi

    dowait ${pid} ${logfile} automatic waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel qemu_mipsel_malta64_defconfig malta busybox-mips64el.cpio
retcode=$?
runkernel qemu_mipsel_malta64_smp_defconfig malta busybox-mips64el.cpio
retcode=$((${retcode} + $?))
runkernel fuloong2e_defconfig fulong2e rootfs.mipsel.ext3 fixup
retcode=$((${retcode} + $?))

exit ${retcode}
