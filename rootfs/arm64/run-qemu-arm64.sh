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

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-aarch64}
PREFIX=aarch64-linux-
ARCH=arm64
PATH_ARM64=/opt/kernel/gcc-7.3.0-nolibc/aarch64-linux/bin

PATH=${PATH}:${PATH_ARM64}

# Xilinx boards don't work on v3.x kernels
# Root file systems only work in v4.9+ (virt) and v4.14 (Xilinx).
# Exceptions:
# - virt:defconfig:smp:virtio:rootfs works from v4.4
# - xlnx-zcu102:defconfig:smp:sata:rootfs:xilinx/zynqmp-ep108 works from v4.4
skip_316="raspi3:defconfig:smp:initrd \
	xlnx-zcu102:defconfig:smp:initrd \
	xlnx-zcu102:defconfig:smp:sata:rootfs \
	xlnx-zcu102:defconfig:smp:sd:rootfs \
	xlnx-zcu102:defconfig:nosmp:initrd \
	xlnx-zcu102:defconfig:nosmp:sd:rootfs \
	virt:defconfig:smp:usb:rootfs \
	virt:defconfig:smp:virtio:rootfs \
	virt:defconfig:nosmp:rootfs"
skip_318="raspi3:defconfig:smp:initrd \
	xlnx-zcu102:defconfig:smp:initrd \
	xlnx-zcu102:defconfig:smp:sata:rootfs \
	xlnx-zcu102:defconfig:smp:sd:rootfs \
	xlnx-zcu102:defconfig:nosmp:initrd \
	xlnx-zcu102:defconfig:nosmp:sd:rootfs \
	virt:defconfig:smp:usb:rootfs \
	virt:defconfig:smp:virtio:rootfs \
	virt:defconfig:nosmp:rootfs"
skip_44="raspi3:defconfig:smp:initrd \
	xlnx-zcu102:defconfig:smp:sd:rootfs \
	xlnx-zcu102:defconfig:nosmp:sd:rootfs \
	virt:defconfig:smp:usb:rootfs \
	virt:defconfig:nosmp:rootfs"
skip_49="raspi3:defconfig:smp:initrd \
	xlnx-zcu102:defconfig:smp:sd:rootfs \
	xlnx-zcu102:defconfig:nosmp:sd:rootfs"

patch_defconfig()
{
    local defconfig=$1
    local fixups=${2//:/ }
    local fixup

    for fixup in ${fixups}; do
	if [ "${fixup}" = "nosmp" ]; then
	    echo "CONFIG_SMP=n" >> ${defconfig}
	fi
	if [ "${fixup}" = "smp" ]; then
	    echo "CONFIG_SMP=y" >> ${defconfig}
	fi
    done
}

runkernel()
{
    local mach=$1
    local defconfig=$2
    local fixup=$3
    local rootfs=$4
    local dtb=$5
    local pid
    local retcode
    local logfile=$(mktemp)
    local waitlist=("Restarting system" "Boot successful" "Rebooting")
    local build="${mach}:${defconfig}:${fixup}"

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	build+=":initrd"
	initcli="rdinit=/sbin/init"
	diskcmd="-initrd ${rootfs%.gz}"
    else
	build+=":rootfs"
	if [[ "${fixup}" = *usb* ]]; then
	    initcli="root=/dev/sda rw rootwait"
	    diskcmd="-usb -device qemu-xhci -device usb-storage,drive=d0"
	    diskcmd+=" -drive file=${rootfs%.gz},if=none,id=d0,format=raw"
	elif [[ "${fixup}" == *virtio* ]]; then
	    initcli="root=/dev/vda rw"
	    diskcmd="-device virtio-blk-pci,drive=d0"
	    diskcmd+=" -drive file=${rootfs%.gz},if=none,id=d0,format=raw"
	elif [[ "${fixup}" == *sata* ]]; then
	    initcli="root=/dev/sda rw"
	    diskcmd="-device ide-hd,drive=d0"
	    diskcmd+=" -drive file=${rootfs%.gz},id=d0,format=raw"
	else
	    initcli="root=/dev/mmcblk0 rw rootwait"
	    diskcmd="-drive file=${rootfs%.gz},if=sd,format=raw"
        fi
    fi

    local pbuild="${ARCH}:${build}${dtb:+:${dtb%.dtb}}"

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

    if ! checkskip "${build}"; then
	return 0
    fi

    if [[ "${cached_config}" != "${defconfig}:${fixup%:*}" ]]; then
	if ! dosetup -f "${fixup}" "${rootfs}" "${defconfig}"; then
	    return 1
	fi
	cached_config="${defconfig}:${fixup%:*}"
    else
	setup_rootfs "${rootfs}"
    fi

    if [[ "${rootfs}" == *.gz ]]; then
	gunzip -f "${rootfs}"
	rootfs="${rootfs%.gz}"
    fi

    echo -n "running ..."

    case ${mach} in
    "virt")
	${QEMU} -M ${mach} -cpu cortex-a57 \
		-nographic -smp 1 -m 512 \
		-monitor none \
		-kernel arch/arm64/boot/Image -no-reboot \
		${diskcmd} \
		-append "console=ttyAMA0 ${initcli}" \
		> ${logfile} 2>&1 &
	pid=$!
	waitflag="manual"
	;;
    "raspi3")
	${QEMU} -M ${mach} -m 1024 \
	    -kernel arch/arm64/boot/Image -no-reboot \
	    --append "${initcli} console=ttyS1,115200" \
	    ${diskcmd} \
	    ${dtb:+-dtb arch/arm64/boot/dts/${dtb}} \
	    -nographic -monitor null -serial null -serial stdio \
	    > ${logfile} 2>&1 &
	pid=$!
	waitflag="manual"
	;;
    "xlnx-ep108"|"xlnx-zcu102")
	${QEMU} -M ${mach} -kernel arch/arm64/boot/Image -m 2048 \
		-nographic -serial mon:stdio -monitor none -no-reboot \
		${dtb:+-dtb arch/arm64/boot/dts/${dtb}} \
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

runkernel virt defconfig smp rootfs.cpio.gz
retcode=$?
runkernel virt defconfig smp:usb rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig smp:virtio rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig smp rootfs.cpio.gz xilinx/zynqmp-ep108.dtb
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig smp:sd rootfs.ext2.gz xilinx/zynqmp-ep108.dtb
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig smp:sata rootfs.ext2.gz xilinx/zynqmp-ep108.dtb
retcode=$((retcode + $?))

runkernel raspi3 defconfig smp rootfs.cpio.gz broadcom/bcm2837-rpi-3-b.dtb
retcode=$((retcode + $?))

if [ ${runall} -eq 1 ]; then
    # Crashes in mmc access
    # sdhost-bcm2835 3f202000.mmc: timeout waiting for hardware interrupt.
    # possibly due to missing clock subsystem implementation or due to
    # bad clock frequencies.
    runkernel raspi3 defconfig smp:sd rootfs.ext2.gz broadcom/bcm2837-rpi-3-b.dtb
    retcode=$((retcode + $?))
fi

runkernel virt defconfig nosmp rootfs.cpio.gz
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig nosmp rootfs.cpio.gz xilinx/zynqmp-ep108.dtb
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig nosmp:sd rootfs.ext2.gz xilinx/zynqmp-ep108.dtb
retcode=$((retcode + $?))

exit ${retcode}
