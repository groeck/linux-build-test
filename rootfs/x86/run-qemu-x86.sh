#!/bin/bash

_cpu=$1
_mach=$2
_defconfig=$3

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-i386}
ARCH=x86

# Older releases don't like gcc 6+
rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
case ${rel} in
v3.2|v3.10|v3.16|v3.18)
	PATH_X86=/opt/poky/1.3/sysroots/x86_64-pokysdk-linux/usr/bin/x86_64-poky-linux
	PREFIX="x86_64-poky-linux-"
	;;
*)
	PATH_X86=/opt/kernel/x86_64/gcc-6.3.0/usr/bin/
	PREFIX="x86_64-linux-"
	;;
esac

PATH=${PATH_X86}:${PATH}

cached_defconfig=""

runkernel()
{
    local defconfig=$1
    local cpu=$2
    local mach=$3
    local drive
    local pid
    local retcode
    local rootfs=core-image-minimal-qemux86.ext3
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("machine restart" "Restarting" "Boot successful" "Rebooting")
    local build="${ARCH}:${cpu}:${mach}:${defconfig}"

    if [ -n "${_cpu}" -a "${_cpu}" != "${cpu}" ]
        then
	echo "Skipping ${build} ... "
	return 0
    fi

    if [ -n "${_mach}" -a "${_mach}" != "${mach}" ]
    then
	echo "Skipping ${build} ... "
	return 0
    fi

    if [ -n "${_defconfig}" -a "${_defconfig}" != "${defconfig}" ]
    then
	echo "Skipping ${build} ... "
	return 0
    fi

    echo -n "Building ${build} ... "

    if [ "${cached_defconfig}" != "${defconfig}" ]
    then
	dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig}
	if [ $? -ne 0 ]
	then
	    return 1
	fi
	cached_defconfig=${defconfig}
    fi

    echo -n "running ..."

    case "${mach}" in
    pc)
	drive=hda
	usb="-usb -usbdevice wacom-tablet"
	;;
    q35)
	drive=sda
	usb="-usb -usbdevice wacom-tablet"
	;;
    isapc)
	drive=hda
	usb=""
	;;
    *)
        echo "failed (unsupported machine type ${mach})"
	return 1
	;;
    esac

    ${QEMU} -kernel arch/x86/boot/bzImage \
	-M ${mach} -cpu ${cpu} ${usb} -no-reboot -m 256 \
	-drive file=${rootfs},format=raw,if=ide \
	--append "root=/dev/${drive} rw mem=256M vga=0 uvesafb.mode_option=640x480-32 oprofile.timer=1 console=ttyS0 console=tty doreboot" \
	-nographic > ${logfile} 2>&1 &

    pid=$!
    dowait ${pid} ${logfile} manual waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel qemu_x86_pc_defconfig Broadwell q35
retcode=$((${retcode} + $?))
runkernel qemu_x86_pc_defconfig Skylake-Client q35
retcode=$((${retcode} + $?))
runkernel qemu_x86_pc_defconfig SandyBridge q35
retcode=$((${retcode} + $?))
runkernel qemu_x86_pc_defconfig Haswell pc
retcode=$((${retcode} + $?))
runkernel qemu_x86_pc_defconfig Nehalem q35
retcode=$((${retcode} + $?))
runkernel qemu_x86_pc_defconfig phenom pc
retcode=$((${retcode} + $?))
runkernel qemu_x86_pc_nosmp_defconfig core2duo q35
retcode=$((${retcode} + $?))
runkernel qemu_x86_pc_nosmp_defconfig Conroe isapc
retcode=$((${retcode} + $?))
runkernel qemu_x86_pc_nosmp_defconfig Opteron_G1 pc
retcode=$((${retcode} + $?))
runkernel qemu_x86_pc_nosmp_defconfig n270 isapc
retcode=$((${retcode} + $?))

exit ${retcode}
