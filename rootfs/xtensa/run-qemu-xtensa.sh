#!/bin/bash

debug=0
if [ "$1" = "-d" ]
then
	debug=1
	shift
fi

machine=$1
config=$2

PREFIX=xtensa-linux-
ARCH=xtensa
rootfs=busybox-xtensa.cpio
PATH_XTENSA=/opt/kernel/xtensa/gcc-4.9.2-dc233c/usr/bin
PATH_XTENSA_TOOLS=/opt/buildbot/bin/xtensa

PATH=${PATH_XTENSA}:${PATH_XTENSA_TOOLS}:${PATH}

dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

cached_defconfig=""

skip_314="xtensa:generic_kc705_defconfig"

patch_defconfig()
{
    local defconfig=$1
    local fixup=$2
    local progdir=$(cd $(dirname $0); pwd)

    # No built-in initrd

    sed -i -e '/CONFIG_INITRAMFS_SOURCE/d' ${defconfig}
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
    local pbuild="${ARCH}:${cpu}:${mach}:${defconfig}"

    if [ -n "${machine}" -a "${machine}" != "${mach}" ]
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

    if [ "${cached_defconfig}" != "${defconfig}:${cpu}" ]
    then
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
	cached_defconfig="${defconfig}:${cpu}"
    fi

    if [ -n "${dts}" -a -e "arch/xtensa/boot/dts/${dts}" ]
    then
	dts="arch/xtensa/boot/dts/${dts}"
	dtb=$(echo ${dts} | sed -e 's/\.dts/\.dtb/')
	dtbcmd="-dtb ${dtb}"
	dtc -I dts -O dtb ${dts} -o ${dtb} >/dev/null 2>&1
    fi

    echo -n "running ..."

    /opt/buildbot/bin/qemu-system-xtensa -cpu ${cpu} -M ${mach} \
	-kernel arch/xtensa/boot/uImage -no-reboot \
	${dtbcmd} \
	--append "rdinit=/sbin/init earlycon=uart8250,mmio32,0xfd050020,115200n8 console=ttyS0,115200n8" \
	-initrd busybox-xtensa.cpio \
	-m ${mem} -nographic -monitor null -serial stdio \
	> ${logfile} 2>&1 &

    pid=$!
    dowait ${pid} ${logfile} manual waitlist[@]
    retcode=$?
    if [ ${debug} -ne 0 ]
    then
	cat ${logfile}
    fi
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel qemu_xtensa_defconfig "" dc232b lx60 128M
retcode=$?
runkernel qemu_xtensa_defconfig "" dc232b kc705 1G
retcode=$((${retcode} + $?))
runkernel generic_kc705_defconfig ml605.dts dc233c ml605 128M
retcode=$((${retcode} + $?))
runkernel generic_kc705_defconfig kc705.dts dc233c kc705 1G
retcode=$((${retcode} + $?))

exit ${retcode}
