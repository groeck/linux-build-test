#!/bin/bash

PREFIX=xtensa-linux-
ARCH=xtensa
rootfs=busybox-xtensa.cpio
PATH_XTENSA=/opt/kernel/xtensa/gcc-4.9.2-dc233c/usr/bin

PATH=${PATH_XTENSA}:${PATH}

dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

cached_defconfig=""

skip_314="xtensa:generic_kc705_defconfig"

patch_defconfig()
{
    local defconfig=$1
    local fixup=$2
    local progdir=$(cd $(dirname $0); pwd)

    # Always provide initrd

    sed -i -e '/CONFIG_INITRAMFS_SOURCE/d' ${defconfig}
    echo 'CONFIG_INITRAMFS_SOURCE="busybox-xtensa.cpio"' >> ${defconfig}

    # Specify built-in devicetree file as required for configuration
    # Copy devicetree file here since 'dosetup' will otherwise remove it
    # during its clean-up phase.

    if [ "${fixup}" != "initrd" -a -e "${progdir}/${fixup}" ]
    then
        cp ${progdir}/${fixup} arch/${ARCH}/boot/dts/qemu.dts
        sed -i -e '/CONFIG_BUILTIN_DTB/d' ${defconfig}
	echo 'CONFIG_BUILTIN_DTB="qemu"' >> ${defconfig}
    fi
}

runkernel()
{
    local defconfig=$1
    local dts=$2
    local cpu=$3
    local mach=$4
    local mem=$5
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Restarting system" "Boot successful" "Rebooting")
    local fixup="initrd"

    echo -n "Building ${ARCH}:${cpu}:${mach}:${defconfig} ... "

    if [ -n "${dts}" ]
    then
	fixup="${dts}"
    fi

    if [ "${cached_defconfig}" != "${defconfig}:${cpu}:${dts}" ]
    then
        dosetup ${ARCH} ${PREFIX} "bootdir-y=boot-elf" ${rootfs} ${defconfig} "" ${fixup}
	retcode=$?
        if [ ${retcode} -ne 0 ]
        then
	    if [ ${retcode} -eq 2 ]
	    then
	        return 0
	    fi
	    return 1
        fi
	cached_defconfig="${defconfig}:${cpu}:${dts}"
    fi

    echo -n "running ..."

    /opt/buildbot/bin/qemu-system-xtensa -cpu ${cpu} -M ${mach} \
	-kernel arch/xtensa/boot/Image.elf -no-reboot \
	-m ${mem} -nographic -monitor null -serial stdio \
	> ${logfile} 2>&1 &

    pid=$!
    dowait ${pid} ${logfile} manual waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel qemu_xtensa_defconfig "" dc232b lx60 128M
retcode=$?
runkernel qemu_xtensa_defconfig "" dc232b kc705 1G
retcode=$((${retcode} + $?))
runkernel generic_kc705_defconfig qemu_kc705.dts dc233c kc705 1G
retcode=$((${retcode} + $?))

exit ${retcode}
