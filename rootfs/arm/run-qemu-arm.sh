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

PREFIX_A="arm-linux-gnueabi-"
PREFIX_M3="arm-linux-"

# integratorcp does not boot in v5.4.y when using gcc 10.3.0/11.2.0/11.3.0
PATH_ARM="/opt/kernel/gcc-9.4.0-nolibc/arm-linux-gnueabi/bin"
# PATH_ARM="/opt/kernel/${DEFAULT_CC}/arm-linux-gnueabi/bin"
# Cortex-M3 (thumb) needs binutils 2.28 or earlier
PATH_ARM_M3=/opt/kernel/arm-m3/gcc-7.3.0/bin

PATH=${PATH_ARM}:${PATH_ARM_M3}:${PATH}

skip_414="arm:versatilepb:versatile_defconfig:aeabi:pci:flash64:mem128:net,default"

patch_defconfig()
{
    local defconfig=$1
    local fixups=${2//:/ }
    local fixup

    # Disable Bluetooth and wireless. We won't ever use or test it.
    disable_config "${defconfig}" CONFIG_BT CONFIG_WLAN CONFIG_WIRELESS

    # Always enable ...
    enable_config "${defconfig}" CONFIG_DEVTMPFS CONFIG_DEVTMPFS_MOUNT CONFIG_BLK_DEV_INITRD

    # Options needed to be built into the kernel for device support
    # on pxa devices
    # MTD, squashfs
    enable_config_cond "${defconfig}" CONFIG_MTD_BLOCK CONFIG_MTD_PXA2XX CONFIG_SQUASHFS
    # MMC
    enable_config_cond "${defconfig}" CONFIG_MMC_BLOCK CONFIG_MMC_PXA
    # PCMCIA
    enable_config_cond "${defconfig}" CONFIG_ATA CONFIG_BLK_DEV_SD CONFIG_PCCARD
    enable_config_cond "${defconfig}" CONFIG_PCMCIA CONFIG_PATA_PCMCIA CONFIG_PCMCIA_PXA2XX
    # USB
    enable_config_cond "${defconfig}" CONFIG_USB CONFIG_USB_STORAGE CONFIG_USB_OHCI_HCD CONFIG_USB_OHCI_HCD_PXA27X
    # NAND (spitz)
    # Doesn't work as-is; it looks like NAND images need to be
    # specially prepared.
    # enable_config_cond "${defconfig}" CONFIG_MTD_RAW_NAND CONFIG_MTD_NAND_SHARPSL

    # Always build PXA watchdog into kernel if enabled
    enable_config_cond "${defconfig}" CONFIG_SA1100_WATCHDOG

    # Build CONFIG_NOP_USB_XCEIV into kernel if enabled
    # Needed for xilinx-zynq-a9 usb boot (and possibly others).
    enable_config_cond "${defconfig}" CONFIG_NOP_USB_XCEIV

    # Enable GPIO_MXC if supported, and build into kernel
    # See upstream kernel commit 12d16b397ce0 ("gpio: mxc: Support module build")
    enable_config_supported "${defconfig}" CONFIG_GPIO_MXC

    for fixup in ${fixups}; do
	case "${fixup}" in
	nofdt)
	    disable_config "${defconfig}" CONFIG_MACH_PXA27X_DT CONFIG_MACH_PXA3XX_DT
	    ;;
	aeabi)
	    enable_config "${defconfig}" CONFIG_AEABI
	    ;;
	pci)
	    enable_config "${defconfig}" CONFIG_PCI CONFIG_PCI_VERSATILE
	    enable_config "${defconfig}" CONFIG_OF CONFIG_OF_PCI CONFIG_OF_PCI_IRQ
	    ;;
	scsi)
	    enable_config "${defconfig}" CONFIG_SCSI CONFIG_SCSI_SYM53C8XX_2 CONFIG_BLK_DEV_SD
	    ;;
	cpuidle)
	    # CPUIDLE causes Exynos targets to run really slow
	    disable_config "${defconfig}" CONFIG_CPU_IDLE CONFIG_ARM_EXYNOS_CPUIDLE
	    ;;
	nonand)
	    # For imx25, disable NAND (not supported as of qemu 2.5, causes
	    # a runtime warning).
	    disable_config "${defconfig}" CONFIG_MTD_NAND_MXC
	    ;;
	nodrm)
	    # qemu does not support CONFIG_DRM_IMX. This starts to fail
	    # with commit 5f2f911578fb (drm/imx: atomic phase 3 step 1:
	    # Use atomic configuration), ie since v4.8. Impact is long boot delay
	    # (kernel needs 70+ seconds to boot) and several kernel tracebacks
	    # in drm code.
	    # It also does not support CONFIG_DRM_MXSFB; trying to enable it
	    # crashes the kernel when running mcimx6ul-evk.
	    disable_config "${defconfig}" CONFIG_DRM_MXSFB CONFIG_DRM_IMX
	    ;;
	nocrypto)
	    # Broken (hangs) for some platforms
	    enable_config "${defconfig}" CONFIG_CRYPTO_MANAGER_DISABLE_TESTS
	    ;;
	realview_eb)
	    # Older versions of realview config files need additional CPU support.
	    enable_config "${defconfig}" CONFIG_REALVIEW_EB_A9MP CONFIG_REALVIEW_EB_ARM11MP_REVB
	    enable_config "${defconfig}" CONFIG_MACH_REALVIEW_PBX CONFIG_MACH_REALVIEW_PB1176
	    # KFENCE results in a warning with realview-eb-mpcore.
	    disable_config "${defconfig}" CONFIG_KFENCE
	    ;;
	realview_pb)
	    # Similar for PB-A8. Also disable some EB and incompatible PB
	    # configurations.
	    disable_config "${defconfig}" CONFIG_REALVIEW_EB_A9MP CONFIG_REALVIEW_EB_ARM11MP
	    disable_config "${defconfig}" CONFIG_MACH_REALVIEW_PB11MP CONFIG_MACH_REALVIEW_PB1176
	    enable_config "${defconfig}" CONFIG_MACH_REALVIEW_PBX CONFIG_MACH_REALVIEW_PBA8
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
    local dtbfile=""
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

    if ! dosetup -F "${fixup}" -c "${defconfig}${fixup%::*}" "${rootfs}" "${defconfig}"; then
	if [[ __dosetup_rc -eq 2 ]]; then
	    return 0
	fi
	return 1
    fi

    # If a dtb file was specified but does not exist, skip the build.
    local dtbcmd=""
    if [[ -n "${dtb}" ]]; then
	dtbfile="$(find arch/arm/boot/dts -name "${dtb}")"
	if [[ -z "${dtbfile}" ]]; then
	    echo "skipped (dtb)"
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
    "akita" | "borzoi" | "spitz" | "terrier")
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
    "smdkc210")
	initcli+=" console=ttySAC0,115200n8"
	initcli+=" earlycon=exynos4210,mmio32,0x13800000,115200n8"
	;;
    "realview-pb-a8" | "realview-pbx-a9" | \
    "realview-eb-mpcore" | "realview-eb" | \
    "versatileab" | "versatilepb" | \
    "integratorcp")
	initcli+=" console=ttyAMA0,115200 earlycon"
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

echo "Build reference: $(git describe --match 'v*')"
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
