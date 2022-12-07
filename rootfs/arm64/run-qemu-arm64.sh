#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. "${dir}/../scripts/common.sh"

parse_args "$@"
shift $((OPTIND - 1))

machine=$1
option=$2
config=$3

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-aarch64}
PREFIX=aarch64-linux-
ARCH=arm64
PATH_ARM64="/opt/kernel/${DEFAULT_CC}/aarch64-linux/bin"

PATH=${PATH}:${PATH_ARM64}

skip_49="raspi3b:defconfig:smp:net,usb:mem1G:initrd \
	raspi3b:defconfig:smp4:net,usb:mem1G:sd:rootfs \
	xlnx-versal-virt:defconfig:smp4:net,default:mem512:sd0:rootfs \
	xlnx-zcu102:defconfig:smp:mem2G:sd:rootfs \
	xlnx-zcu102:defconfig:nosmp:mem2G:sd:rootfs"

patch_defconfig()
{
    local defconfig=$1

    # Starting with v5.6, we need to have DMA_BCM2835 built into the
    # kernel because MMC code using may otherwise fail with -EPROBE_DEFER.
    # Otherwise we can no longer boot raspi3b from mmc cards.
    # See upstream commit 9e17c1cd28cd ("mmc: bcm2835: Use dma_request_chan()
    # instead dma_request_slave_channel()") for background.
    enable_config_cond "${defconfig}" CONFIG_DMA_BCM2835

    # Starting with v5.14, CONFIG_USB_XHCI_PCI_RENESAS=m is enabled.
    # This results in CONFIG_USB_XHCI_PCI=m, which in turn causes some
    # test failures. Set CONFIG_USB_XHCI_PCI_RENESAS=y if enabled to
    # work around the problem.
    enable_config_cond "${defconfig}" CONFIG_USB_XHCI_PCI_RENESAS
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
    "raspi3b")
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

# Failing network tests: i82551, usb-net

runkernel virt defconfig smp:net,e1000:mem512 rootfs.cpio.gz
retcode=$?
runkernel virt defconfig smp2:net,e1000e:efi:mem512:usb-xhci rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig smp2:net,i82801:mem512:usb-ehci rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig smp2:net,i82550:mem512:usb-ohci rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig smp4:net,ne2k_pci:mem512:usb-uas-xhci rootfs.btrfs.gz
retcode=$((retcode + $?))
runkernel virt defconfig smp6:net,pcnet:mem512:virtio rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig smp8:net,rtl8139:mem512:virtio-pci rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig smp:net,tulip:efi:mem512:virtio-blk rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig smp2:net,virtio-net:mem512:nvme rootfs.btrfs.gz
retcode=$((retcode + $?))
runkernel virt defconfig smp4:net,e1000:mem512:sdhci:mmc rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig "smp6:net,i82557a:mem512:scsi[DC395]" rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig "smp8:net,i82557b:efi:mem512:scsi[AM53C974]" rootfs.btrfs.gz
retcode=$((retcode + $?))
runkernel virt defconfig "smp2:net,i82558b:mem512:scsi[MEGASAS]" rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig "smp4:net,i82559er:mem512:scsi[MEGASAS2]" rootfs.btrfs.gz
retcode=$((retcode + $?))
runkernel virt defconfig "smp6:net,e1000-82544gc:mem512:scsi[53C810]" rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig "smp8:net,e1000-82545em:mem512:scsi[53C895A]" rootfs.btrfs.gz
retcode=$((retcode + $?))
runkernel virt defconfig "smp:net,pcnet:mem512:scsi[FUSION]" rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig "smp2:net,usb-ohci:mem512:scsi[virtio]" rootfs.ext2.gz
retcode=$((retcode + $?))

runkernel xlnx-versal-virt defconfig smp:net,default:mem512 rootfs.cpio.gz
retcode=$((retcode + $?))
runkernel xlnx-versal-virt defconfig "smp4:net,default:mem512:virtio-blk" rootfs.ext2.gz
retcode=$((retcode + $?))
if [[ ${runall} -ne 0 ]]; then
    # unreliable; the drive sometimes instantiates as mmcblk1 instead of
    # mmcblk0, causing spurious failures.
    runkernel xlnx-versal-virt defconfig "smp4:net,default:mem512:sd0" rootfs.ext2.gz
    retcode=$((retcode + $?))
fi

runkernel "xlnx-zcu102" defconfig smp:mem2G rootfs.cpio.gz xilinx/zynqmp-ep108.dtb
retcode=$((retcode + $?))
runkernel "xlnx-zcu102" defconfig smp:mem2G:sd rootfs.ext2.gz xilinx/zynqmp-ep108.dtb
retcode=$((retcode + $?))
runkernel "xlnx-zcu102" defconfig smp:mem2G:sata rootfs.ext2.gz xilinx/zynqmp-ep108.dtb
retcode=$((retcode + $?))

if [[ ${runall} -ne 0 ]]; then
    # Since Linux v5.6, the entire clock tree for zynqmp depends on firmware
    # support (which is not available in qemu). See Linux kernel upstream
    # commit 9c8a47b484ed ("arm64: dts: xilinx: Add the clock nodes for
    # zynqmp") for details. Without clocks, loading various io drivers
    # including the serial port driver stalls, and it becomes all but
    # impossible to use the emulation on any kernel later than v5.5.
    runkernel xlnx-zcu102 defconfig smp:mem2G rootfs.cpio.gz xilinx/zynqmp-zcu102-rev1.0.dtb
    retcode=$((retcode + $?))
    runkernel xlnx-zcu102 defconfig smp:mem2G:sd1 rootfs.ext2.gz xilinx/zynqmp-zcu102-rev1.0.dtb
    retcode=$((retcode + $?))
    runkernel xlnx-zcu102 defconfig smp:mem2G:sata rootfs.btrfs.gz xilinx/zynqmp-zcu102-rev1.0.dtb
    retcode=$((retcode + $?))
fi

runkernel raspi3b defconfig smp:net,usb:mem1G rootfs.cpio.gz broadcom/bcm2837-rpi-3-b.dtb
retcode=$((retcode + $?))
runkernel raspi3b defconfig smp4:net,usb:mem1G:sd rootfs.ext2.gz broadcom/bcm2837-rpi-3-b.dtb
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
