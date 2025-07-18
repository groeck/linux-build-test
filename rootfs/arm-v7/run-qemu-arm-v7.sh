#!/bin/bash

progdir=$(cd $(dirname $0); pwd)
. ${progdir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-arm}

machine=$1
config=$2
options=$3
devtree=$4
boot=$5

ARCH=arm

PREFIX="arm-linux-gnueabi-"

PATH_ARM="/opt/kernel/${DEFAULT_CC}/arm-linux-gnueabi/bin"

PATH=${PATH_ARM}:${PATH}

skip_419="arm:bpim2u:sunxi_defconfig:sata:net=nic \
	arm:npcm750-evb:multi_v7_defconfig:npcm:mtd32,6,5:net=nic,npcm-gmac \
	arm:npcm750-evb:multi_v7_defconfig:npcm:usb0.1:net=nic,npcm-gmac \
	arm:npcm750-evb:multi_v7_defconfig:npcm:net=nic,npcm-gmac \
	arm:sabrelite,spi-model=sst25vf032b:multi_v7_defconfig:mtd4:mem256:net=default \
	arm:vexpress-a9:multi_v7_defconfig:nolocktests:flash64:mem128:net=default"
skip_54="arm:npcm750-evb:multi_v7_defconfig:npcm:mtd32,6,5:net=nic,npcm-gmac \
	arm:npcm750-evb:multi_v7_defconfig:npcm:usb0.1:net=nic,npcm-gmac \
	arm:npcm750-evb:multi_v7_defconfig:npcm:net=nic,npcm-gmac"
skip_510="arm:npcm750-evb:multi_v7_defconfig:npcm:mtd32,6,5:net=nic,npcm-gmac \
	arm:npcm750-evb:multi_v7_defconfig:npcm:usb0.1:net=nic,npcm-gmac \
	arm:npcm750-evb:multi_v7_defconfig:npcm:net=nic,npcm-gmac"

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
    echo "CONFIG_DYNAMIC_DEBUG=y" >> ${defconfig}

    echo "CONFIG_CRAMFS=y" >> ${defconfig}

    # TPM
    echo "CONFIG_TCG_TPM=y" >> ${defconfig}
    echo "CONFIG_TCG_TIS=y" >> ${defconfig}

    # MMC
    sed -i -e 's/CONFIG_MMC_BLOCK=m/CONFIG_MMC_BLOCK=y/' ${defconfig}
    # PCMCIA
    sed -i -e 's/CONFIG_ATA=m/CONFIG_ATA=y/' ${defconfig}
    sed -i -e 's/CONFIG_BLK_DEV_SD=m/CONFIG_BLK_DEV_SD=y/' ${defconfig}
    sed -i -e 's/CONFIG_PCCARD=m/CONFIG_PCCARD=y/' ${defconfig}
    sed -i -e 's/CONFIG_PCMCIA=m/CONFIG_PCMCIA=y/' ${defconfig}
    sed -i -e 's/CONFIG_PATA_PCMCIA=m/CONFIG_PATA_PCMCIA=y/' ${defconfig}
    # USB
    sed -i -e 's/CONFIG_USB=m/CONFIG_USB=y/' ${defconfig}
    sed -i -e 's/CONFIG_USB_STORAGE=m/CONFIG_USB_STORAGE=y/' ${defconfig}
    sed -i -e 's/CONFIG_USB_OHCI_HCD=m/CONFIG_USB_OHCI_HCD=y/' ${defconfig}

    # Build CONFIG_NOP_USB_XCEIV into kernel if enabled
    # Needed for xilinx-zynq-a9 usb boot (and possibly others).
    sed -i -e 's/CONFIG_NOP_USB_XCEIV=m/CONFIG_NOP_USB_XCEIV=y/' ${defconfig}

    # Enable GPIO_MXC if supported, and build into kernel
    # See upstream kernel commit 12d16b397ce0 ("gpio: mxc: Support module build")
    if grep -F -q CONFIG_GPIO_MXC ${defconfig}; then
	echo "CONFIG_GPIO_MXC=y" >> ${defconfig}
    fi

    # Enable SPI controller for sabrelite and other IMX boards
    enable_config ${defconfig} CONFIG_SPI_IMX
    enable_config ${defconfig} CONFIG_IMX_SDMA

    # KFENCE results in useless warnings
    disable_config "${defconfig}" CONFIG_KFENCE

    # Does not work as of qemu v8.0 due to DMA error.
    # Disable if enabled to avoid warning backtrace.
    disable_config "${defconfig}" CONFIG_CRYPTO_DEV_SUN8I_CE

    for fixup in ${fixups}; do
	case "${fixup}" in
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
    local bmach="${mach%%,*}"	# basic machine, without machine options
    local cpu=$3
    local rootfs=$4
    local mode=$5
    local fixup=$6
    local dtb=$7
    local ddtb="${dtb%.dtb}"
    local dtbfile=""
    local nonet=0
    local waitlist=("Restarting" "Boot successful" "Rebooting")
    local build="${ARCH}:${mach}:${defconfig}${fixup:+:${fixup}}"
    local pbuild="${build}${dtb:+:${dtb%.dtb}}"

    local _boot
    if [[ "${rootfs}" == *cpio ]]; then
	pbuild+=":initrd"
	_boot="initrd"
    else
	pbuild+=":${rootfs##*.}"
	_boot="rootfs"
    fi

    pbuild="${pbuild//+(:)/:}"
    build="${build//+(:)/:}"

    if ! match_params "${machine}@${bmach}" "${config}@${defconfig}" "${options}@${fixup}" "${devtree}@${ddtb}" "${boot}@${_boot}"; then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    echo -n "Building ${pbuild} ... "

    if ! checkskip "${build}" ; then
	return 0
    fi

    if [[ "${nonet}" -ne 0 ]]; then
	fixup="$(echo ${fixup} | sed -e 's/:\+net=nic//')"
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
	dtbfile="$(__findfile "arch/arm/boot/dts" "${dtb}")"
	if [[ -z "${dtbfile}" ]]; then
	    echo "skipped (dtb)"
	    return 0
	fi
	dtbcmd="-dtb ${dtbfile}"
    fi

    rootfs="$(rootfsname ${rootfs})"

    kernel="arch/arm/boot/zImage"
    case ${bmach} in
    "bpim2u")
	initcli+=" console=ttyS0,115200"
	initcli+=" earlycon=uart8250,mmio32,0x1c28000,115200n8"
	;;
    "orangepi-pc")
	initcli+=" console=ttyS0,115200"
	initcli+=" earlycon=uart8250,mmio32,0x1c28000,115200n8"
	extra_params+=" -nodefaults"
	;;
    "npcm750-evb" | "quanta-gsj" | "kudo-bmc")
	initcli+=" console=ttyS3,115200"
	initcli+=" earlycon=uart8250,mmio32,0xf0004000,115200n8"
	extra_params+=" -nodefaults -serial null -serial null -serial null"
	;;
    "mori-bmc")
	initcli+=" console=ttyS3,115200"
	initcli+=" earlycon=uart8250,mmio32,0xf0004000,115200n8"
	extra_params+=" -nodefaults -serial null -serial null -serial null"
	;;
    "cubieboard")
	initcli+=" earlycon=uart8250,mmio32,0x1c28000,115200n8"
	initcli+=" console=ttyS0"
	;;
    "raspi2b")
	initcli+=" earlycon=pl011,0x3f201000"
	initcli+=" console=ttyAMA0"
	;;
    sabrelite* | "mcimx6ul-evk")
	initcli+=" earlycon=ec_imx6q,mmio,0x21e8000,115200n8"
	initcli+=" console=ttymxc1,115200"
	extra_params+=" -display none -serial null"
	;;
    "mcimx7d-sabre")
	initcli+=" earlycon=ec_imx6q,mmio,0x30860000,115200n8"
	initcli+=" console=ttymxc0,115200"
	extra_params+=" -display none"
	;;
    "virt" | \
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
        ${QEMU} -M ${mach} \
	    ${cpu:+-cpu ${cpu}} \
	    -kernel ${kernel} \
	    -no-reboot \
	    ${extra_params} \
	    ${initcli:+--append "${initcli} ${extracli}"} \
	    ${dtbcmd} \
	    -nographic -monitor null -serial stdio

    return $?
}

build_reference "${PREFIX}gcc" "${QEMU}"

# Ethernet needs double net=nic (double '-nic user') to work.
runkernel imx_v6_v7_defconfig mcimx6ul-evk "" \
	rootfs-armv7a.cpio manual nodrm::mem256:net=nic:net=nic imx6ul-14x14-evk.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel imx_v6_v7_defconfig mcimx6ul-evk "" \
	rootfs-armv7a.ext2 manual nodrm::sd:mem256:net=nic:net=nic imx6ul-14x14-evk.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel imx_v6_v7_defconfig mcimx6ul-evk "" \
	rootfs-armv7a.ext2 manual nodrm::usb0:mem256:net=nic:net=nic imx6ul-14x14-evk.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel imx_v6_v7_defconfig mcimx6ul-evk "" \
	rootfs-armv7a.ext2 manual nodrm::usb1:mem256:net=nic:net=nic imx6ul-14x14-evk.dtb
retcode=$((retcode + $?))
checkstate ${retcode}

runkernel imx_v6_v7_defconfig mcimx7d-sabre "" \
	rootfs-armv7a.cpio manual nodrm::smp2:mem256:net=nic imx7d-sdb.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel imx_v6_v7_defconfig mcimx7d-sabre "" \
	rootfs-armv7a.ext2 manual nodrm::smp2:usb1:mem256:net=nic imx7d-sdb.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel imx_v6_v7_defconfig mcimx7d-sabre "" \
	rootfs-armv7a.ext2 manual nodrm::smp2:sd:mem256:net=nic imx7d-sdb.dtb
retcode=$((retcode + $?))
checkstate ${retcode}

# A second Ethernet interface can be enabled with something like
#	-netdev user,id=net0 -netdev hubport,hubid=0,id=h1,netdev=net0 \
#	-netdev hubport,hubid=0,id=h2 -net nic,netdev=h2 \
#	-netdev hubport,hubid=0,id=h3 -device virtio-net-pci,netdev=h3
# added to the command line.
# Note that the virtual PCIe device is only instantiated in qemu v10.0.

runkernel imx_v6_v7_defconfig sabrelite "" \
	rootfs-armv5.cpio manual nodrm::mem256:net=default imx6dl-sabrelite.dtb
retcode=$((retcode + $?))
checkstate ${retcode}

runkernel imx_v6_v7_defconfig "sabrelite,spi-model=sst25vf032b" "" \
	rootfs-armv5.sqf manual nodrm::mtd4:mem256:net=default imx6dl-sabrelite.dtb
retcode=$((retcode + $?))
checkstate ${retcode}

# For sabrelite, the instatiated mmc device index is linux kernel release
# specific. See upstream kernel patch fa2d0aa96941 ("mmc: core: Allow
# setting slot index via device tree alias") for reason and details.
# On top of that, there is commit 2a43322ca7f3 ("ARM: dts: imx6qdl-sabre:
# Add mmc aliases") after v6.1. This changes the alias back from mmc3 to
# mmc1, just to make things even more complicated.
# We could try to determine the actual mmc device, but it turns out
# that Linux also supports providing raw device references. Use "b300"
# as root device becasue that is known to work everywhere.
# Also see bpim2u below, which has the same problem.

runkernel imx_v6_v7_defconfig sabrelite "" \
	rootfs-armv5.ext2 manual "nodrm::mmc,b300:mem256:net=default" imx6dl-sabrelite.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel imx_v6_v7_defconfig sabrelite "" \
	rootfs-armv5.ext2 manual nodrm::usb0:mem256:net=default imx6dl-sabrelite.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel imx_v6_v7_defconfig sabrelite "" \
	rootfs-armv5.ext2 manual nodrm::usb1:mem256:net=default imx6dl-sabrelite.dtb
retcode=$((retcode + $?))
checkstate ${retcode}

# vexpress tests generate a warning during reboot if CONFIG_PROVE_RCU is enabled
runkernel multi_v7_defconfig vexpress-a9 "" \
	rootfs-armv5.cpio auto nolocktests::mem128:net=default \
	vexpress-v2p-ca9.dtb
retcode=$((retcode + $?))
runkernel multi_v7_defconfig vexpress-a9 "" \
	rootfs-armv5.ext2 auto nolocktests::sd:mem128:net=default \
	vexpress-v2p-ca9.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig vexpress-a9 "" \
	rootfs-armv5.ext2 auto nolocktests::flash64:mem128:net=default \
	vexpress-v2p-ca9.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig vexpress-a9 "" \
	rootfs-armv5.ext2 auto nolocktests::virtio-blk:mem128:net=default \
	vexpress-v2p-ca9.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig vexpress-a15 "" \
	rootfs-armv7a.ext2 auto nolocktests::sd:mem128:net=default \
	vexpress-v2p-ca15-tc1.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
# Local qemu v2.7+ has minimal support for vexpress-a15-a7
runkernel multi_v7_defconfig vexpress-a15-a7 "" \
	rootfs-armv7a.ext2 auto nolocktests::sd:mem256:net=default \
	vexpress-v2p-ca15_a7.dtb
retcode=$((retcode + $?))
checkstate ${retcode}

runkernel multi_v7_defconfig xilinx-zynq-a9 "" \
	rootfs-armv5.cpio auto ::mem128:net=default zynq-zc702.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig xilinx-zynq-a9 "" \
	rootfs-armv5.ext2 auto ::usb0:mem128:net=default zynq-zc702.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig xilinx-zynq-a9 "" \
	rootfs-armv5.ext2 auto ::sd:mem128:net=default zynq-zc702.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig xilinx-zynq-a9 "" \
	rootfs-armv5.ext2 auto ::sd:mem128:net=default zynq-zc706.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
# zynq-zed.dtb expects PHY address 0. The xilinx-zynq-a9 machine
# configures PHY address 7. This results in the following error
# message.
#	macb e000b000.ethernet eth0: Could not attach PHY (-19)
# We already tested the Ethernet interface for this machine above,
# so it is ok to skip network interface tests here.
runkernel multi_v7_defconfig xilinx-zynq-a9 "" \
	rootfs-armv5.ext2 auto ::usb0:mem128 zynq-zed.dtb
retcode=$((retcode + $?))
checkstate ${retcode}

runkernel multi_v7_defconfig cubieboard "" \
	rootfs-armv5.cpio manual ::mem512:net=default sun4i-a10-cubieboard.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
# EHCI
runkernel multi_v7_defconfig cubieboard "" \
	rootfs-armv5.ext2 manual ::usb0:mem512:net=default sun4i-a10-cubieboard.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
# OHCI through USB hub on 2nd USB port
runkernel multi_v7_defconfig cubieboard "" \
	rootfs-armv5.ext2 manual ::usb-hub1:mem512:net=default sun4i-a10-cubieboard.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig cubieboard "" \
	rootfs-armv5.ext2 manual ::sata:mem512:net=default sun4i-a10-cubieboard.dtb
retcode=$((retcode + $?))
checkstate ${retcode}

runkernel multi_v7_defconfig raspi2b "" \
	rootfs-armv7a.cpio manual "::net=usb" bcm2836-rpi-2-b.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig raspi2b "" \
	rootfs-armv7a.ext2 manual "::sd:net=usb" bcm2836-rpi-2-b.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
# OHCI
# Note: Linux always instantiates a USB 1.1 hub on top of the single-port
# DWC2 USB port. It appears that raspi2 does not support USB 2.0.
runkernel multi_v7_defconfig raspi2b "" \
	rootfs-armv7a.ext2 manual "::usb0:nonet" bcm2836-rpi-2-b.dtb
retcode=$((retcode + $?))
checkstate ${retcode}

runkernel multi_v7_defconfig virt "" \
	rootfs-armv7a.ext2 auto "::virtio-blk:mem512:net=virtio-net-device"
retcode=$((retcode + $?))
checkstate ${retcode}

runkernel multi_v7_defconfig virt "" \
	rootfs-armv7a.ext2 auto "::efi32:virtio-blk:mem512:net=virtio-net-device"
retcode=$((retcode + $?))
checkstate ${retcode}

runkernel multi_v7_defconfig virt "" \
	rootfs-armv7a.ext2 auto "::tpm-tis-device:virtio-blk:mem512:net=virtio-net-device"
retcode=$((retcode + $?))
checkstate ${retcode}

runkernel multi_v7_defconfig virt "" \
	rootfs-armv7a.ext2 auto "::tpm-tis-device:efi32:virtio-blk:mem512:net=virtio-net-device"
retcode=$((retcode + $?))
checkstate ${retcode}

runkernel multi_v7_defconfig orangepi-pc "" \
	rootfs-armv7a.cpio automatic "::net=nic" sun8i-h3-orangepi-pc.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig orangepi-pc "" \
	rootfs-armv7a.ext2 automatic ::sd:net=nic sun8i-h3-orangepi-pc.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
# EHCI
runkernel multi_v7_defconfig orangepi-pc "" \
	rootfs-armv7a.ext2 automatic ::usb0:net=nic sun8i-h3-orangepi-pc.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
# OHCI (assumes that there is no companion interface in qemu)
runkernel multi_v7_defconfig orangepi-pc "" \
	rootfs-armv7a.ext2 automatic ::usb4:net=nic sun8i-h3-orangepi-pc.dtb
retcode=$((retcode + $?))
checkstate ${retcode}

# serial line input fails sporadically for npcm based systems (console output
# works, though)
# Ethernet interface (emc, gmac) emulation is not supported as of qemu
# v5.2. emc is supposed to work with qemu 6.0, but I have not been able
# to figure out how to make it work (it looks like the upstream Linux kernel
# doesn't support it).

runkernel multi_v7_defconfig npcm750-evb "" \
	rootfs-armv5.cpio automatic npcm::net=nic,npcm-gmac nuvoton-npcm750-evb.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig npcm750-evb "" \
	rootfs-armv5.sqf automatic npcm::mtd32,6,5:net=nic,npcm-gmac nuvoton-npcm750-evb.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig npcm750-evb "" \
	rootfs-armv5.ext2 automatic npcm::usb0.1:net=nic,npcm-gmac nuvoton-npcm750-evb.dtb
retcode=$((retcode + $?))
checkstate ${retcode}

runkernel multi_v7_defconfig quanta-gsj "" \
	rootfs-armv5.cpio automatic npcm::net=nic,npcm-gmac nuvoton-npcm730-gsj.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig quanta-gsj,spi-model=n25q256a13 "" \
	rootfs-armv5.ext2 automatic npcm::mtd32:net=nic,npcm-gmac nuvoton-npcm730-gsj.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig quanta-gsj "" \
	rootfs-armv5.ext2 automatic npcm::usb0.1:net=nic,npcm-gmac nuvoton-npcm730-gsj.dtb
retcode=$((retcode + $?))
checkstate ${retcode}

runkernel multi_v7_defconfig kudo-bmc "" \
	rootfs-armv5.cpio automatic npcm::net=nic,npcm-gmac nuvoton-npcm730-kudo.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
if [ ${runall} -eq 1 ]; then
    # kernel support for sdhci missing in upstream kernel (as of v6.3-rc1)
    runkernel multi_v7_defconfig kudo-bmc "" \
	rootfs-armv5.ext2 automatic npcm::sd:net=nic,npcm-gmac nuvoton-npcm730-kudo.dtb
    retcode=$((retcode + $?))
    checkstate ${retcode}
fi
runkernel multi_v7_defconfig kudo-bmc,spi-model=n25q512a13 "" \
	rootfs-armv7a.cramfs automatic npcm::mtd64,8,3:net=nic,npcm-gmac nuvoton-npcm730-kudo.dtb
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig kudo-bmc "" \
	rootfs-armv5.ext2 automatic npcm::usb0.1:net=nic,npcm-gmac nuvoton-npcm730-kudo.dtb
retcode=$((retcode + $?))
checkstate ${retcode}

runkernel sunxi_defconfig bpim2u "" \
	rootfs-armv7a.cpio automatic "::net=nic" sun8i-r40-bananapi-m2-ultra.dtb
checkstate ${retcode}
# sd card association is not fixed (randomly instantiated as mmc0, mmc1,
# or mmc2)
# The following change in sun8i-r40-bananapi-m2-ultra.dts appears to fix
# the problem.
# diff --git a/arch/arm/boot/dts/sun8i-r40-bananapi-m2-ultra.dts b/arch/arm/boot/dts/sun8i-r40-bananapi-m2-ultra.dts
# index 28197bbcb1d5..475183ab9bf5 100644
# --- a/arch/arm/boot/dts/sun8i-r40-bananapi-m2-ultra.dts
# +++ b/arch/arm/boot/dts/sun8i-r40-bananapi-m2-ultra.dts
# @@ -54,6 +54,9 @@ / {
#         aliases {
#                 ethernet0 = &gmac;
#                 serial0 = &uart0;
# +               mmc0 = &mmc0;
# +               mmc1 = &mmc1;
# +               mmc2 = &mmc2;
#         };
# No idea if that would be acceptable in the upstream kernel. Also see mmc
# comments for sabrelite above for more details.
# Alternatively, we can specify the block device number (b300) as root device.
# See qemu patch 7ea47af390 ("tests/avocado: Make the test_arm_bpim2u_gmac
# test more reliable") for details. That is hackish, but it works.
runkernel sunxi_defconfig bpim2u "" \
	rootfs-armv7a.ext2 automatic "::sd0,b300:net=nic" sun8i-r40-bananapi-m2-ultra.dtb
checkstate ${retcode}
runkernel sunxi_defconfig bpim2u "" \
	rootfs-armv7a.ext2 automatic "::sd1,b300:net=nic" sun8i-r40-bananapi-m2-ultra.dtb
checkstate ${retcode}
runkernel sunxi_defconfig bpim2u "" \
	rootfs-armv7a.ext2 automatic "::sata:net=nic" sun8i-r40-bananapi-m2-ultra.dtb
checkstate ${retcode}
# EHCI
runkernel sunxi_defconfig bpim2u "" \
	rootfs-armv7a.ext2 automatic "::usb0:net=nic" sun8i-r40-bananapi-m2-ultra.dtb
checkstate ${retcode}

exit ${retcode}
