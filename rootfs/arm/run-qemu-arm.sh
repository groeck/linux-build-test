#!/bin/bash

progdir=$(cd $(dirname $0); pwd)
. ${progdir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

QEMU_MIDWAY=${QEMU:-${QEMU_V30_BIN}/qemu-system-arm}
QEMU_V60=${QEMU:-${QEMU_V60_BIN}/qemu-system-arm}
QEMU=${QEMU:-${QEMU_BIN}/qemu-system-arm}

machine=$1
config=$2
options=$3
devtree=$4
boot=$5

ARCH=arm

PREFIX_A="arm-linux-gnueabi-"
PREFIX_M3="arm-linux-"

# integratorcp does not boot in v5.4.y when using gcc 10.3.0
PATH_ARM="/opt/kernel/gcc-9.3.0-nolibc/arm-linux-gnueabi/bin"
# Cortex-M3 (thumb) needs binutils 2.28 or earlier
PATH_ARM_M3=/opt/kernel/arm-m3/gcc-7.3.0/bin

PATH=${PATH_ARM}:${PATH_ARM_M3}:${PATH}

skip_44="arm:imx25-pdk:imx_v4_v5_defconfig:nonand:sd:mem128:net,default \
	arm:raspi2:multi_v7_defconfig \
	arm:raspi2:multi_v7_defconfig:sd \
	arm:vexpress-a9:multi_v7_defconfig:nolocktests:flash64:mem128:net,default \
	arm:mcimx6ul-evk:imx_v6_v7_defconfig:nodrm:usb0:mem256 \
	arm:mcimx7d-sabre:multi_v7_defconfig:mem256 \
	arm:mcimx7d-sabre:multi_v7_defconfig:usb1:mem256 \
	arm:mcimx7d-sabre:multi_v7_defconfig:sd:mem256 \
	arm:sabrelite:multi_v7_defconfig:mmc1:mem256:net,default \
	arm:virt:multi_v7_defconfig:virtio-blk:mem512:net,virtio-net-device \
	arm:versatilepb:versatile_defconfig:aeabi:pci:flash64:mem128:net,default \
	arm:realview-pbx-a9:realview_defconfig:realview_pb:net,default"
skip_49="arm:imx25-pdk:imx_v4_v5_defconfig:nonand:sd:mem128:net,default \
	arm:ast2500-evb:aspeed_g5_defconfig:notests:net,nic \
	arm:ast2500-evb:aspeed_g5_defconfig:notests:mtd32:net,nic \
	arm:ast2500-evb:aspeed_g5_defconfig:notests:sd:net,nic \
	arm:ast2500-evb:aspeed_g5_defconfig:notests:usb:net,nic \
	arm:ast2600-evb:aspeed_g5_defconfig:notests \
	arm:ast2600-evb:multi_v7_defconfig:notests \
	arm:vexpress-a9:multi_v7_defconfig:nolocktests:flash64:mem128:net,default \
	arm:xilinx-zynq-a9:multi_v7_defconfig:usb0:mem128 \
	arm:mcimx6ul-evk:imx_v6_v7_defconfig:nodrm:mem256 \
	arm:mcimx6ul-evk:imx_v6_v7_defconfig:nodrm:sd:mem256 \
	arm:mcimx6ul-evk:imx_v6_v7_defconfig:nodrm:usb0:mem256 \
	arm:mcimx7d-sabre:multi_v7_defconfig:mem256 \
	arm:mcimx7d-sabre:multi_v7_defconfig:usb1:mem256 \
	arm:mcimx7d-sabre:multi_v7_defconfig:sd:mem256 \
	arm:orangepi-pc:multi_v7_defconfig:usb0:net,nic \
	arm:versatilepb:versatile_defconfig:aeabi:pci:flash64:mem128:net,default \
	arm:palmetto-bmc:aspeed_g4_defconfig:net,nic \
	arm:palmetto-bmc:aspeed_g4_defconfig:mtd32:net,nic"
skip_414="arm:ast2500-evb:aspeed_g5_defconfig:notests:sd:net,nic \
	arm:ast2500-evb:aspeed_g5_defconfig:notests:usb:net,nic \
	arm:ast2600-evb:aspeed_g5_defconfig:notests \
	arm:ast2600-evb:multi_v7_defconfig:notests \
	arm:versatilepb:versatile_defconfig:aeabi:pci:flash64:mem128:net,default \
	arm:vexpress-a9:multi_v7_defconfig:nolocktests:flash64:mem128:net,default \
	arm:xilinx-zynq-a9:multi_v7_defconfig:usb0:mem128 \
	arm:mcimx7d-sabre:multi_v7_defconfig:mem256 \
	arm:mcimx7d-sabre:multi_v7_defconfig:usb1:mem256 \
	arm:mcimx7d-sabre:multi_v7_defconfig:sd:mem256"
skip_419="arm:ast2500-evb:aspeed_g5_defconfig:notests:sd:net,nic \
	arm:npcm750-evb:multi_v7_defconfig:npcm:usb0.1 \
	arm:vexpress-a9:multi_v7_defconfig:nolocktests:flash64:mem128:net,default"
skip_54="arm:palmetto-bmc:aspeed_g4_defconfig:mtd32:net,nic \
	arm:ast2600-evb:aspeed_g5_defconfig:notests:sd2:net,nic \
	arm:npcm750-evb:multi_v7_defconfig:npcm:usb0.1"
skip_510="arm:npcm750-evb:multi_v7_defconfig:npcm:usb0.1"

. ${progdir}/../scripts/common.sh

patch_defconfig()
{
    local defconfig=$1
    local fixups=${2//:/ }
    local fixup

    # Disable Bluetooth and wireless. We won't ever use or test it.
    echo "CONFIG_BT=n" >> ${defconfig}
    echo "CONFIG_WLAN=n" >> ${defconfig}
    echo "CONFIG_WIRELESS=n" >> ${defconfig}

    # Always enable ...
    echo "CONFIG_DEVTMPFS=y" >> ${defconfig}
    echo "CONFIG_DEVTMPFS_MOUNT=y" >> ${defconfig}
    echo "CONFIG_BLK_DEV_INITRD=y" >> ${defconfig}

    # Options needed to be built into the kernel for device support
    # on pxa devices
    # MTD, squashfs
    sed -i -e 's/CONFIG_MTD_BLOCK=m/CONFIG_MTD_BLOCK=y/' ${defconfig}
    sed -i -e 's/CONFIG_MTD_PXA2XX=m/CONFIG_MTD_PXA2XX=y/' ${defconfig}
    sed -i -e 's/CONFIG_SQUASHFS=m/CONFIG_SQUASHFS=y/' ${defconfig}
    # MMC
    sed -i -e 's/CONFIG_MMC_BLOCK=m/CONFIG_MMC_BLOCK=y/' ${defconfig}
    sed -i -e 's/CONFIG_MMC_PXA=m/CONFIG_MMC_PXA=y/' ${defconfig}
    # PCMCIA
    sed -i -e 's/CONFIG_ATA=m/CONFIG_ATA=y/' ${defconfig}
    sed -i -e 's/CONFIG_BLK_DEV_SD=m/CONFIG_BLK_DEV_SD=y/' ${defconfig}
    sed -i -e 's/CONFIG_PCCARD=m/CONFIG_PCCARD=y/' ${defconfig}
    sed -i -e 's/CONFIG_PCMCIA=m/CONFIG_PCMCIA=y/' ${defconfig}
    sed -i -e 's/CONFIG_PATA_PCMCIA=m/CONFIG_PATA_PCMCIA=y/' ${defconfig}
    sed -i -e 's/CONFIG_PCMCIA_PXA2XX=m/CONFIG_PCMCIA_PXA2XX=y/' ${defconfig}
    # USB
    sed -i -e 's/CONFIG_USB=m/CONFIG_USB=y/' ${defconfig}
    sed -i -e 's/CONFIG_USB_STORAGE=m/CONFIG_USB_STORAGE=y/' ${defconfig}
    sed -i -e 's/CONFIG_USB_OHCI_HCD=m/CONFIG_USB_OHCI_HCD=y/' ${defconfig}
    sed -i -e 's/CONFIG_USB_OHCI_HCD_PXA27X=m/CONFIG_USB_OHCI_HCD_PXA27X=y/' ${defconfig}
    # NAND (spitz)
    # Doesn't work as-is; it looks like NAND images need to be
    # specially prepared.
    # sed -i -e 's/CONFIG_MTD_RAW_NAND=m/CONFIG_MTD_RAW_NAND=y/' ${defconfig}
    # sed -i -e 's/CONFIG_MTD_NAND_SHARPSL=m/CONFIG_MTD_NAND_SHARPSL=y/' ${defconfig}

    # Always build PXA watchdog into kernel if enabled
    sed -i -e 's/CONFIG_SA1100_WATCHDOG=m/CONFIG_SA1100_WATCHDOG=y/' ${defconfig}

    # Build CONFIG_NOP_USB_XCEIV into kernel if enabled
    # Needed for mcimx7d-sabre usb boot
    sed -i -e 's/CONFIG_NOP_USB_XCEIV=m/CONFIG_NOP_USB_XCEIV=y/' ${defconfig}

    # Enable GPIO_MXC if supported, and build into kernel
    # See upstream kernel commit 12d16b397ce0 ("gpio: mxc: Support module build")
    if grep -F -q CONFIG_GPIO_MXC ${defconfig}; then
	echo "CONFIG_GPIO_MXC=y" >> ${defconfig}
    fi

    for fixup in ${fixups}; do
	case "${fixup}" in
	nofdt)
	    echo "CONFIG_MACH_PXA27X_DT=n" >> ${defconfig}
	    echo "CONFIG_MACH_PXA3XX_DT=n" >> ${defconfig}
	    ;;
	aeabi)
	    echo "CONFIG_AEABI=y" >> ${defconfig}
	    ;;
	pci)
	    echo "CONFIG_PCI=y" >> ${defconfig}
	    echo "CONFIG_PCI_VERSATILE=y" >> ${defconfig}
	    echo "CONFIG_OF=y" >> ${defconfig}
	    echo "CONFIG_OF_PCI=y" >> ${defconfig}
	    echo "CONFIG_OF_PCI_IRQ=y" >> ${defconfig}
	    ;;
	scsi)
	    echo "CONFIG_SCSI=y" >> ${defconfig}
	    echo "CONFIG_SCSI_SYM53C8XX_2=y" >> ${defconfig}
	    echo "CONFIG_BLK_DEV_SD=y" >> ${defconfig}
	    ;;
	cpuidle)
	    # CPUIDLE causes Exynos targets to run really slow
	    echo "CONFIG_CPU_IDLE=n" >> ${defconfig}
	    echo "CONFIG_ARM_EXYNOS_CPUIDLE=n" >> ${defconfig}
	    ;;
	nonand)
	    # For imx25, disable NAND (not supported as of qemu 2.5, causes
	    # a runtime warning).
	    echo "CONFIG_MTD_NAND_MXC=n" >> ${defconfig}
	    ;;
	nodrm)
	    # qemu does not support CONFIG_DRM_IMX. This starts to fail
	    # with commit 5f2f911578fb (drm/imx: atomic phase 3 step 1:
	    # Use atomic configuration), ie since v4.8. Impact is long boot delay
	    # (kernel needs 70+ seconds to boot) and several kernel tracebacks
	    # in drm code.
	    # It also does not support CONFIG_DRM_MXSFB; trying to enable it
	    # crashes the kernel when running mcimx6ul-evk.
	    echo "CONFIG_DRM_MXSFB=n" >> ${defconfig}
	    echo "CONFIG_DRM_IMX=n" >> ${defconfig}
	    ;;
	nocrypto)
	    # Broken (hangs) for some platforms
	    echo "CONFIG_CRYPTO_MANAGER_DISABLE_TESTS=y" >> ${defconfig}
	    ;;
	realview_eb)
	    # Older versions of realview config files need additional CPU support.
	    echo "CONFIG_REALVIEW_EB_A9MP=y" >> ${defconfig}
	    echo "CONFIG_REALVIEW_EB_ARM11MP_REVB=y" >> ${defconfig}
	    echo "CONFIG_MACH_REALVIEW_PBX=y" >> ${defconfig}
	    echo "CONFIG_MACH_REALVIEW_PB1176=y" >> ${defconfig}
	    ;;
	realview_pb)
	    # Similar for PB-A8. Also disable some EB and incompatible PB
	    # configurations.
	    echo "CONFIG_REALVIEW_EB_A9MP=n" >> ${defconfig}
	    echo "CONFIG_REALVIEW_EB_ARM11MP=n" >> ${defconfig}
	    echo "CONFIG_MACH_REALVIEW_PB11MP=n" >> ${defconfig}
	    echo "CONFIG_MACH_REALVIEW_PB1176=n" >> ${defconfig}
	    echo "CONFIG_MACH_REALVIEW_PBX=y" >> ${defconfig}
	    echo "CONFIG_MACH_REALVIEW_PBA8=y" >> ${defconfig}
	    ;;
	npcm)
	    echo "CONFIG_ARCH_NPCM=y" >> ${defconfig}
	    echo "CONFIG_ARCH_NPCM7XX=y" >> ${defconfig}
	    echo "CONFIG_SENSORS_NPCM7XX=y" >> ${defconfig}
	    echo "CONFIG_NPCM7XX_WATCHDOG=y" >> ${defconfig}
	    echo "CONFIG_SPI_NPCM_FIU=y" >> ${defconfig}
	    ;;
	esac
    done
}

runkernel()
{
    local defconfig=$1
    local mach=$2
    local cpu=$3
    local rootfs=$4
    local mode=$5
    local fixup=$6
    local dtb=$7
    local ddtb="${dtb%.dtb}"
    local dtbfile="arch/arm/boot/dts/${dtb}"
    local nonet=0
    local logfile="$(__mktemp)"
    local waitlist=("Restarting" "Boot successful" "Rebooting")
    local build="${ARCH}:${mach}:${defconfig}${fixup:+:${fixup}}"
    local pbuild="${build}${dtb:+:${dtb%.dtb}}"
    local QEMUCMD="${QEMU}"
    local PREFIX="${PREFIX_A}"
    if [[ "${cpu}" = "cortex-m3" ]]; then
	PREFIX="${PREFIX_M3}"
    fi

    local _boot
    if [[ "${rootfs%.gz}" == *cpio ]]; then
	pbuild+=":initrd"
	_boot="initrd"
    else
	pbuild+=":rootfs"
	_boot="rootfs"
    fi

    pbuild="${pbuild//+(:)/:}"
    build="${build//+(:)/:}"

    if ! match_params "${machine}@${mach}" "${config}@${defconfig}" "${options}@${fixup}" "${devtree}@${ddtb}" "${boot}@${_boot}"; then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    echo -n "Building ${pbuild} ... "

    if ! checkskip "${build}" ; then
	return 0
    fi

    case "${mach}" in
    "ast2600-evb")
	# Network tests need v5.11 or later
	# Older kernels only instantiate the second Ethernet interface.
	if [[ ${linux_version_code} -lt $(kernel_version 5 11) ]]; then
	    nonet=1
	fi
	;;
    "orangepi-pc")
	# Network tests need v4.19 or later
	if [[ ${linux_version_code} -lt $(kernel_version 4 19) ]]; then
	    nonet=1
        fi
	;;
    *)
	;;
    esac
    if [[ "${nonet}" -ne 0 ]]; then
	fixup="$(echo ${fixup} | sed -e 's/:\+net,nic//')"
    fi

    if ! dosetup -F "${fixup}" -c "${defconfig}${fixup%::*}" "${rootfs}" "${defconfig}"; then
	if [[ __dosetup_rc -eq 2 ]]; then
	    return 0
	fi
	return 1
    fi

    # If a dtb file was specified but does not exist, skip the build.
    local dtbcmd=""
    if [[ -n "${dtb}" ]]; then
	if [[ ! -e "${dtbfile}" ]]; then
	    echo "skipped"
	    return 0
	fi
	dtbcmd="-dtb ${dtbfile}"
    fi

    rootfs="$(rootfsname ${rootfs})"

    kernel="arch/arm/boot/zImage"
    case ${mach} in
    "sx1")
	initcli+=" console=ttyS0,115200 earlycon=uart8250,mmio32,0xfffb0000,115200n8"
	;;
    "mps2-an385")
	extra_params+=" -bios ${progdir}/mps2-boot.axf"
	initcli=""
	kernel="vmlinux"
	;;
    "ast2500-evb" | "ast2600-evb" | "palmetto-bmc" | "romulus-bmc" | \
    "witherspoon-bmc" | "swift-bmc")
	initcli+=" console=ttyS4,115200"
	initcli+=" earlycon=uart8250,mmio32,0x1e784000,115200n8"
	extra_params+=" -nodefaults"
	;;
    "g220a-bmc")
	initcli+=" console=ttyS4,115200"
	initcli+=" earlycon=uart8250,mmio32,0x1e784000,115200n8"
	extra_params+=" -nodefaults"
	QEMUCMD="${QEMU_V60}"
	;;
    "tacoma-bmc")
	initcli+=" console=ttyS4,115200"
	initcli+=" earlycon=uart8250,mmio32,0x1e784000,115200n8"
	extra_params+=" -nodefaults"
	;;
    "orangepi-pc")
	initcli+=" console=ttyS0,115200"
	initcli+=" earlycon=uart8250,mmio32,0x1c28000,115200n8"
	extra_params+=" -nodefaults"
	;;
    "npcm750-evb" | "quanta-gsj")
	initcli+=" console=ttyS3,115200"
	initcli+=" earlycon=uart8250,mmio32,0xf0004000,115200n8"
	extra_params+=" -nodefaults -serial null -serial null -serial null"
	;;
    "akita" | "borzoi" | "spitz" | "tosa" | "terrier" | "z2" | "mainstone")
	initcli+=" console=ttyS0"
	;;
    "collie")
	initcli+=" console=ttySA1"
	;;
    "cubieboard")
	initcli+=" earlycon=uart8250,mmio32,0x1c28000,115200n8"
	initcli+=" console=ttyS0"
	;;
    "imx25-pdk" )
	initcli+=" console=ttymxc0,115200"
	;;
    "raspi2")
	initcli+=" earlycon=pl011,0x3f201000"
	initcli+=" console=ttyAMA0"
	;;
    "sabrelite" | "mcimx6ul-evk")
	initcli+=" earlycon=ec_imx6q,mmio,0x21e8000,115200n8"
	initcli+=" console=ttymxc1,115200"
	extra_params+=" -display none -serial null"
	;;
    "mcimx7d-sabre")
	initcli+=" earlycon=ec_imx6q,mmio,0x30860000,115200n8"
	initcli+=" console=ttymxc0,115200"
	extra_params+=" -display none"
	;;
    "smdkc210")
	initcli+=" console=ttySAC0,115200n8"
	initcli+=" earlycon=exynos4210,mmio32,0x13800000,115200n8"
	;;
    "midway")
	initcli+=" console=ttyAMA0,115200"
	# Fails silently with later versions of qemu (up to at least 4.2)
	QEMUCMD="${QEMU_MIDWAY}"
	;;
    "realview-pb-a8" | "realview-pbx-a9" | \
    "realview-eb-mpcore" | "realview-eb" | \
    "versatileab" | "versatilepb" | \
    "highbank" | "integratorcp" | "virt" | \
    "vexpress-a9" | "vexpress-a15" | "vexpress-a15-a7")
	initcli+=" console=ttyAMA0,115200"
	;;
    "xilinx-zynq-a9")
	initcli+=" console=ttyPS0 earlycon"
	extra_params+=" -serial null"
	;;
    *)
	;;
    esac

    execute "${mode}" waitlist[@] \
        ${QEMUCMD} -M ${mach} \
	    ${cpu:+-cpu ${cpu}} \
	    -kernel ${kernel} \
	    -no-reboot \
	    ${extra_params} \
	    ${initcli:+--append "${initcli}"} \
	    ${dtbcmd} \
	    -nographic -monitor null -serial stdio

    return $?
}

echo "Build reference: $(git describe)"
echo

runkernel versatile_defconfig versatilepb "" \
	rootfs-armv5.ext2 auto aeabi:pci::scsi:mem128:net,default versatile-pb.dtb
retcode=$?
checkstate ${retcode}
runkernel versatile_defconfig versatilepb "" \
	rootfs-armv5.ext2 auto aeabi:pci::flash64:mem128:net,default versatile-pb.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel versatile_defconfig versatilepb "" \
	rootfs-armv5.cpio auto aeabi:pci::mem128:net,default versatile-pb.dtb
retcode=$((retcode + $?))
checkstate ${retcode}

runkernel versatile_defconfig versatileab "" \
	rootfs-armv5.cpio auto ::mem128:net,default versatile-ab.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel imx_v4_v5_defconfig imx25-pdk "" \
	rootfs-armv5.cpio manual nonand::mem128:net,default imx25-pdk.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel imx_v4_v5_defconfig imx25-pdk "" \
	rootfs-armv5.ext2 manual nonand::sd:mem128:net,default imx25-pdk.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel imx_v4_v5_defconfig imx25-pdk "" \
	rootfs-armv5.ext2 manual nonand::usb0:mem128:net,default imx25-pdk.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel imx_v4_v5_defconfig imx25-pdk "" \
	rootfs-armv5.ext2 manual nonand::usb1:mem128:net,default imx25-pdk.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

# Ethernet instantiates but fails to get an IP address
# (no packets received on eth0)
runkernel imx_v6_v7_defconfig mcimx6ul-evk "" \
	rootfs-armv7a.cpio manual nodrm::mem256 imx6ul-14x14-evk.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel imx_v6_v7_defconfig mcimx6ul-evk "" \
	rootfs-armv7a.ext2 manual nodrm::sd:mem256 imx6ul-14x14-evk.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel imx_v6_v7_defconfig mcimx6ul-evk "" \
	rootfs-armv7a.ext2 manual nodrm::usb0:mem256 imx6ul-14x14-evk.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel imx_v6_v7_defconfig mcimx6ul-evk "" \
	rootfs-armv7a.ext2 manual nodrm::usb1:mem256 imx6ul-14x14-evk.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

# vexpress tests generate a warning during reboot if CONFIG_PROVE_RCU is enabled
runkernel multi_v7_defconfig vexpress-a9 "" \
	rootfs-armv5.cpio auto nolocktests::mem128:net,default \
	vexpress-v2p-ca9.dtb
retcode=$((${retcode} + $?))
runkernel multi_v7_defconfig vexpress-a9 "" \
	rootfs-armv5.ext2 auto nolocktests::sd:mem128:net,default \
	vexpress-v2p-ca9.dtb
retcode=$((${retcode} + $?))
runkernel multi_v7_defconfig vexpress-a9 "" \
	rootfs-armv5.ext2 auto nolocktests::flash64:mem128:net,default \
	vexpress-v2p-ca9.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig vexpress-a9 "" \
	rootfs-armv5.ext2 auto nolocktests::virtio-blk:mem128:net,default \
	vexpress-v2p-ca9.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig vexpress-a15 "" \
	rootfs-armv7a.ext2 auto nolocktests::sd:mem128:net,default \
	vexpress-v2p-ca15-tc1.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
# Local qemu v2.7+ has minimal support for vexpress-a15-a7
runkernel multi_v7_defconfig vexpress-a15-a7 "" \
	rootfs-armv7a.ext2 auto nolocktests::sd:mem256:net,default \
	vexpress-v2p-ca15_a7.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel multi_v7_defconfig midway "" \
	rootfs-armv7a.cpio auto ::mem2G ecx-2000.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel multi_v7_defconfig sabrelite "" \
	rootfs-armv5.cpio manual ::mem256:net,default imx6dl-sabrelite.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

# For sabrelite, the instatiated mmc device index is linux kernel release
# specific. See upstream kernel patch fa2d0aa96941 ("mmc: core: Allow
# setting slot index via device tree alias") for reason and details.

if [[ ${linux_version_code} -lt $(kernel_version 5 10) ]]; then
    sabrelite_mmc="mmc1"
else
    sabrelite_mmc="mmc3"
fi

runkernel multi_v7_defconfig sabrelite "" \
	rootfs-armv5.ext2 manual "::${sabrelite_mmc}:mem256:net,default" imx6dl-sabrelite.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig sabrelite "" \
	rootfs-armv5.ext2 manual ::usb0:mem256:net,default imx6dl-sabrelite.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig sabrelite "" \
	rootfs-armv5.ext2 manual ::usb1:mem256:net,default imx6dl-sabrelite.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

# Network interface does not come up
#	fec 30bf0000.ethernet eth0: Unable to connect to phy

runkernel multi_v7_defconfig mcimx7d-sabre "" \
	rootfs-armv7a.cpio manual ::mem256 imx7d-sdb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig mcimx7d-sabre "" \
	rootfs-armv7a.ext2 manual ::usb1:mem256 imx7d-sdb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig mcimx7d-sabre "" \
	rootfs-armv7a.ext2 manual ::sd:mem256 imx7d-sdb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

# Network interface does not come up
#	macb e000b000.ethernet eth0: Could not attach PHY (-19)

runkernel multi_v7_defconfig xilinx-zynq-a9 "" \
	rootfs-armv5.cpio auto ::mem128 zynq-zc702.dtb
retcode=$((${retcode} + $?))
runkernel multi_v7_defconfig xilinx-zynq-a9 "" \
	rootfs-armv5.ext2 auto ::usb0:mem128 zynq-zc702.dtb
retcode=$((${retcode} + $?))
runkernel multi_v7_defconfig xilinx-zynq-a9 "" \
	rootfs-armv5.ext2 auto ::sd:mem128 zynq-zc702.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig xilinx-zynq-a9 "" \
	rootfs-armv5.ext2 auto ::sd:mem128 zynq-zc706.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig xilinx-zynq-a9 "" \
	rootfs-armv5.ext2 auto ::usb0:mem128 zynq-zed.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel multi_v7_defconfig cubieboard "" \
	rootfs-armv5.cpio manual ::mem512:net,default sun4i-a10-cubieboard.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig cubieboard "" \
	rootfs-armv5.ext2 manual ::usb:mem512:net,default sun4i-a10-cubieboard.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig cubieboard "" \
	rootfs-armv5.ext2 manual ::sata:mem512:net,default sun4i-a10-cubieboard.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel multi_v7_defconfig raspi2 "" \
	rootfs-armv7a.cpio manual "::net,usb" bcm2836-rpi-2-b.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig raspi2 "" \
	rootfs-armv7a.ext2 manual "::sd:net,usb" bcm2836-rpi-2-b.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel multi_v7_defconfig virt "" \
	rootfs-armv7a.ext2 auto "::virtio-blk:mem512:net,virtio-net-device"
retcode=$((${retcode} + $?))
checkstate ${retcode}

if [ ${runall} -eq 1 ]; then
    # highbank boots with updated (local version of) qemu,
    # but generates warnings to the console due to ignored SMC calls.
    runkernel multi_v7_defconfig highbank cortex-a9 \
	rootfs-armv5.cpio auto ::mem2G highbank.dtb
    retcode=$((${retcode} + $?))
    checkstate ${retcode}
fi

# Driver for built-in network interface is not enabled with multi_v7_defconfig
# Test it below with aspeed_g5_defconfig.
runkernel multi_v7_defconfig ast2600-evb "" \
	rootfs-armv7a.cpio automatic "" aspeed-ast2600-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel multi_v7_defconfig orangepi-pc "" \
	rootfs-armv7a.cpio automatic "::net,nic" sun8i-h3-orangepi-pc.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig orangepi-pc "" \
	rootfs-armv7a.ext2 automatic ::sd:net,nic sun8i-h3-orangepi-pc.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig orangepi-pc "" \
	rootfs-armv7a.ext2 automatic ::usb0:net,nic sun8i-h3-orangepi-pc.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig orangepi-pc "" \
	rootfs-armv7a.ext2 automatic ::usb1:net,nic sun8i-h3-orangepi-pc.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

# serial line input fails for npcm based systems (console output works, though)
# Ethernet interface (gmac) emulation is not supported as of qemu v5.2

runkernel multi_v7_defconfig npcm750-evb "" \
	rootfs-armv5.cpio automatic npcm nuvoton-npcm750-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig npcm750-evb "" \
	rootfs-armv5.ext2 automatic npcm::usb0.1 nuvoton-npcm750-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig quanta-gsj "" \
	rootfs-armv5.cpio automatic npcm nuvoton-npcm730-gsj.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig quanta-gsj "" \
	rootfs-armv5.ext2 automatic npcm::mtd64 nuvoton-npcm730-gsj.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig quanta-gsj "" \
	rootfs-armv5.ext2 automatic npcm::usb0.1 nuvoton-npcm730-gsj.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel exynos_defconfig smdkc210 "" \
	rootfs-armv5.cpio manual cpuidle:nocrypto::mem128 exynos4210-smdkv310.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel exynos_defconfig smdkc210 "" \
	rootfs-armv5.ext2 manual cpuidle:nocrypto::sd2:mem128 exynos4210-smdkv310.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

if [ ${runall} -eq 1 ]; then
    runkernel s5pv210_defconfig smdkc210 "" \
	rootfs-armv5.cpio manual cpuidle:nocrypto::mem128 s5pv210-smdkv210.dtb
    retcode=$((${retcode} + $?))
    checkstate ${retcode}
fi

runkernel realview_defconfig realview-pb-a8 "" \
	rootfs-armv5.cpio auto realview_pb::mem512:net,default arm-realview-pba8.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel realview_defconfig realview-pbx-a9 "" \
	rootfs-armv5.cpio auto realview_pb::net,default arm-realview-pbx-a9.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel realview_defconfig realview-eb cortex-a8 \
	rootfs-armv5.cpio manual realview_eb::mem512:net,default arm-realview-eb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel realview_defconfig realview-eb-mpcore "" \
	rootfs-armv5.cpio manual realview_eb::mem512:net,default \
	arm-realview-eb-11mp-ctrevb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

# disable most test options to avoid running out of memory
runkernel pxa_defconfig akita "" \
	rootfs-armv5.cpio automatic nodebug:nocd:nofs:nonvme:noscsi:notests:novirt:nofdt
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel pxa_defconfig borzoi "" \
	rootfs-armv5.cpio automatic \
	nodebug:nocd:nofs:nonvme:noscsi:notests:novirt:nofdt::net,usb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel pxa_defconfig borzoi "" \
	rootfs-armv5.ext2 automatic \
	nodebug:nocd:nofs:nonvme:noscsi:notests:novirt:nofdt::mmc:net,usb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel pxa_defconfig borzoi "" \
	rootfs-armv5.ext2 automatic \
	nodebug:nocd:nofs:nonvme:noscsi:notests:novirt:nofdt::ata:net,usb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel pxa_defconfig borzoi "" \
	rootfs-armv5.ext2 automatic \
	nodebug:nocd:nofs:nonvme:noscsi:notests:novirt:nofdt::usb:net,usb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel pxa_defconfig mainstone "" \
	rootfs-armv5.cpio automatic \
	nodebug:nocd:nofs:nonvme:noscsi:notests:novirt:nofdt::net,usb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel pxa_defconfig mainstone "" \
	rootfs-armv5.ext2 automatic \
	nodebug:nocd:nofs:nonvme:noscsi:notests:novirt:nofdt::flash32,4352k,2:net,usb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel pxa_defconfig mainstone "" \
	rootfs-armv5.ext2 automatic \
	nodebug:nocd:nofs:nonvme:noscsi:notests:novirt:nofdt::mmc:net,usb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel pxa_defconfig mainstone "" \
	rootfs-armv5.ext2 automatic \
	nodebug:nocd:nofs:nonvme:noscsi:notests:novirt:nofdt::usb:net,usb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel pxa_defconfig spitz "" \
	rootfs-armv5.cpio automatic \
	nodebug:nocd:nofs:nonvme:noscsi:notests:novirt:nofdt::net,usb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel pxa_defconfig spitz "" \
	rootfs-armv5.ext2 automatic \
	nodebug:nocd:nofs:nonvme:noscsi:notests:novirt:nofdt::mmc:net,usb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel pxa_defconfig spitz "" \
	rootfs-armv5.ext2 automatic \
	nodebug:nocd:nofs:nonvme:noscsi:notests:novirt:nofdt::ata:net,usb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel pxa_defconfig spitz "" \
	rootfs-armv5.ext2 automatic \
	nodebug:nocd:nofs:nonvme:noscsi:notests:novirt:nofdt::usb:net,usb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel pxa_defconfig terrier "" \
	rootfs-armv5.cpio automatic \
	nodebug:nocd:nofs:nonvme:noscsi:notests:novirt:nofdt::net,usb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel pxa_defconfig terrier "" \
	rootfs-armv5.ext2 automatic \
	nodebug:nocd:nofs:nonvme:noscsi:notests:novirt:nofdt::mmc:net,usb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel pxa_defconfig terrier "" \
	rootfs-armv5.ext2 automatic \
	nodebug:nocd:nofs:nonvme:noscsi:notests:novirt:nofdt::ata:net,usb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel pxa_defconfig terrier "" \
	rootfs-armv5.ext2 automatic \
	nodebug:nocd:nofs:nonvme:noscsi:notests:novirt:nofdt::usb:net,usb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel pxa_defconfig tosa "" \
	rootfs-armv5.cpio automatic nodebug:nocd:nofs:nonvme:noscsi:notests:novirt:nofdt
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel pxa_defconfig tosa "" \
	rootfs-armv5.ext2 automatic nodebug:nocd:nofs:nonvme:noscsi:notests:novirt:nofdt::ata
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel pxa_defconfig z2 "" \
	rootfs-armv5.cpio automatic nodebug:nocd:nofs:nonvme:noscsi:notests:novirt:nofdt
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel pxa_defconfig z2 "" \
	rootfs-armv5.sqf automatic nodebug:nocd:nofs:nonvme:noscsi:notests:novirt:nofdt::flash8,384k,2
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel pxa_defconfig z2 "" \
	rootfs-armv5.ext2 automatic nodebug:nocd:nofs:nonvme:noscsi:notests:novirt:nofdt::mmc
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel collie_defconfig collie "" \
	rootfs-sa110.cpio manual aeabi:notests
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel integrator_defconfig integratorcp "" \
	rootfs-armv5.cpio automatic ::mem128:net,default integratorcp.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel integrator_defconfig integratorcp "" \
	rootfs-armv5.ext2 automatic ::mem128:sd:net,default integratorcp.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g4_defconfig palmetto-bmc "" \
	rootfs-armv5.cpio automatic "::net,nic" aspeed-bmc-opp-palmetto.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g4_defconfig palmetto-bmc "" \
	rootfs-armv5.ext2 automatic "::mtd32:net,nic" aspeed-bmc-opp-palmetto.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

# selftests sometimes hang with soft CPU lockup
runkernel aspeed_g5_defconfig witherspoon-bmc "" \
	rootfs-armv5.cpio automatic notests::net,nic aspeed-bmc-opp-witherspoon.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig witherspoon-bmc "" \
	rootfs-armv5.ext2 automatic notests::mtd32:net,nic aspeed-bmc-opp-witherspoon.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g5_defconfig ast2500-evb "" \
	rootfs-armv5.cpio automatic notests::net,nic aspeed-ast2500-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig ast2500-evb "" \
	rootfs-armv5.ext2 automatic notests::sd:net,nic aspeed-ast2500-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig ast2500-evb "" \
	rootfs-armv5.ext2 automatic notests::mtd32:net,nic aspeed-ast2500-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig ast2500-evb "" \
	rootfs-armv5.ext2 automatic notests::usb:net,nic aspeed-ast2500-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g5_defconfig ast2600-evb "" \
	rootfs-armv5.cpio automatic notests::net,nic aspeed-ast2600-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
# Repeat with armv7a root file system.
# Both are expected to work.
runkernel aspeed_g5_defconfig ast2600-evb "" \
	rootfs-armv7a.cpio automatic notests::net,nic aspeed-ast2600-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig ast2600-evb "" \
	rootfs-armv5.ext2 automatic notests::sd2:net,nic aspeed-ast2600-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

if [ ${runall} -eq 1 ]; then
    # SPI (NOR) Flash doesn't instantiate on ast2600-evb
    # because drivers/mtd/spi-nor/aspeed-smc.c doesn't have a 'compatible'
    # entry for aspeed,ast2600-fmc or aspeed,ast2600-spi.
    runkernel aspeed_g5_defconfig ast2600-evb "" \
	rootfs-armv7a.ext2 automatic notests::mtd64 aspeed-ast2600-evb.dtb
    retcode=$((${retcode} + $?))
    checkstate ${retcode}
fi

runkernel aspeed_g5_defconfig romulus-bmc "" \
	rootfs-armv5.cpio automatic notests::net,nic aspeed-bmc-opp-romulus.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig romulus-bmc "" \
	rootfs-armv5.ext2 automatic notests::mtd32:net,nic aspeed-bmc-opp-romulus.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g5_defconfig swift-bmc "" \
	rootfs-armv5.cpio automatic notests::net,nic aspeed-bmc-opp-swift.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig swift-bmc "" \
	rootfs-armv5.ext2 automatic notests::sd1:net,nic aspeed-bmc-opp-swift.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig swift-bmc "" \
	rootfs-armv5.ext2 automatic notests::mmc:net,nic aspeed-bmc-opp-swift.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig swift-bmc "" \
	rootfs-armv5.ext2 automatic notests::mtd128:net,nic aspeed-bmc-opp-swift.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g5_defconfig g220a-bmc "" \
	rootfs-armv5.cpio automatic notests::net,nic aspeed-bmc-bytedance-g220a.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig g220a-bmc "" \
	rootfs-armv5.ext2 automatic notests::mtd128:net,nic aspeed-bmc-bytedance-g220a.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g5_defconfig tacoma-bmc "" \
	rootfs-armv5.cpio automatic notests::net,nic aspeed-bmc-opp-tacoma.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g5_defconfig tacoma-bmc "" \
	rootfs-armv5.ext2 automatic notests::mmc:net,nic aspeed-bmc-opp-tacoma.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel qemu_sx1_defconfig sx1 "" rootfs-armv4.cpio automatic "nonet"
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel qemu_sx1_defconfig sx1 "" rootfs-armv4.ext2 automatic "nonet::sd"
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel qemu_sx1_defconfig sx1 "" rootfs-armv4.sqf automatic "nonet::flash32,26,3"
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel mps2_defconfig "mps2-an385" "cortex-m3" \
	rootfs-arm-m3.cpio manual "" mps2-an385.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

if [ ${runall} -eq 1 ]; then
    # Generates runtime warning "sunxi_musb_ep_offset called with non 0 offset"
    # which may be caused by qemu. The call originates from ep_config_from_hw(),
    # which calls musb_read_fifosize(), which in turn calls the function
    # with parameter MUSB_FIFOSIZE=0x0f.
    runkernel sunxi_defconfig cubieboard "" \
	rootfs-armv5.cpio manual ::mem512 sun4i-a10-cubieboard.dtb
    retcode=$((${retcode} + $?))
    checkstate ${retcode}
fi

exit ${retcode}
