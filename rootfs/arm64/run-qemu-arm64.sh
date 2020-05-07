#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. "${dir}/../scripts/common.sh"

parse_args "$@"
shift $((OPTIND - 1))

machine=$1
option=$2
config=$3

# 2nd CPU of xlnx-versal-virt fails to come online with qemu v4.2
QEMU=${QEMU:-${QEMU_BIN}/qemu-system-aarch64}
PREFIX=aarch64-linux-
ARCH=arm64
PATH_ARM64=/opt/kernel/gcc-8.3.0-nolibc/aarch64-linux/bin

PATH=${PATH}:${PATH_ARM64}

# Xilinx boards don't work on v3.x kernels
# Root file systems only work in v4.9+ (virt) and v4.14 (Xilinx).
# Exceptions:
# - virt:defconfig:smp:virtio:rootfs works from v4.4
# - xlnx-zcu102:defconfig:smp:sata:rootfs:xilinx/zynqmp-zcu102 works from v4.4
skip_316="virt:defconfig:smp2:mem512:usb-xhci:rootfs \
	virt:defconfig:smp2:mem512:usb-ehci:rootfs \
	virt:defconfig:smp2:mem512:usb-ohci:rootfs \
	virt:defconfig:smp4:mem512:usb-uas-xhci:rootfs \
	virt:defconfig:smp6:mem512:virtio:rootfs \
	virt:defconfig:smp8:mem512:virtio-pci:rootfs \
	virt:defconfig:smp2:mem512:nvme:rootfs \
	virt:defconfig:smp4:mem512:sdhci:mmc:rootfs \
	virt:defconfig:smp6:mem512:scsi[DC395]:rootfs \
	virt:defconfig:smp8:mem512:scsi[AM53C974]:rootfs \
	virt:defconfig:smp2:mem512:scsi[MEGASAS]:rootfs \
	virt:defconfig:smp4:mem512:scsi[MEGASAS2]:rootfs \
	virt:defconfig:smp4:mem512:scsi[virtio]:rootfs \
	virt:defconfig:smp6:mem512:scsi[53C810]:rootfs \
	virt:defconfig:smp8:mem512:scsi[53C895A]:rootfs \
	virt:defconfig:smp:mem512:scsi[FUSION]:rootfs \
	xlnx-versal-virt:defconfig:smp2:mem512:virtio-blk:rootfs"
skip_44="xlnx-zcu102:defconfig:smp:mem2G:sd:rootfs \
	xlnx-zcu102:defconfig:nosmp:mem2G:sd:rootfs"
skip_49="raspi3:defconfig:smp:mem1G:initrd \
	raspi3:defconfig:smp4:mem1G:sd:rootfs \
	xlnx-zcu102:defconfig:smp:mem2G:sd:rootfs \
	xlnx-zcu102:defconfig:nosmp:mem2G:sd:rootfs"

patch_defconfig()
{
    local defconfig=$1

    # Starting with v5.6, we need to have DMA_BCM2835 built into the
    # kernel because MMC code using may otherwise fail with -EPROBE_DEFER.
    # Otherwise we can no longer boot raspi3 from mmc cards.
    # See upstream commit 9e17c1cd28cd ("mmc: bcm2835: Use dma_request_chan()
    # instead dma_request_slave_channel()") for background.
    sed -i -e 's/CONFIG_DMA_BCM2835=m/CONFIG_DMA_BCM2835=y/' ${defconfig}
}

runkernel()
{
    local mach=$1
    local defconfig=$2
    local fixup="$3"
    local rootfs=$4
    local dtb=$5
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
    "virt")
	initcli+=" earlycon=pl011,0x9000000 console=ttyAMA0"
	extra_params+=" -cpu cortex-a57"
	waitflag="manual"
	;;
    "xlnx-versal-virt")
	initcli+=" earlycon=pl011,0xff000000 console=ttyAMA0"
	extra_params+=" -cpu cortex-a57"
	waitflag="manual"
	;;
    "raspi3")
	initcli+=" earlycon=uart8250,mmio32,0x3f215040 console=ttyS1,115200"
	extra_params+=" -serial null"
	waitflag="manual"
	;;
    "xlnx-zcu102")
	initcli+=" earlycon=cdns,mmio,0xFF000000,115200n8 console=ttyPS0"
	waitflag="automatic"
	;;
    esac

    execute ${waitflag} waitlist[@] \
	${QEMU} -M ${mach} \
		-kernel arch/arm64/boot/Image -no-reboot \
		-nographic \
		${extra_params} \
		-serial stdio \
		-monitor none \
		-no-reboot \
		--append "${initcli}" \
		${dtb:+-dtb arch/arm64/boot/dts/${dtb}}
    return $?
}

echo "Build reference: $(git describe)"
echo

runkernel virt defconfig smp:mem512 rootfs.cpio.gz
retcode=$?
runkernel virt defconfig smp2:efi:mem512:usb-xhci rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig smp2:mem512:usb-ehci rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig smp2:mem512:usb-ohci rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig smp4:mem512:usb-uas-xhci rootfs.btrfs.gz
retcode=$((retcode + $?))
runkernel virt defconfig smp6:mem512:virtio rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig smp8:mem512:virtio-pci rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig smp:efi:mem512:virtio-blk rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig smp2:mem512:nvme rootfs.btrfs.gz
retcode=$((retcode + $?))
runkernel virt defconfig smp4:mem512:sdhci:mmc rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig "smp6:mem512:scsi[DC395]" rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig "smp8:efi:mem512:scsi[AM53C974]" rootfs.btrfs.gz
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

# Instantiating virtual devices requires qemu v3.1.0 plus patches, or qemu v4.0.0.
runkernel xlnx-versal-virt defconfig "smp2:mem512:virtio-blk" rootfs.ext2.gz
retcode=$((retcode + $?))

runkernel xlnx-zcu102 defconfig smp:mem2G rootfs.cpio.gz xilinx/zynqmp-ep108.dtb
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig smp:mem2G:sd rootfs.ext2.gz xilinx/zynqmp-ep108.dtb
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig smp:mem2G:sata rootfs.ext2.gz xilinx/zynqmp-ep108.dtb
retcode=$((retcode + $?))

if [[ ${runall} -ne 0 ]]; then
    runkernel xlnx-zcu102 defconfig smp:mem2G rootfs.cpio.gz xilinx/zynqmp-zcu102-rev1.0.dtb
    retcode=$((retcode + $?))
    runkernel xlnx-zcu102 defconfig smp:mem2G:sd1 rootfs.ext2.gz xilinx/zynqmp-zcu102-rev1.0.dtb
    retcode=$((retcode + $?))
    runkernel xlnx-zcu102 defconfig smp:mem2G:sata rootfs.btrfs.gz xilinx/zynqmp-zcu102-rev1.0.dtb
    retcode=$((retcode + $?))
fi

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

if [[ ${runall} -ne 0 ]]; then
    runkernel xlnx-zcu102 defconfig nosmp:mem2G rootfs.cpio.gz xilinx/zynqmp-zcu102-rev1.0.dtb
    retcode=$((retcode + $?))
    runkernel xlnx-zcu102 defconfig nosmp:mem2G:sd1 rootfs.ext2.gz xilinx/zynqmp-zcu102-rev1.0.dtb
    retcode=$((retcode + $?))
fi

exit ${retcode}
