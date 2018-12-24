#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

machine=$1
option=$2
config=$3

QEMU=${QEMU:-${QEMU_V31_BIN}/qemu-system-aarch64}
PREFIX=aarch64-linux-
ARCH=arm64
PATH_ARM64=/opt/kernel/gcc-7.3.0-nolibc/aarch64-linux/bin

PATH=${PATH}:${PATH_ARM64}

# Xilinx boards don't work on v3.x kernels
# Root file systems only work in v4.9+ (virt) and v4.14 (Xilinx).
# Exceptions:
# - virt:defconfig:smp:virtio:rootfs works from v4.4
# - xlnx-zcu102:defconfig:smp:sata:rootfs:xilinx/zynqmp-zcu102 works from v4.4
skip_316="virt:defconfig:smp2:mem512:usb-xhci:rootfs \
	virt:defconfig:smp4:mem512:usb-uas-xhci:rootfs \
	virt:defconfig:smp6:mem512:virtio:rootfs \
	virt:defconfig:smp8:mem512:virtio-pci:rootfs \
	virt:defconfig:smp2:mem512:nvme:rootfs \
	virt:defconfig:smp4:mem512:mmc:rootfs \
	virt:defconfig:smp6:mem512:scsi[DC395]:rootfs \
	virt:defconfig:smp8:mem512:scsi[AM53C974]:rootfs \
	virt:defconfig:smp2:mem512:scsi[MEGASAS]:rootfs \
	virt:defconfig:smp4:mem512:scsi[MEGASAS2]:rootfs \
	virt:defconfig:smp4:mem512:scsi[virtio]:rootfs \
	virt:defconfig:smp6:mem512:scsi[53C810]:rootfs \
	virt:defconfig:smp8:mem512:scsi[53C895A]:rootfs \
	virt:defconfig:smp:mem512:scsi[FUSION]:rootfs"
skip_318="virt:defconfig:smp2:mem512:usb-xhci:rootfs \
	virt:defconfig:smp4:mem512:usb-uas-xhci:rootfs \
	virt:defconfig:smp6:mem512:virtio:rootfs \
	virt:defconfig:smp8:mem512:virtio-pci:rootfs \
	virt:defconfig:smp2:mem512:nvme:rootfs \
	virt:defconfig:smp4:mem512:mmc:rootfs \
	virt:defconfig:smp6:mem512:scsi[DC395]:rootfs \
	virt:defconfig:smp8:mem512:scsi[AM53C974]:rootfs \
	virt:defconfig:smp2:mem512:scsi[MEGASAS]:rootfs \
	virt:defconfig:smp4:mem512:scsi[MEGASAS2]:rootfs \
	virt:defconfig:smp6:mem512:scsi[53C810]:rootfs \
	virt:defconfig:smp8:mem512:scsi[53C895A]:rootfs \
	virt:defconfig:smp:mem512:scsi[FUSION]:rootfs \
	virt:defconfig:smp:mem512:scsi[virtio]:rootfs"
skip_44="xlnx-zcu102:defconfig:smp2:mem2G:sd:rootfs \
	xlnx-zcu102:defconfig:nosmp:mem2G:sd:rootfs"
skip_49="raspi3:defconfig:smp:mem1G:initrd \
	raspi3:defconfig:smp4:mem1G:sd:rootfs \
	xlnx-zcu102:defconfig:smp2:mem2G:sd:rootfs \
	xlnx-zcu102:defconfig:nosmp:mem2G:sd:rootfs"

patch_defconfig()
{
    : # nothing to do
}

runkernel()
{
    local mach=$1
    local defconfig=$2
    local fixup="$3"
    local rootfs=$4
    local dtb=$5
    local pid
    local retcode
    local logfile=$(__mktemp)
    local waitlist=("Restarting system" "Boot successful" "Rebooting")
    local build="${mach}:${defconfig}:${fixup}"

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":rootfs"
    fi

    local pbuild="${ARCH}:${build}${dtb:+:${dtb%.dtb}}"

    if ! match_params "${machine}@${mach}" "${option}@${fixup}" "${config}@${defconfig}"; then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    if [[ -n "${dtb}" && ! -e "arch/arm64/boot/dts/${dtb/.dtb/.dts}" ]]; then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    echo -n "Building ${pbuild} ... "

    if ! checkskip "${build}"; then
	return 0
    fi

    if ! dosetup -F "${fixup}" -c "${defconfig}:${fixup//smp*/smp}" "${rootfs}" "${defconfig}"; then
	if [[ __dosetup_rc -eq 2 ]]; then
	    return 0
	fi
	return 1
    fi

    echo -n "running ..."

    case ${mach} in
    "virt" | "xlnx-versal-virt" )
	[[ ${dodebug} -ne 0 ]] && set -x
	${QEMU} -M ${mach} -cpu cortex-a57 \
		-nographic \
		-monitor none \
		-kernel arch/arm64/boot/Image -no-reboot \
		${extra_params} \
		-append "console=ttyAMA0 ${initcli}" \
		> ${logfile} 2>&1 &
	pid=$!
	[[ ${dodebug} -ne 0 ]] && set +x
	waitflag="manual"
	;;
    "raspi3")
	[[ ${dodebug} -ne 0 ]] && set -x
	${QEMU} -M ${mach} \
	    -kernel arch/arm64/boot/Image -no-reboot \
	    --append "earlycon=uart8250,mmio32,0x3f215040 ${initcli} console=ttyS1,115200" \
	    ${extra_params} \
	    ${dtb:+-dtb arch/arm64/boot/dts/${dtb}} \
	    -nographic -monitor null -serial null -serial stdio \
	    > ${logfile} 2>&1 &
	pid=$!
	[[ ${dodebug} -ne 0 ]] && set +x
	waitflag="manual"
	;;
    "xlnx-zcu102")
	[[ ${dodebug} -ne 0 ]] && set -x
	${QEMU} -M ${mach} -kernel arch/arm64/boot/Image \
		-nographic -serial stdio -monitor none -no-reboot \
		${dtb:+-dtb arch/arm64/boot/dts/${dtb}} \
		${extra_params} \
		--append "${initcli} console=ttyPS0 earlycon=cdns,mmio,0xFF000000,115200n8" \
		> ${logfile} 2>&1 &
	pid=$!
	[[ ${dodebug} -ne 0 ]] && set +x
	waitflag="automatic"
	;;
    esac

    dowait ${pid} ${logfile} ${waitflag} waitlist[@]
    retcode=$?

    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel virt defconfig smp:mem512 rootfs.cpio.gz
retcode=$?
runkernel virt defconfig smp2:mem512:usb-xhci rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig smp4:mem512:usb-uas-xhci rootfs.btrfs.gz
retcode=$((retcode + $?))
runkernel virt defconfig smp6:mem512:virtio rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig smp8:mem512:virtio-pci rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig smp:mem512:virtio-blk rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig smp2:mem512:nvme rootfs.btrfs.gz
retcode=$((retcode + $?))
runkernel virt defconfig smp4:mem512:mmc rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig "smp6:mem512:scsi[DC395]" rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig "smp8:mem512:scsi[AM53C974]" rootfs.btrfs.gz
retcode=$((retcode + $?))
runkernel virt defconfig "smp2:mem512:scsi[MEGASAS]" rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig "smp4:mem512:scsi[MEGASAS2]" rootfs.btrfs.gz
retcode=$((retcode + $?))
runkernel virt defconfig "smp6:mem512:scsi[53C810]" rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig "smp8:mem512:scsi[53C895A]" rootfs.btrfs.gz
retcode=$((retcode + $?))
runkernel virt defconfig "smp:mem512:scsi[FUSION]" rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig "smp2:mem512:scsi[virtio]" rootfs.ext2.gz
retcode=$((retcode + $?))

# No idea how to instantiate virtual devices
# runkernel xlnx-versal-virt defconfig "smp2:mem512:virtio-blk" rootfs.ext2.gz
# retcode=$((retcode + $?))

runkernel xlnx-zcu102 defconfig smp:mem2G rootfs.cpio.gz xilinx/zynqmp-ep108.dtb
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig smp2:mem2G:sd rootfs.ext2.gz xilinx/zynqmp-ep108.dtb
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig smp4:mem2G:sata rootfs.ext2.gz xilinx/zynqmp-ep108.dtb
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig smp:mem2G rootfs.cpio.gz xilinx/zynqmp-zcu102-rev1.0.dtb
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig smp2:mem2G:sd1 rootfs.ext2.gz xilinx/zynqmp-zcu102-rev1.0.dtb
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig smp4:mem2G:sata rootfs.btrfs.gz xilinx/zynqmp-zcu102-rev1.0.dtb
retcode=$((retcode + $?))

runkernel raspi3 defconfig smp:mem1G rootfs.cpio.gz broadcom/bcm2837-rpi-3-b.dtb
retcode=$((retcode + $?))
runkernel raspi3 defconfig smp4:mem1G:sd rootfs.ext2.gz broadcom/bcm2837-rpi-3-b.dtb
retcode=$((retcode + $?))

runkernel virt defconfig nosmp:mem512 rootfs.cpio.gz
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig nosmp:mem2G rootfs.cpio.gz xilinx/zynqmp-ep108.dtb
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig nosmp:mem2G:sd rootfs.ext2.gz xilinx/zynqmp-ep108.dtb
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig nosmp:mem2G rootfs.cpio.gz xilinx/zynqmp-zcu102-rev1.0.dtb
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig nosmp:mem2G:sd1 rootfs.ext2.gz xilinx/zynqmp-zcu102-rev1.0.dtb
retcode=$((retcode + $?))

exit ${retcode}
