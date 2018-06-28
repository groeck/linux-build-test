#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-microblazeel}
PREFIX=microblazeel-linux-
ARCH=microblaze
PATH_MICROBLAZE=/opt/kernel/microblazeel/gcc-4.9.1/usr/bin

PATH=${PATH_MICROBLAZE}:${PATH}

runkernel()
{
    local defconfig=$1
    local mach=$2
    local rootfs=$3
    local pid
    local retcode
    local waitlist=("Machine restart" "Boot successful" "Rebooting")
    local logfile=/tmp/runkernel-$$.log

    echo -n "Building ${ARCH}:${mach}:${defconfig} ... "

    dosetup -d "${rootfs}" "${defconfig}"
    if [ $? -ne 0 ]; then
	return 1
    fi

    echo -n "running ..."

    case "${mach}" in
    "petalogix-s3adsp1800")
	${QEMU} -M petalogix-s3adsp1800 \
		-kernel arch/microblaze/boot/linux.bin -no-reboot \
		-initrd ${rootfs} \
		-append "rdinit=/sbin/init console=ttyUL0,115200" \
		-monitor none -nographic \
		> ${logfile} 2>&1 &
	pid=$!
	;;
    "petalogix-ml605")
	${QEMU} -M petalogix-ml605 -m 256 \
		-kernel arch/microblaze/boot/linux.bin -no-reboot \
		-initrd ${rootfs} \
		-append "rdinit=/sbin/init console=ttyS0,115200" \
		-monitor none -serial stdio -nographic \
		> ${logfile} 2>&1 &
	pid=$!
	;;
    esac
    dowait ${pid} ${logfile} manual waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

retcode=0
runkernel qemu_microblazeel_defconfig petalogix-s3adsp1800 rootfs.cpio
retcode=$((retcode + $?))
runkernel qemu_microblazeel_ml605_defconfig petalogix-ml605 rootfs.cpio
retcode=$((retcode + $?))

exit $?
