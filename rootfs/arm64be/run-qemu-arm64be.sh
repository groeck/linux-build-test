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

patch_defconfig()
{
    local defconfig=$1

    # Starting with v5.6, we need to have DMA_BCM2835 built into the
    enable_config "${defconfig}" CONFIG_CPU_BIG_ENDIAN

    # File system support
    enable_config "${defconfig}" CONFIG_EXFAT_FS
    enable_config "${defconfig}" CONFIG_HFSPLUS_FS
    enable_config "${defconfig}" CONFIG_HFS_FS
    enable_config "${defconfig}" CONFIG_JFS_FS
    enable_config "${defconfig}" CONFIG_NILFS2_FS
    enable_config "${defconfig}" CONFIG_XFS_FS
    enable_config "${defconfig}" CONFIG_BCACHEFS_FS

    enable_config "${defconfig}" CONFIG_EROFS_FS
    enable_config "${defconfig}" CONFIG_F2FS_FS
    enable_config "${defconfig}" CONFIG_GFS2_FS
    enable_config "${defconfig}" CONFIG_MINIX_FS

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

    if [[ "${rootfs}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":${rootfs##*.}"
    fi

    local pbuild="arm64be:${build}${dtb:+:${dtb%.dtb}}"

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

build_reference "${PREFIX}gcc" "${QEMU}"

# f2fs has known lockdep issues which the maintainers don't seem
# to care about.
if [[ "${runall}" -ne 0 ]]; then
	f2fs="f2fs"
else
	f2fs="ext2"
fi

# kown net test failures:
#	i82551, usb-net= i82557a, i82557b

# file system tests
if [[ ${runall} -ne 0 ]]; then
    # Run all file system tests, even those known to fail
    runkernel virt defconfig smp4:net=e1000:mem512:nvme "rootfs.btrfs"
    retcode=$((retcode + $?))
    runkernel virt defconfig smp4:net=e1000:mem512:nvme "rootfs.erofs"
    retcode=$((retcode + $?))
    runkernel virt defconfig smp4:net=e1000:mem512:nvme "rootfs.f2fs"
    retcode=$((retcode + $?))
    runkernel virt defconfig smp4:net=e1000:mem512:nvme:fstest=exfat "rootfs.ext2"
    retcode=$((retcode + $?))
    runkernel virt defconfig smp4:net=e1000:mem512:nvme:fstest=gfs2 "rootfs.ext2"
    retcode=$((retcode + $?))
    runkernel virt defconfig smp4:net=e1000:mem512:nvme:fstest=hfs "rootfs.ext2"
    retcode=$((retcode + $?))
    runkernel virt defconfig smp4:net=e1000:mem512:nvme:fstest=hfs+ "rootfs.ext2"
    retcode=$((retcode + $?))
    runkernel virt defconfig smp4:net=e1000:mem512:nvme:fstest=jfs "rootfs.ext2"
    retcode=$((retcode + $?))
    runkernel virt defconfig smp4:net=e1000:mem512:nvme:fstest=minix "rootfs.ext2"
    retcode=$((retcode + $?))
    runkernel virt defconfig smp4:net=e1000:mem512:nvme:fstest=nilfs2 "rootfs.ext2"
    retcode=$((retcode + $?))
    runkernel virt defconfig smp4:net=e1000:mem512:nvme:fstest=xfs "rootfs.ext2"
    retcode=$((retcode + $?))
    runkernel virt defconfig smp4:net=e1000:mem512:nvme:fstest=bcachefs "rootfs.ext2"
    retcode=$((retcode + $?))
fi

runkernel virt defconfig smp:net=e1000:mem512 rootfs.cpio
retcode=$?
runkernel virt defconfig smp2:net=e1000e:mem512:usb-xhci rootfs.ext2
retcode=$((retcode + $?))
runkernel virt defconfig smp2:net=i82801:mem512:usb-ehci rootfs.ext2
retcode=$((retcode + $?))
runkernel virt defconfig smp2:net=i82550:mem512:usb-ohci rootfs.ext2
retcode=$((retcode + $?))
runkernel virt defconfig smp4:net=ne2k_pci:mem512:usb-uas-xhci rootfs.btrfs
retcode=$((retcode + $?))
runkernel virt defconfig smp6:net=pcnet:mem512:virtio rootfs.ext2
retcode=$((retcode + $?))
runkernel virt defconfig smp8:net=rtl8139:mem512:virtio-pci rootfs.ext2
retcode=$((retcode + $?))
runkernel virt defconfig smp:net=i82559er:mem512:virtio-blk rootfs.ext2
retcode=$((retcode + $?))
runkernel virt defconfig smp2:net=tulip:mem512:nvme rootfs.btrfs
retcode=$((retcode + $?))
runkernel virt defconfig smp4:net=virtio-net:mem512:sdhci-mmc "rootfs.erofs"
retcode=$((retcode + $?))
runkernel virt defconfig "smp6:net=i82558b:mem512:scsi[DC395]" "rootfs.${f2fs}"
retcode=$((retcode + $?))
runkernel virt defconfig "smp8:net=pcnet:mem512:scsi[AM53C974]" rootfs.btrfs
retcode=$((retcode + $?))
runkernel virt defconfig "smp2:net=i82558a:mem512:scsi[MEGASAS]" rootfs.ext2
retcode=$((retcode + $?))
runkernel virt defconfig "smp4:net=i82559a:mem512:scsi[MEGASAS2]" rootfs.btrfs
retcode=$((retcode + $?))
runkernel virt defconfig "smp6:net=i82559b:mem512:scsi[53C810]" rootfs.ext2
retcode=$((retcode + $?))
runkernel virt defconfig "smp8:net=usb-ohci:mem512:scsi[53C895A]" rootfs.btrfs
retcode=$((retcode + $?))
runkernel virt defconfig "smp:net=i82559er:mem512:scsi[FUSION]" rootfs.ext2
retcode=$((retcode + $?))
runkernel virt defconfig "smp2:net=i82562:mem512:scsi[virtio]" rootfs.ext2
retcode=$((retcode + $?))

runkernel xlnx-versal-virt defconfig "smp4:mem512:virtio-blk" rootfs.ext2
retcode=$((retcode + $?))

runkernel xlnx-zcu102 defconfig smp:mem2G rootfs.cpio xilinx/zynqmp-ep108.dtb
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig smp:mem2G:sd rootfs.ext2 xilinx/zynqmp-ep108.dtb
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig smp:mem2G:sata rootfs.ext2 xilinx/zynqmp-ep108.dtb
retcode=$((retcode + $?))

if [ ${runall} -eq 1 ]; then
    # No longer works with mainline kernel; secondary CPU is now mandatory
    runkernel xlnx-zcu102 defconfig smp:mem2G rootfs.cpio xilinx/zynqmp-zcu102-rev1.0.dtb
    retcode=$((retcode + $?))
    runkernel xlnx-zcu102 defconfig smp:mem2G:sd1 rootfs.ext2 xilinx/zynqmp-zcu102-rev1.0.dtb
    retcode=$((retcode + $?))
    runkernel xlnx-zcu102 defconfig smp:mem2G:sata rootfs.btrfs xilinx/zynqmp-zcu102-rev1.0.dtb
    retcode=$((retcode + $?))
fi

# net=usb works for raspi3b:arm64 but not for raspi3b:arm64be
runkernel raspi3b defconfig smp:mem1G rootfs.cpio broadcom/bcm2837-rpi-3-b.dtb
retcode=$((retcode + $?))
if [ ${runall} -eq 1 ]; then
    # sd emulation code in qemu seems to have endianness problems in big endian
    # mode if DMA is disabled.
    runkernel raspi3b defconfig smp4:mem1G:sd rootfs.ext2 broadcom/bcm2837-rpi-3-b.dtb
    retcode=$((retcode + $?))
fi

runkernel virt defconfig nosmp:mem512 rootfs.cpio
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig nosmp:mem2G rootfs.cpio xilinx/zynqmp-ep108.dtb
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig nosmp:mem2G:sd rootfs.ext2 xilinx/zynqmp-ep108.dtb
retcode=$((retcode + $?))

if [ ${runall} -eq 1 ]; then
    # No longer works with mainline kernel; secondary CPU is now mandatory
    runkernel xlnx-zcu102 defconfig nosmp:mem2G rootfs.cpio xilinx/zynqmp-zcu102-rev1.0.dtb
    retcode=$((retcode + $?))
    runkernel xlnx-zcu102 defconfig nosmp:mem2G:sd1 rootfs.ext2 xilinx/zynqmp-zcu102-rev1.0.dtb
    retcode=$((retcode + $?))
fi

exit ${retcode}
