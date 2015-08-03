#!/bin/bash

# machine specific information
# PATH_PPC=/opt/poky/1.4.0-1/sysroots/x86_64-pokysdk-linux/usr/bin/ppc64e5500-poky-linux
PATH_PPC=/opt/poky/1.5.1/sysroots/x86_64-pokysdk-linux/usr/bin/powerpc64-poky-linux
PATH_X86=/opt/poky/1.4.0-1/sysroots/x86_64-pokysdk-linux/usr/bin
PREFIX=powerpc64-poky-linux-
ARCH=powerpc
QEMUCMD=/opt/buildbot/bin/qemu-system-ppc
QEMU_MACH=mac99

PATH=${PATH_PPC}:${PATH_X86}:${PATH}
dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

skip_32="powerpc:qemu_virtex440_defconfig \
	powerpc:mpc85xx_defconfig powerpc:mpc85xx_smp_defconfig"
skip_34="powerpc:mpc85xx_defconfig powerpc:mpc85xx_smp_defconfig"

runkernel()
{
    local defconfig=$1
    local mach=$2
    local rootfs=$3
    local kernel=$4
    local dts=$5
    local dtb
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Restarting" "Boot successful" "Rebooting")

    echo -n "Building ${ARCH}:${defconfig} ... "

    dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig}
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

    if [ "${rootfs}" = "core-image-minimal-qemuppc.ext3" ]
    then
	${QEMUCMD} -kernel ${kernel} -M ${mach} -cpu G4 \
	    -hda ${rootfs} -usb -usbdevice wacom-tablet -no-reboot -m 128 \
	    --append "root=/dev/hda rw mem=128M console=ttyS0 console=tty doreboot" \
	    -nographic > ${logfile} 2>&1 &
    else
	dtbcmd=""
	if [ -n "${dts}" -a -e "${dts}" ]
	then
	    dtb=$(echo ${dts} | sed -e 's/\.dts/\.dtb/')
	    dtbcmd="-dtb ${dtb}"
	    dtc -I dts -O dtb ${dts} -o ${dtb} >/dev/null 2>&1
	fi
	${QEMUCMD} -kernel ${kernel} -M ${mach} -no-reboot -m 256 \
	    --append "rdinit=/sbin/init console=ttyS0 console=tty doreboot" \
	    ${dtbcmd} -monitor none -nographic \
	    -initrd ${rootfs} > ${logfile} 2>&1 &
    fi

    pid=$!

    dowait ${pid} ${logfile} automatic waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

VIRTEX440_DTS=arch/powerpc/boot/dts/virtex440-ml507.dts

runkernel qemu_ppc_book3s_defconfig mac99 core-image-minimal-qemuppc.ext3 vmlinux
retcode=$?
runkernel qemu_ppc_book3s_smp_defconfig mac99 core-image-minimal-qemuppc.ext3 vmlinux
retcode=$((${retcode} + $?))
runkernel qemu_g3beige_defconfig g3beige core-image-minimal-qemuppc.ext3 vmlinux
retcode=$((${retcode} + $?))
runkernel qemu_virtex440_defconfig virtex-ml507 busybox-ppc.cpio vmlinux ${VIRTEX440_DTS}
retcode=$((${retcode} + $?))
runkernel mpc85xx_defconfig mpc8544ds busybox-ppc.cpio arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
runkernel mpc85xx_smp_defconfig mpc8544ds busybox-ppc.cpio arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))

exit ${retcode}
