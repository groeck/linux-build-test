#!/bin/bash

progdir=$(cd $(dirname $0); pwd)
. ${progdir}/../scripts/config.sh
. ${progdir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

QEMU_LINARO=${QEMU:-${QEMU_LINARO_BIN}/qemu-system-arm}
QEMU_MICRO=${QEMU:-${QEMU_V31_BIN}/qemu-system-arm}
QEMU_SMDKC=${QEMU:-${QEMU_V28_BIN}/qemu-system-arm}
QEMU=${QEMU:-${QEMU_BIN}/qemu-system-arm}

machine=$1
config=$2
devtree=$3

ARCH=arm

PREFIX_A="arm-linux-gnueabi-"
PREFIX_M3="arm-linux-"

PATH_ARM="/opt/kernel/gcc-7.3.0-nolibc/arm-linux-gnueabi/bin"
# Cortex-M3 (thumb) needs binutils 2.28 or earlier
PATH_ARM_M3=/opt/kernel/arm-m3/gcc-7.3.0/bin

PATH=${PATH_ARM}:${PATH_ARM_M3}:${PATH}

skip_316="arm:mcimx6ul-evk:imx_v6_v7_defconfig \
	arm:raspi2:multi_v7_defconfig \
	arm:virt:multi_v7_defconfig \
	arm:realview-pbx-a9:realview_defconfig"
skip_318="arm:mcimx6ul-evk:imx_v6_v7_defconfig \
	arm:raspi2:multi_v7_defconfig \
	arm:virt:multi_v7_defconfig \
	arm:realview-pbx-a9:realview_defconfig"
skip_44="arm:raspi2:multi_v7_defconfig \
	arm:virt:multi_v7_defconfig \
	arm:realview-pbx-a9:realview_defconfig"
skip_49="arm:ast2500-evb:aspeed_g5_defconfig \
	arm:mcimx6ul-evk:imx_v6_v7_defconfig \
	arm:palmetto-bmc:aspeed_g4_defconfig \
	arm:romulus-bmc:aspeed_g5_defconfig \
	arm:witherspoon-bmc:aspeed_g5_defconfig"
skip_414="arm:witherspoon-bmc:aspeed_g5_defconfig"

. ${progdir}/../scripts/common.sh

patch_defconfig()
{
    local defconfig=$1
    local fixups=${2//:/ }
    local fixup

    # Always enable ...
    echo "CONFIG_DEVTMPFS=y" >> ${defconfig}
    echo "CONFIG_DEVTMPFS_MOUNT=y" >> ${defconfig}
    echo "CONFIG_BLK_DEV_INITRD=y" >> ${defconfig}

    # Always build PXA watchdog into kernel if enabled
    sed -i -e 's/CONFIG_SA1100_WATCHDOG=m/CONFIG_SA1100_WATCHDOG=y/' ${defconfig}

    for fixup in ${fixups}; do
        case "${fixup}" in
	nofdt)
	    echo "MACH_PXA27X_DT=n" >> ${defconfig}
	    echo "MACH_PXA3XX_DT=n" >> ${defconfig}
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
	    # with commit 5f2f911578fb ("drm/imx: # atomic phase 3 step 1:
	    # Use atomic configuration"), ie since v4.8. Impact is long boot delay
	    # (kernel needs 70+ seconds to boot) and several kernel tracebacks
	    # in drm code.
	    # It also does not support CONFIG_DRM_MXSFB; trying to enable it
	    # crashes the kernel when running mcimx6ul-evk.
	    echo "CONFIG_DRM_MXSFB=n" >> ${defconfig}
	    echo "CONFIG_DRM_IMX=n" >> ${defconfig}
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
    local pid
    local retcode
    local logfile="$(__mktemp)"
    local waitlist=("Restarting" "Boot successful" "Rebooting")
    local build="${ARCH}:${mach}:${defconfig}"
    local pbuild="${build}${fixup:+:${fixup}}${dtb:+:${dtb%.dtb}}"
    local QEMUCMD="${QEMU}"
    local PREFIX="${PREFIX_A}"
    if [[ "${cpu}" = "cortex-m3" ]]; then
	PREFIX="${PREFIX_M3}"
    fi

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	pbuild+=":initrd"
    else
	pbuild+=":rootfs"
    fi

    pbuild="${pbuild//+(:)/:}"

    if ! match_params "${machine}@${mach}" "${config}@${defconfig}" "${devtree}@${ddtb}"; then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    echo -n "Building ${pbuild} ... "

    if ! checkskip "${build}" ; then
	return 0
    fi

    if ! dosetup -F "${fixup}" -c "${defconfig}${fixup%::*}}" "${rootfs}" "${defconfig}"; then
        if [[ __dosetup_rc -eq 2 ]]; then
	    return 0
	fi
	return 1
    fi

    rootfs="$(rootfsname ${rootfs})"

    echo -n "running ..."

    # if we have a dtb file use it
    local dtbcmd=""
    if [ -n "${dtb}" -a -f "${dtbfile}" ]
    then
	dtbcmd="-dtb ${dtbfile}"
    fi

    kernel="arch/arm/boot/zImage"
    case ${mach} in
    "mps2-an385")
	extra_params+=" -bios ${progdir}/mps2-boot.axf"
	initcli=""
	kernel="vmlinux"
	;;
    "overo" | "beagle" | "beaglexm")
	if ! ${progdir}/${mach}/setup.sh ${ARCH} ${PREFIX} ${rootfs} \
			${dtbfile} sd.img > ${logfile} 2>&1 ; then
	    echo "failed"
	    cat ${logfile}
	    return 1
	fi
	extra_params+=" -clock unix"
	extra_params+=" -device usb-mouse -device usb-kbd"
	# replace original root file system with generated image
	extra_params="${extra_params//${rootfs}/sd.img}"
	initcli=""
	QEMUCMD="${QEMU_LINARO}"
	;;
    "ast2500-evb" | "palmetto-bmc" | "romulus-bmc" | "witherspoon-bmc")
	initcli+=" console=ttyS4,115200"
	extra_params+=" -nodefaults"
	;;
    "akita" | "borzoi" | "spitz" | "tosa" | "terrier" | "cubieboard")
	initcli+=" console=ttyS0"
	;;
    "collie")
	initcli+=" console=ttySA1"
	;;
    "kzm" | "imx25-pdk" )
	initcli+=" console=ttymxc0,115200"
	;;
    "mainstone")
        dd if=/dev/zero of=/tmp/flash bs=262144 count=128 >/dev/null 2>&1
	# dd if=${rootfs} of=/tmp/flash bs=262144 seek=17 conv=notrunc
	# then boot from /dev/mtdblock2 (requires mtd to be built into kernel)
	initcli+=" console=ttyS0"
	extra_params+=" -drive file=/tmp/flash,format=raw,if=pflash"
	extra_params+=" -drive file=/tmp/flash,format=raw,if=pflash"
	;;
    "z2")
        dd if=/dev/zero of=/tmp/flash bs=262144 count=128 >/dev/null 2>&1
	extra_params+=" -drive file=/tmp/flash,format=raw,if=pflash"
	initcli+=" console=ttyS0"
	;;
    "raspi2")
	initcli+=" earlycon=pl011,0x3f201000"
	initcli+=" console=ttyAMA0"
	;;
    "sabrelite" | "mcimx7d-sabre" | "mcimx6ul-evk")
	initcli+=" earlycon=ec_imx6q,mmio,0x21e8000,115200n8"
	initcli+=" console=ttymxc1,115200"
	extra_params+=" -display none -serial null"
	QEMUCMD="${QEMU_MICRO}"
	;;
    "smdkc210")
	initcli+=" console=ttySAC0,115200n8"
	QEMUCMD="${QEMU_SMDKC}"
	;;
    "realview-pb-a8" | "realview-pbx-a9" | \
    "realview-eb-mpcore" | "realview-eb" | \
    "versatileab" | "versatilepb" | \
    "highbank" | "midway" | "integratorcp" | "virt" | \
    "vexpress-a9" | "vexpress-a15" | "vexpress-a15-a7")
	initcli+=" console=ttyAMA0,115200"
	;;
    "xilinx-zynq-a9")
	initcli+=" console=ttyPS0"
	extra_params+=" -serial null"
	;;
    *)
	;;
    esac

    [[ ${dodebug} -ne 0 ]] && set -x
    ${QEMUCMD} -M ${mach} \
	    ${cpu:+-cpu ${cpu}} \
	    -kernel ${kernel} \
	    -no-reboot \
	    ${extra_params} \
	    ${initcli:+--append "${initcli}"} \
	    ${dtbcmd} \
	    -nographic -monitor null -serial stdio \
	    > ${logfile} 2>&1 &
    pid=$!
    [[ ${dodebug} -ne 0 ]] && set +x
    dowait ${pid} ${logfile} ${mode} waitlist[@]
    return $?
}

echo "Build reference: $(git describe)"
echo

runkernel versatile_defconfig versatilepb "" \
	rootfs-armv5.ext2 auto aeabi:pci::scsi:mem128 versatile-pb.dtb
retcode=$?
checkstate ${retcode}
runkernel versatile_defconfig versatilepb "" \
	rootfs-armv5.cpio auto aeabi:pci::mem128 versatile-pb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel versatile_defconfig versatileab "" \
	rootfs-armv5.cpio auto ::mem128 versatile-ab.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel imx_v4_v5_defconfig imx25-pdk "" \
	rootfs-armv5.cpio manual nonand::mem128 imx25-pdk.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel imx_v6_v7_defconfig kzm "" \
	rootfs-armv5.cpio manual nodrm::mem128
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel imx_v6_v7_defconfig mcimx6ul-evk "" \
	rootfs-armv7a.cpio manual nodrm::mem256 imx6ul-14x14-evk.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel imx_v6_v7_defconfig mcimx6ul-evk "" \
	rootfs-armv7a.ext2 manual nodrm::sd:mem256 imx6ul-14x14-evk.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

# vexpress tests generate a warning if CONFIG_PROVE_RCU is enabled
runkernel multi_v7_defconfig vexpress-a9 "" \
	rootfs-armv5.cpio auto nolocktests::mem128 vexpress-v2p-ca9.dtb
retcode=$((${retcode} + $?))
runkernel multi_v7_defconfig vexpress-a9 "" \
	rootfs-armv5.ext2 auto nolocktests::sd:mem128 vexpress-v2p-ca9.dtb
retcode=$((${retcode} + $?))
runkernel multi_v7_defconfig vexpress-a9 "" \
	rootfs-armv5.ext2 auto nolocktests::virtio-blk:mem128 vexpress-v2p-ca9.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig vexpress-a15 "" \
	rootfs-armv7a.ext2 auto nolocktests::sd:mem128 vexpress-v2p-ca15-tc1.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
# Local qemu v2.7+ has minimal support for vexpress-a15-a7
runkernel multi_v7_defconfig vexpress-a15-a7 "" \
	rootfs-armv7a.ext2 auto nolocktests::sd:mem256 vexpress-v2p-ca15_a7.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel multi_v7_defconfig beagle "" \
	rootfs-armv5.ext2 auto ::sd:mem256 omap3-beagle.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig beaglexm "" \
	rootfs-armv5.ext2 auto ::sd:mem512 omap3-beagle-xm.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig overo "" \
	rootfs-armv5.ext2 auto ::sd:mem256 omap3-overo-tobi.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel multi_v7_defconfig midway "" \
	rootfs-armv7a.cpio auto ::mem2G ecx-2000.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel multi_v7_defconfig sabrelite "" \
	rootfs-armv5.cpio manual ::mem256 imx6dl-sabrelite.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

if [[ "${runall}" -eq 1 ]]; then
  # Completely fails to boot, no message to console
  runkernel multi_v7_defconfig mcimx7d-sabre "" \
	rootfs-armv7a.cpio manual ::mem256 imx7d-sdb.dtb
  retcode=$((${retcode} + $?))
  checkstate ${retcode}
fi

runkernel multi_v7_defconfig xilinx-zynq-a9 "" \
	rootfs-armv5.cpio auto ::mem128 zynq-zc702.dtb
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
	rootfs-armv5.ext2 auto ::sd:mem128 zynq-zed.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel multi_v7_defconfig cubieboard "" \
	rootfs-armv5.cpio manual ::mem128 sun4i-a10-cubieboard.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel multi_v7_defconfig raspi2 "" \
	rootfs-armv7a.cpio manual "" bcm2836-rpi-2-b.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig raspi2 "" \
	rootfs-armv7a.ext2 manual ::sd bcm2836-rpi-2-b.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel multi_v7_defconfig virt "" \
	rootfs-armv7a.ext2 auto "::virtio-blk:mem512"
retcode=$((${retcode} + $?))
checkstate ${retcode}

if [ ${runall} -eq 1 ]; then
    # highbank boots with updated qemu, but generates warnings to the console
    # due to ignored SMC calls.
    runkernel multi_v7_defconfig highbank cortex-a9 \
	rootfs-armv7a.cpio auto ::mem2G highbank.dtb
    retcode=$((${retcode} + $?))
    checkstate ${retcode}
fi

runkernel exynos_defconfig smdkc210 "" \
	rootfs-armv5.cpio manual cpuidle::mem128 exynos4210-smdkv310.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel realview_defconfig realview-pb-a8 "" \
	rootfs-armv5.cpio auto realview_pb::mem512 arm-realview-pba8.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel realview_defconfig realview-pbx-a9 "" \
	rootfs-armv5.cpio auto realview_pb arm-realview-pbx-a9.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel realview_defconfig realview-eb cortex-a8 \
	rootfs-armv5.cpio manual realview_eb::mem512 arm-realview-eb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel realview_defconfig realview-eb-mpcore "" \
	rootfs-armv5.cpio manual realview_eb::mem512 \
	arm-realview-eb-11mp-ctrevb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

# disable options to avoid running out of memory
runkernel pxa_defconfig akita "" \
	rootfs-armv5.cpio automatic nofdt:nodebug:notests:novirt:nousb:noscsi
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel pxa_defconfig borzoi "" \
	rootfs-armv5.cpio automatic nofdt:nodebug:notests:novirt:nousb:noscsi
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel pxa_defconfig mainstone "" \
	rootfs-armv5.cpio automatic nofdt:nodebug:notests:novirt:nousb:noscsi
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel pxa_defconfig spitz "" \
	rootfs-armv5.cpio automatic nofdt:nodebug:notests:novirt:nousb:noscsi
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel pxa_defconfig terrier "" \
	rootfs-armv5.cpio automatic nofdt:nodebug:notests:novirt:nousb:noscsi
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel pxa_defconfig tosa "" \
	rootfs-armv5.cpio automatic nofdt:nodebug:notests:novirt:nousb:noscsi
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel pxa_defconfig z2 "" \
	rootfs-armv5.cpio automatic nofdt:nodebug:notests:novirt:nousb:noscsi
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel collie_defconfig collie "" \
	rootfs-sa110.cpio manual aeabi:notests
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel integrator_defconfig integratorcp "" \
	rootfs-armv5.cpio automatic ::mem128 integratorcp.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g4_defconfig palmetto-bmc "" \
	rootfs-armv5.cpio automatic "" aspeed-bmc-opp-palmetto.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

# selftests sometimes hang with soft CPU lockup
runkernel aspeed_g5_defconfig witherspoon-bmc "" \
	rootfs-armv5.cpio automatic notests aspeed-bmc-opp-witherspoon.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g5_defconfig ast2500-evb "" \
	rootfs-armv5.cpio automatic notests aspeed-ast2500-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g5_defconfig romulus-bmc "" \
	rootfs-armv5.cpio automatic notests aspeed-bmc-opp-romulus.dtb
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
	rootfs-armv7a.cpio manual ::mem128 sun4i-a10-cubieboard.dtb
    retcode=$((${retcode} + $?))
    checkstate ${retcode}
fi

exit ${retcode}
