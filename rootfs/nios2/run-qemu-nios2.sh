#!/bin/bash

debug=0
if [ "$1" = "-d" ]
then
	debug=1
	shift
fi

machine=$1
config=$2

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-nios2}

PREFIX=nios2-linux-
ARCH=nios2
rootfs=busybox-nios2.cpio
PATH_NIOS2=/opt/kernel/gcc-7.3.0-nolibc/nios2-linux/bin

PATH=${PATH_NIOS2}:${PATH}

patch_defconfig()
{
    local defconfig=$1
    local progdir=$(cd $(dirname $0); pwd)

    sed -i -e '/CONFIG_NIOS2_PASS_CMDLINE/d' ${defconfig}
    sed -i -e '/CONFIG_BLK_DEV_INITRD/d' ${defconfig}
    echo "CONFIG_NIOS2_PASS_CMDLINE=y" >> ${defconfig}
    echo "CONFIG_BLK_DEV_INITRD=y" >> ${defconfig}
}

runkernel()
{
    local mach=$1
    local defconfig=$2
    local dts=$3
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Restarting system" "Boot successful" "Machine restart")
    local pbuild="${ARCH}:${mach}:${defconfig}:${dts}"

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

    dosetup -f fixup "${rootfs}" "${defconfig}"
    retcode=$?
    if [ ${retcode} -ne 0 ]
    then
	if [ ${retcode} -eq 2 ]
	then
	    return 0
	fi
	return 1
    fi

    dts="arch/nios2/boot/dts/${dts}"
    dtb=$(echo ${dts} | sed -e 's/\.dts/\.dtb/')
    dtc -I dts -O dtb ${dts} -o ${dtb} >/dev/null 2>&1

    echo -n "running ..."

    ${QEMU} -M ${mach} \
	-kernel vmlinux -no-reboot \
	-dtb ${dtb} \
	--append "rdinit=/sbin/init earlycon console=ttyS0,115200 doreboot" \
	-initrd busybox-nios2.cpio \
	-nographic -monitor none \
	> ${logfile} 2>&1 &

    pid=$!
    dowait ${pid} ${logfile} automatic waitlist[@]
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

runkernel 10m50-ghrd 10m50_defconfig 10m50_devboard.dts
retcode=$?

exit ${retcode}
