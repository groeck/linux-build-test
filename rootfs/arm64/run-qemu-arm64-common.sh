#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. "${dir}/../scripts/common.sh"

parse_args "$@"
shift $((OPTIND - 1))

machine=$1
option=$2
config=$3

QEMU_V100=${QEMU:-${QEMU_V100_BIN}/qemu-system-aarch64}
QEMU=${QEMU:-${QEMU_BIN}/qemu-system-aarch64}
PREFIX=aarch64-linux-
ARCH=arm64
PATH_ARM64="/opt/kernel/${DEFAULT_CC}/aarch64-linux/bin"

PATH=${PATH}:${PATH_ARM64}

patch_defconfig()
{
    local defconfig=$1
    local fixups=${2//:/ }
    local fixup

    # File system support
    enable_config "${defconfig}" CONFIG_EROFS_FS
    enable_config "${defconfig}" CONFIG_EXFAT_FS
    enable_config "${defconfig}" CONFIG_F2FS_FS
    enable_config "${defconfig}" CONFIG_GFS2_FS
    enable_config "${defconfig}" CONFIG_HFS_FS
    enable_config "${defconfig}" CONFIG_HFSPLUS_FS
    enable_config "${defconfig}" CONFIG_JFS_FS
    enable_config "${defconfig}" CONFIG_MINIX_FS
    enable_config "${defconfig}" CONFIG_NILFS2_FS
    enable_config "${defconfig}" CONFIG_XFS_FS
    enable_config "${defconfig}" CONFIG_BCACHEFS_FS

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

    # For TPM testing
    enable_config "${defconfig}" CONFIG_TCG_TPM CONFIG_TCG_TIS

    # Needed for Nuvoton boards
    enable_config "${defconfig}" CONFIG_COMMON_CLK_NPCM8XX
    enable_config "${defconfig}" CONFIG_PINCTRL_NPCM8XX
    enable_config "${defconfig}" CONFIG_I2C_NPCM
    enable_config "${defconfig}" CONFIG_SPI_NPCM_FIU
    enable_config "${defconfig}" CONFIG_SPI_NPCM_PSPI
    enable_config "${defconfig}" CONFIG_MMC_SDHCI_NPCM
    enable_config "${defconfig}" CONFIG_GPIO_NPCM_SGPIO

    # Raspberry
    enable_config "${defconfig}" CONFIG_CLK_RASPBERRYPI
    enable_config "${defconfig}" CONFIG_ARM_RASPBERRYPI_CPUFREQ

    # i.MX 8
    enable_config "${defconfig}" CONFIG_SPI_IMX
    enable_config "${defconfig}" CONFIG_DWMAC_IMX8
    enable_config "${defconfig}" CONFIG_PHY_FSL_IMX8MQ_USB
    enable_config "${defconfig}" CONFIG_INTERCONNECT_IMX8MQ

    enable_config "${defconfig}" CONFIG_DYNAMIC_DEBUG

    for fixup in ${fixups}; do
	case "${fixup}" in
	be)
	    enable_config "${defconfig}" CONFIG_CPU_BIG_ENDIAN
	    ;;
	pagesize*)
	    enable_config "${defconfig}" "CONFIG_ARM64_${fixup##pagesize}K_PAGES"
	    ;;
	*)
	    ;;
	esac
    done
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
    local waitflag="manual"

    if [[ "${rootfs}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":${rootfs##*.}"
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
    "imx8mp-evk")
	QEMU="${QEMU_V100}"
	initcli+=" console=ttymxc1 earlycon"
	extra_params+=" -serial null"
	waitflag="automatic"
	;;
    "virt")
	initcli+=" earlycon=pl011,0x9000000 console=ttyAMA0"
	extra_params+=" -cpu cortex-a57"
	;;
    "xlnx-versal-virt")
	initcli+=" earlycon=pl011,0xff000000 console=ttyAMA0"
	extra_params+=" -cpu cortex-a57"
	;;
    "npcm845-evb")
	QEMU="${QEMU_V100}"
	initcli+=" console=ttyS0,115200"
	initcli+=" earlycon=uart8250,mmio32,0xf0000000,115200n8"
	;;
    "raspi3b")
	initcli+=" earlycon=uart8250,mmio32,0x3f215040 console=ttyS1,115200"
	extra_params+=" -serial null"
	;;
    "raspi4b")
	QEMU="${QEMU_V100}"
	initcli+=" earlycon console=ttyS1,115200"
	extra_params+=" -serial null"
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

__runkernel_common()
{
    local prefix="$1"
    local retcode=0
    local efi="efi:"
    local exfat=""
    local minix=":fstest=minix"
    local i82557a="i82557a"
    local i82557b="i82557b"
    local tpm="tpm-tis-device:"

    # Some tests are known to fail in big endian mode.
    # Skip or replace.
    if [[ "${prefix}" == *be* ]]; then
	efi=""
	minix=""
	tpm=""
	i82557a="i82558a"
	i82557b="i82558b"
    fi

    # exfat is not supported in v5.4 and older
    if [[ ${linux_version_code} -ge $(kernel_version 5 10) ]]; then
	exfat=":fstest=exfat"
    fi

    # Failing network tests: i82551, usb-net

    runkernel virt defconfig ${prefix}smp:net=e1000:mem512 rootfs.cpio
    retcode=$?
    runkernel virt defconfig ${prefix}smp2:${tpm}net=e1000e:${efi}mem512:usb-xhci rootfs.ext2
    retcode=$((retcode + $?))
    runkernel virt defconfig "${prefix}smp2:net=i82801:mem512:usb-ehci" rootfs.ext2
    retcode=$((retcode + $?))
    runkernel virt defconfig ${prefix}smp2:net=i82550:mem512:usb-ohci rootfs.ext2
    retcode=$((retcode + $?))
    runkernel virt defconfig ${prefix}smp4:net=ne2k_pci:mem512:usb-uas-xhci rootfs.btrfs
    retcode=$((retcode + $?))
    runkernel virt defconfig "${prefix}smp6:net=pcnet:mem512:virtio${minix}" rootfs.ext2
    retcode=$((retcode + $?))
    runkernel virt defconfig ${prefix}smp8:net=rtl8139:mem512:virtio-pci rootfs.ext2
    retcode=$((retcode + $?))
    runkernel virt defconfig ${prefix}smp:net=tulip:${efi}mem512:virtio-blk rootfs.ext2
    retcode=$((retcode + $?))
    runkernel virt defconfig "${prefix}smp2:net=virtio-net:mem512:nvme${exfat}" rootfs.btrfs
    retcode=$((retcode + $?))
    runkernel virt defconfig ${prefix}smp4:net=e1000:mem512:sdhci-mmc "rootfs.erofs"
    retcode=$((retcode + $?))
    runkernel virt defconfig "${prefix}smp6:net=${i82557a}:mem512:scsi[DC395]" "rootfs.f2fs"
    retcode=$((retcode + $?))
    runkernel virt defconfig "${prefix}smp8:net=${i82557b}:${efi}mem512:scsi[AM53C974]" rootfs.btrfs
    retcode=$((retcode + $?))
    runkernel virt defconfig "${prefix}smp2:net=i82558b:mem512:scsi[MEGASAS]:fstest=hfs" rootfs.ext2
    retcode=$((retcode + $?))
    runkernel virt defconfig "${prefix}smp4:net=i82559er:mem512:scsi[MEGASAS2]:fstest=hfs+" rootfs.btrfs
    retcode=$((retcode + $?))
    runkernel virt defconfig "${prefix}smp6:net=e1000-82544gc:mem512:scsi[53C810]:fstest=jfs" rootfs.ext2
    retcode=$((retcode + $?))
    runkernel virt defconfig "${prefix}smp8:net=e1000-82545em:mem512:scsi[53C895A]:fstest=nilfs2" rootfs.btrfs
    retcode=$((retcode + $?))
    runkernel virt defconfig "${prefix}smp:net=pcnet:mem512:scsi[FUSION]:fstest=xfs" rootfs.ext2
    retcode=$((retcode + $?))
    runkernel virt defconfig "${prefix}smp2:net=usb-ohci:mem512:scsi[virtio]" rootfs.ext2
    retcode=$((retcode + $?))

    # file system tests
    if [[ ${runall} -ne 0 ]]; then
	# Run all file system tests, even those known to fail
	runkernel virt defconfig ${prefix}smp4:net=e1000:mem512:nvme "rootfs.btrfs"
	retcode=$((retcode + $?))
	runkernel virt defconfig ${prefix}smp4:net=e1000:mem512:nvme "rootfs.erofs"
	retcode=$((retcode + $?))
	runkernel virt defconfig ${prefix}smp4:net=e1000:mem512:nvme "rootfs.f2fs"
	retcode=$((retcode + $?))
	runkernel virt defconfig ${prefix}smp4:net=e1000:mem512:nvme:fstest=exfat "rootfs.ext2"
	retcode=$((retcode + $?))
	runkernel virt defconfig ${prefix}smp4:net=e1000:mem512:nvme:fstest=gfs2 "rootfs.ext2"
	retcode=$((retcode + $?))
	runkernel virt defconfig ${prefix}smp4:net=e1000:mem512:nvme:fstest=hfs "rootfs.ext2"
	retcode=$((retcode + $?))
	runkernel virt defconfig ${prefix}smp4:net=e1000:mem512:nvme:fstest=hfs+ "rootfs.ext2"
	retcode=$((retcode + $?))
	runkernel virt defconfig ${prefix}smp4:net=e1000:mem512:nvme:fstest=jfs "rootfs.ext2"
	retcode=$((retcode + $?))
	runkernel virt defconfig ${prefix}smp4:net=e1000:mem512:nvme:fstest=minix "rootfs.ext2"
	retcode=$((retcode + $?))
	runkernel virt defconfig ${prefix}smp4:net=e1000:mem512:nvme:fstest=nilfs2 "rootfs.ext2"
	retcode=$((retcode + $?))
	runkernel virt defconfig ${prefix}smp4:net=e1000:mem512:nvme:fstest=xfs "rootfs.ext2"
	retcode=$((retcode + $?))
	runkernel virt defconfig ${prefix}smp4:net=e1000:mem512:nvme:fstest=bcachefs "rootfs.ext2"
	retcode=$((retcode + $?))
    fi

    if [[ "${prefix}" != *be* ]]; then
	runkernel xlnx-versal-virt defconfig ${prefix}smp:net=default:mem512 rootfs.cpio
	retcode=$((retcode + $?))
	runkernel xlnx-versal-virt defconfig "${prefix}smp4:net=default:mem512:virtio-blk" rootfs.ext2
	retcode=$((retcode + $?))
	runkernel xlnx-versal-virt defconfig "${prefix}smp4:net=default:mem512:sd0,b300" rootfs.ext2
	retcode=$((retcode + $?))
    fi

    runkernel "xlnx-zcu102" defconfig ${prefix}smp:mem2G rootfs.cpio xilinx/zynqmp-ep108.dtb
    retcode=$((retcode + $?))
    runkernel "xlnx-zcu102" defconfig ${prefix}smp:mem2G:sd rootfs.ext2 xilinx/zynqmp-ep108.dtb
    retcode=$((retcode + $?))
    runkernel "xlnx-zcu102" defconfig ${prefix}smp:mem2G:sata rootfs.ext2 xilinx/zynqmp-ep108.dtb
    retcode=$((retcode + $?))

    if [[ ${linux_version_code} -lt $(kernel_version 5 6) ]] || [[ ${runall} -ne 0 ]]; then
	# Since Linux v5.6, the entire clock tree for zynqmp depends on firmware
	# support (which is not available in qemu). See Linux kernel upstream
	# commit 9c8a47b484ed ("arm64: dts: xilinx: Add the clock nodes for
	# zynqmp") for details. Without clocks, loading various io drivers
	# including the serial port driver stalls, and it becomes all but
	# impossible to use the emulation on any kernel later than v5.5.
	runkernel xlnx-zcu102 defconfig ${prefix}smp:mem2G rootfs.cpio xilinx/zynqmp-zcu102-rev1.0.dtb
	retcode=$((retcode + $?))
	runkernel xlnx-zcu102 defconfig ${prefix}smp:mem2G:sd1 rootfs.ext2 xilinx/zynqmp-zcu102-rev1.0.dtb
	retcode=$((retcode + $?))
	runkernel xlnx-zcu102 defconfig ${prefix}smp:mem2G:sata rootfs.btrfs xilinx/zynqmp-zcu102-rev1.0.dtb
	retcode=$((retcode + $?))
    fi

    if [[ ${runall} -ne 0 ]]; then
	# hangs in boot
	#    platform f000901c.watchdog: deferred probe pending: (reason unknown)
	#    platform f0000000.serial: deferred probe pending: of_serial: failed to get clock
	runkernel npcm845-evb defconfig ${prefix}smp:mem1G rootfs.cpio nuvoton/nuvoton-npcm845-evb.dtb
	retcode=$((retcode + $?))
	runkernel npcm845-evb defconfig ${prefix}smp:mtd32:mem1G rootfs.ext2 nuvoton/nuvoton-npcm845-evb.dtb
	retcode=$((retcode + $?))
    fi

    runkernel raspi3b defconfig ${prefix}smp:mem1G rootfs.cpio broadcom/bcm2837-rpi-3-b.dtb
    retcode=$((retcode + $?))
    if [[ "${prefix}" != *be* ]]; then
	# possible endianness problem in mmc driver
	runkernel raspi3b defconfig ${prefix}smp4:mem1G:sd rootfs.ext2 broadcom/bcm2837-rpi-3-b.dtb
	retcode=$((retcode + $?))
    fi

    # imx8mp-evk should support SHDCI, USB, and PCI interfaces.
    runkernel imx8mp-evk defconfig ${prefix}smp4:mem2G:net=default rootfs.cpio freescale/imx8mp-evk.dtb
    retcode=$((retcode + $?))
    runkernel imx8mp-evk defconfig ${prefix}smp4:mem2G:sdb2:net=default rootfs.ext2 freescale/imx8mp-evk.dtb
    retcode=$((retcode + $?))
    runkernel imx8mp-evk defconfig ${prefix}smp4:mem2G:virtio-pci:net=default rootfs.ext2 freescale/imx8mp-evk.dtb
    retcode=$((retcode + $?))
    runkernel imx8mp-evk defconfig ${prefix}smp4:mem2G:virtio:net=default rootfs.ext2 freescale/imx8mp-evk.dtb
    retcode=$((retcode + $?))
    runkernel imx8mp-evk defconfig ${prefix}smp4:mem2G:usb:net=default rootfs.ext2 freescale/imx8mp-evk.dtb
    retcode=$((retcode + $?))
    if [[ ${runall} -ne 0 ]]; then
        # PCI interface access attempts result in hung task hang during boot
        runkernel imx8mp-evk defconfig ${prefix}smp4:mem2G:usb-xhci:net=default rootfs.ext2 freescale/imx8mp-evk.dtb
        retcode=$((retcode + $?))
        runkernel imx8mp-evk defconfig ${prefix}smp4:mem2G:nvme:net=default rootfs.btrfs freescale/imx8mp-evk.dtb
        retcode=$((retcode + $?))
        runkernel imx8mp-evk defconfig ${prefix}smp4:mem2G:scsi[53C810]:net=default rootfs.ext2 freescale/imx8mp-evk.dtb
        retcode=$((retcode + $?))
    fi

    if [[ ${runall} -ne 0 ]]; then
	# Crashes (qemu 9.1 and mainline as of 10/12/24) due to missing interrupt
	# controller support, missing i2c controller support, and missing clock
	# controller support (gave up here).
	runkernel raspi4b defconfig ${prefix}smp:mem2G rootfs.cpio broadcom/bcm2711-rpi-4-b.dtb
	retcode=$((retcode + $?))
	runkernel raspi4b defconfig ${prefix}smp4:mem2G:sd rootfs.ext2 broadcom/bcm2711-rpi-4-b.dtb
	retcode=$((retcode + $?))
    fi

    if [[ ${runall} -ne 0 ]]; then
	# The following all fail to boot. Something seems to be missing/bad in the configuration.
	runkernel raspi3b defconfig ${prefix}pagesize16:smp:mem1G rootfs.cpio broadcom/bcm2837-rpi-3-b.dtb
	retcode=$((retcode + $?))
	runkernel raspi3b defconfig ${prefix}pagesize16:smp4:mem1G:sd rootfs.ext2 broadcom/bcm2837-rpi-3-b.dtb
	retcode=$((retcode + $?))
	runkernel raspi3b defconfig ${prefix}pagesize16:smp4:mem1G:sd rootfs.btrfs broadcom/bcm2837-rpi-3-b.dtb
	retcode=$((retcode + $?))
	runkernel virt defconfig ${prefix}pagesize16:smp4:net=ne2k_pci:mem1024:usb-uas-xhci rootfs.btrfs
	retcode=$((retcode + $?))
	runkernel virt defconfig ${prefix}pagesize16:smp6:net=pcnet:mem1024:virtio${minix} rootfs.ext2
	retcode=$((retcode + $?))
	runkernel virt defconfig ${prefix}pagesize16:smp8:net=rtl8139:mem1024:virtio-pci:fstest=hfs rootfs.erofs
	retcode=$((retcode + $?))
	runkernel virt defconfig ${prefix}pagesize16:smp:net=tulip:${efi}mem1024:virtio-blk rootfs.f2fs
	retcode=$((retcode + $?))

	runkernel virt defconfig ${prefix}pagesize64:smp4:net=ne2k_pci:mem1024:usb-uas-xhci rootfs.btrfs
	retcode=$((retcode + $?))
	runkernel virt defconfig ${prefix}pagesize64:smp6:net=pcnet:mem1024:virtio${minix} rootfs.ext2
	retcode=$((retcode + $?))
	runkernel virt defconfig ${prefix}pagesize64:smp8:net=rtl8139:mem1024:virtio-pci:fstest=hfs rootfs.erofs
	retcode=$((retcode + $?))
	runkernel virt defconfig ${prefix}pagesize64:smp:net=tulip:${efi}mem1024:virtio-blk rootfs.f2fs
	retcode=$((retcode + $?))
    fi

    return ${retcode}
}
