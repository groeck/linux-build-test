#!/bin/bash

runall=0
if [ "$1" = "-a" ]; then
    runall=1
    shift
fi

machine=$1
option=$2
config=$3

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

kernelrelease=$(git describe | cut -f1 -d- | cut -f1,2 -d. | sed -e 's/\.//' | sed -e 's/v//')

QEMU_V212=${QEMU_V212:-${QEMU_V212_BIN}/qemu-system-aarch64}
QEMU=${QEMU:-${QEMU_BIN}/qemu-system-aarch64}
PREFIX=aarch64-linux-
ARCH=arm64
PATH_ARM64=/opt/kernel/aarch64/gcc-7.2.0/bin

PATH=${PATH}:${PATH_ARM64}

# Xilinx boards don't work on v3.x kernels
# Root file systems only work in v4.9+ (virt) and v4.14 (Xilinx)
skip_32="xlnx-zcu102:smp:defconfig:initrd \
	xlnx-zcu102:nosmp:defconfig:initrd \
	xlnx-zcu102:smp:defconfig:rootfs \
	xlnx-zcu102:nosmp:defconfig:rootfs \
	virt:smp:defconfig:rootfs \
	virt:nosmp:defconfig:rootfs"
skip_316="xlnx-zcu102:smp:defconfig:initrd \
	xlnx-zcu102:nosmp:defconfig:initrd \
	xlnx-zcu102:smp:defconfig:rootfs \
	xlnx-zcu102:nosmp:defconfig:rootfs \
	virt:smp:defconfig:rootfs \
	virt:nosmp:defconfig:rootfs"
skip_318="xlnx-zcu102:smp:defconfig:initrd \
	xlnx-zcu102:nosmp:defconfig:initrd \
	xlnx-zcu102:smp:defconfig:rootfs \
	xlnx-zcu102:nosmp:defconfig:rootfs \
	virt:smp:defconfig:rootfs \
	virt:nosmp:defconfig:rootfs"
skip_41="virt:smp:defconfig:rootfs \
	virt:nosmp:defconfig:rootfs \
	xlnx-zcu102:smp:defconfig:rootfs \
	xlnx-zcu102:nosmp:defconfig:rootfs"
skip_44="virt:smp:defconfig:rootfs \
	virt:nosmp:defconfig:rootfs \
	xlnx-zcu102:smp:defconfig:rootfs \
	xlnx-zcu102:nosmp:defconfig:rootfs"
skip_49="xlnx-zcu102:smp:defconfig:rootfs \
	xlnx-zcu102:nosmp:defconfig:rootfs"

patch_defconfig()
{
    local defconfig=$1
    local fixup=$2

    sed -i -e '/CONFIG_SMP/d' ${defconfig}

    if [ "${fixup}" = "nosmp" ]; then
	echo "# CONFIG_SMP is not set" >> ${defconfig}
    else
	echo "CONFIG_SMP=y" >> ${defconfig}
    fi
}

runkernel()
{
    local mach=$1
    local defconfig=$2
    local fixup=$3
    local rootfs=$4
    local dtb=$5
    local ddtb=$(basename -s .dtb ""${dtb})
    local dtbfile="arch/arm64/boot/dts/${dtb}"
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Restarting system" "Boot successful" "Rebooting")
    local build="${mach}:${fixup}:${defconfig}"
    local tmp="skip_${kernelrelease}"
    local skip=(${!tmp})

    if [[ "${rootfs}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":rootfs"
    fi

    local pbuild="${ARCH}:${build}"
    if [ -n "${ddtb}" ]; then
	pbuild+=":${ddtb}"
    fi

    if [ -n "${machine}" -a "${machine}" != "${mach}" ]; then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    if [ -n "${option}" -a "${option}" != "${fixup}" ]; then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    if [ -n "${config}" -a "${config}" != "${defconfig}" ]
    then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    echo -n "Building ${pbuild} ... "

    for s in ${skip[*]}
    do
	if [ "$s" = "${build}" ]; then
	    echo "skipped"
	    return 0
	fi
    done

    if [ "${cached_config}" != "${defconfig}:${fixup}" ]; then
	dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig} generic ${fixup}
	retcode=$?
	if [ ${retcode} -eq 2 ]; then
	    return 0
	fi
	if [ ${retcode} -ne 0 ]; then
	    return 1
	fi
	cached_config="${defconfig}:${fixup}"
    else
	setup_rootfs ${rootfs}
    fi

    # if we have a dtb file use it
    local dtbcmd=""
    if [ -n "${dtb}" -a -f "${dtbfile}" ]; then
	dtbcmd="-dtb ${dtbfile}"
    fi

    if [[ "${rootfs}" == *cpio ]]; then
	initcli="rdinit=/sbin/init"
	diskcmd="-initrd ${rootfs}"
    elif [[ "${mach}" = "virt" ]]; then
	initcli="root=/dev/sda rw rootwait"
	diskcmd="-usb -device qemu-xhci -device usb-storage,drive=d0 \
		-drive file=${rootfs},format=raw,if=none,id=d0"
    else
	initcli="root=/dev/mmcblk0 rw rootwait"
	diskcmd="-drive file=${rootfs},if=sd,format=raw"
    fi

    echo -n "running ..."

    case ${mach} in
    "virt")
	${QEMU} -machine ${mach} -cpu cortex-a57 \
		-machine type=virt -nographic -smp 1 -m 512 \
		-kernel arch/arm64/boot/Image -no-reboot \
		${diskcmd} \
		-append "console=ttyAMA0 ${initcli}" \
		> ${logfile} 2>&1 &
	pid=$!
	waitflag="manual"
	;;
    "raspi3")
	${QEMU_V212} -M ${mach} \
	    -kernel arch/arm64/boot/Image -no-reboot \
	    --append "${initcli} console=ttyAMA0,115200" \
	    ${diskcmd} \
	    ${dtbcmd} \
	    -nographic -monitor null -serial stdio \
	    > ${logfile} 2>&1 &
	pid=$!
	waitflag="manual"
	;;
    "xlnx-ep108"|"xlnx-zcu102")
	${QEMU} -M ${mach} -kernel arch/arm64/boot/Image -m 2048 \
		-nographic -serial mon:stdio -monitor none -no-reboot \
		${dtbcmd} \
		${diskcmd} \
		--append "${initcli} console=ttyPS0" \
		> ${logfile} 2>&1 &
	pid=$!
	waitflag="automatic"
	;;
    esac

    dowait ${pid} ${logfile} ${waitflag} waitlist[@]
    retcode=$?

    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel virt defconfig smp rootfs.cpio
retcode=$?
runkernel virt defconfig smp rootfs.ext2
retcode=$((${retcode} + $?))
runkernel xlnx-zcu102 defconfig smp rootfs.cpio xilinx/zynqmp-ep108.dtb
retcode=$((${retcode} + $?))
runkernel xlnx-zcu102 defconfig smp rootfs.ext2 xilinx/zynqmp-ep108.dtb
retcode=$((${retcode} + $?))

if [ ${runall} -eq 1 ]; then
    runkernel raspi3 defconfig smp rootfs.cpio broadcom/bcm2837-rpi-3-b.dtb
    retcode=$((${retcode} + $?))
    runkernel raspi3 defconfig smp rootfs.ext2 broadcom/bcm2837-rpi-3-b.dtb
    retcode=$((${retcode} + $?))
fi

runkernel virt defconfig nosmp rootfs.cpio
retcode=$((${retcode} + $?))
runkernel xlnx-zcu102 defconfig nosmp rootfs.cpio xilinx/zynqmp-ep108.dtb
retcode=$((${retcode} + $?))
runkernel xlnx-zcu102 defconfig nosmp rootfs.ext2 xilinx/zynqmp-ep108.dtb
retcode=$((${retcode} + $?))

exit ${retcode}
