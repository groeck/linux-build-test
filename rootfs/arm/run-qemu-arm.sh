#!/bin/bash

progdir=$(cd $(dirname $0); pwd)
. ${progdir}/../scripts/config.sh
. ${progdir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

QEMU_MICRO=${QEMU:-${QEMU_V31_BIN}/qemu-system-arm}
# Some zynq images fail to run with qemu v2.7
QEMU_ZYNQ=${QEMU:-${QEMU_BIN}/qemu-system-arm}
QEMU_SMDKC=${QEMU:-${QEMU_V28_BIN}/qemu-system-arm}
QEMU_LINARO=${QEMU:-${QEMU_LINARO_BIN}/qemu-system-arm}
# Failures seen with qemu v2.9:
# arm:smdkc210:multi_v7_defconfig:exynos4210-smdkv310
# arm:smdkc210:exynos_defconfig:exynos4210-smdkv310
# arm:z2:pxa_defconfig
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

skip_316="arm:mainstone:mainstone_defconfig \
	arm:mcimx6ul-evk:imx_v6_v7_defconfig \
	arm:raspi2:multi_v7_defconfig \
	arm:virt:multi_v7_defconfig \
	arm:realview-pbx-a9:realview_defconfig \
	arm:smdkc210:multi_v7_defconfig"
skip_318="arm:mainstone:mainstone_defconfig \
	arm:mcimx6ul-evk:imx_v6_v7_defconfig \
	arm:raspi2:multi_v7_defconfig \
	arm:virt:multi_v7_defconfig \
	arm:realview-pbx-a9:realview_defconfig \
	arm:smdkc210:multi_v7_defconfig"
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
	regulator)
	    echo "CONFIG_REGULATOR=y" >> ${defconfig}
	    echo "CONFIG_REGULATOR_VEXPRESS=y" >> ${defconfig}
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
    local mem=$4
    local rootfs=$5
    local mode=$6
    local fixup=$7
    local dtb=$8
    local ddtb=$(echo ${dtb} | sed -e 's/.dtb//')
    local dtbfile="arch/arm/boot/dts/${dtb}"
    local pid
    local retcode
    local logfile="$(__mktemp)"
    local waitlist=("Restarting" "Boot successful" "Rebooting")
    local s
    local build="${ARCH}:${mach}:${defconfig}"
    local pbuild="${build}"

    PREFIX="${PREFIX_A}"
    if [[ "${cpu}" == "cortex-m3" ]]; then
	PREFIX="${PREFIX_M3}"
    fi

    if [ -n "${ddtb}" ]
    then
	pbuild="${build}:${ddtb}"
    fi

    if ! match_params "${machine}@${mach}" "${config}@${defconfig}" "${devtree}@${ddtb}"; then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    echo -n "Building ${pbuild} ... "

    if ! checkskip "${build}" ; then
	return 0
    fi

    if ! dosetup -f "${fixup:-fixup}" -c "${defconfig}${fixup:+:${fixup}}" "${rootfs}" "${defconfig}"; then
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

    # Specify CPU if provided
    local cpucmd=""
    if [ -n "${cpu}" ]
    then
	cpucmd="-cpu ${cpu}"
    fi

    # Specify amount of memory if provided
    local memcmd=""
    if [ -n "${mem}" ]
    then
	memcmd="-m ${mem}"
    fi

    local earlycon=""
    case ${mach} in
    raspi2)
	earlycon="earlycon=pl011,0x3f201000"
	;;
    "sabrelite" | "mcimx7d-sabre" | "mcimx6ul-evk")
	earlycon="earlycon=ec_imx6q,mmio,0x21e8000,115200n8"
	;;
    *)
	;;
    esac

    case ${mach} in
    "virt")
	[[ ${dodebug} -ne 0 ]] && set -x
	${QEMU} -M ${mach} -m 512 \
	    -no-reboot \
	    -kernel arch/arm/boot/zImage \
	    -snapshot \
	    -drive file=${rootfs},format=raw,id=rootfs,if=none \
	    -device virtio-blk-device,drive=rootfs \
	    --append "console=ttyAMA0 root=/dev/vda rw" \
	    -nographic -monitor null -serial stdio \
	    > ${logfile} 2>&1 &
	pid=$!
	[[ ${dodebug} -ne 0 ]] && set +x
	;;
    "mps2-an385")
	[[ ${dodebug} -ne 0 ]] && set -x
	${QEMU} -M ${mach} \
	    -bios "${progdir}/mps2-boot.axf" \
	    -kernel vmlinux \
	    -initrd ${rootfs} \
	    ${dtbcmd} \
	    -nographic -monitor null -serial stdio \
	    > ${logfile} 2>&1 &
	pid=$!
	[[ ${dodebug} -ne 0 ]] && set +x
	;;
    "raspi2")
	[[ ${dodebug} -ne 0 ]] && set -x
	${QEMU} -M ${mach} \
	    -kernel arch/arm/boot/zImage -no-reboot \
	    -snapshot \
	    -drive file=${rootfs},format=raw,if=sd \
	    --append "root=/dev/mmcblk0 rootwait rw ${earlycon} console=ttyAMA0" \
	    ${dtbcmd} \
	    -nographic -monitor null -serial stdio \
	    > ${logfile} 2>&1 &
	pid=$!
	[[ ${dodebug} -ne 0 ]] && set +x
	;;
    "collie")
	[[ ${dodebug} -ne 0 ]] && set -x
	${QEMU} -M ${mach} \
	    -kernel arch/arm/boot/zImage -no-reboot \
	    -initrd ${rootfs} \
	    --append "rdinit=/sbin/init console=ttySA1 doreboot" \
	    -monitor null -nographic \
	    > ${logfile} 2>&1 &
	pid=$!
	[[ ${dodebug} -ne 0 ]] && set +x
	;;
    "mainstone")
        dd if=/dev/zero of=/tmp/flash bs=262144 count=128 >/dev/null 2>&1
	# dd if=${rootfs} of=/tmp/flash bs=262144 seek=17 conv=notrunc
	# then boot from /dev/mtdblock2 (requires mtd to be built into kernel)
	[[ ${dodebug} -ne 0 ]] && set -x
	${QEMU} -M ${mach} ${cpucmd} \
	    -kernel arch/arm/boot/zImage -no-reboot \
	    -initrd ${rootfs} \
	    -drive file=/tmp/flash,format=raw,if=pflash \
	    -drive file=/tmp/flash,format=raw,if=pflash \
	    --append "rdinit=/sbin/init console=ttyS0" \
	    -monitor null -nographic \
	    > ${logfile} 2>&1 &
	pid=$!
	[[ ${dodebug} -ne 0 ]] && set +x
	;;
    "z2")
        dd if=/dev/zero of=/tmp/flash bs=262144 count=128 >/dev/null 2>&1
	# dd if=${rootfs} of=/tmp/flash bs=262144 seek=17 conv=notrunc
	# then boot from /dev/mtdblock2 (requires mtd to be built into kernel)
	[[ ${dodebug} -ne 0 ]] && set -x
	${QEMU} -M ${mach} ${cpucmd} \
	    -kernel arch/arm/boot/zImage -no-reboot \
	    -initrd ${rootfs} \
	    -drive file=/tmp/flash,format=raw,if=pflash \
	    --append "rdinit=/sbin/init console=ttyS0" \
	    -monitor null -nographic \
	    > ${logfile} 2>&1 &
	pid=$!
	[[ ${dodebug} -ne 0 ]] && set +x
	;;
    "akita" | "borzoi" | "spitz" | "tosa" | "terrier" | "cubieboard")
	[[ ${dodebug} -ne 0 ]] && set -x
	${QEMU} -M ${mach} ${cpucmd} \
	    -kernel arch/arm/boot/zImage -no-reboot \
	    -d unimp,guest_errors \
	    -initrd ${rootfs} \
	    --append "rdinit=/sbin/init console=ttyS0" \
	    -monitor null -nographic ${dtbcmd} \
	    > ${logfile} 2>&1 &
	pid=$!
	[[ ${dodebug} -ne 0 ]] && set +x
	;;
    "overo" | "beagle" | "beaglexm")
	${progdir}/${mach}/setup.sh ${ARCH} ${PREFIX} ${rootfs} \
	    ${dtbfile} sd.img > ${logfile} 2>&1
	if [ $? -ne 0 ]
	then
	    echo "failed"
	    cat ${logfile}
	    return 1
	fi
	[[ ${dodebug} -ne 0 ]] && set -x
	${QEMU_LINARO} -M ${mach} \
	    ${memcmd} -clock unix -no-reboot \
	    -snapshot \
	    -drive file=sd.img,format=raw,if=sd,cache=writeback \
	    -device usb-mouse -device usb-kbd \
	    -serial stdio -monitor none -nographic \
	    > ${logfile} 2>&1 &
	pid=$!
	[[ ${dodebug} -ne 0 ]] && set +x
        ;;
    "kzm" | "imx25-pdk" )
	${QEMU} -M ${mach} \
	    -kernel arch/arm/boot/zImage  -no-reboot \
	    -initrd ${rootfs} \
	    -append "rdinit=/sbin/init console=ttymxc0,115200" \
	    -nographic -monitor none -serial stdio \
	    ${dtbcmd} > ${logfile} 2>&1 &
	pid=$!
	;;
    "sabrelite" | "mcimx7d-sabre" | "mcimx6ul-evk")
	if [[ "${rootfs}" = *cpio ]]; then
	    diskcmd="-initrd ${rootfs}"
	    initcli="rdinit=/sbin/init"
	else
	    diskcmd="-drive file=${rootfs},format=raw,if=sd -snapshot"
	    initcli="root=/dev/mmcblk0 rootwait rw"
	fi

	[[ ${dodebug} -ne 0 ]] && set -x
	${QEMU_MICRO} -M ${mach} ${memcmd} \
	    -kernel arch/arm/boot/zImage  -no-reboot \
	    ${diskcmd} \
	    -append "${initcli} ${earlycon} console=ttymxc1,115200" \
	    -nographic -monitor none -display none -serial null -serial stdio \
	    ${dtbcmd} > ${logfile} 2>&1 &
	pid=$!
	[[ ${dodebug} -ne 0 ]] && set +x
	;;
    "smdkc210")
	${QEMU_SMDKC} -M ${mach} -smp 2 \
	    -kernel arch/arm/boot/zImage -no-reboot \
	    -initrd ${rootfs} \
	    -append "rdinit=/sbin/init console=ttySAC0,115200n8" \
	    -nographic -monitor none -serial stdio \
	    ${dtbcmd} > ${logfile} 2>&1 &
	pid=$!
	;;
    "xilinx-zynq-a9")
	${QEMU_ZYNQ} -M ${mach} \
	    -kernel arch/arm/boot/zImage -no-reboot \
	    -snapshot \
	    -drive file=${rootfs},format=raw,if=sd \
	    -append "root=/dev/mmcblk0 rootwait rw console=ttyPS0" \
	    -nographic -monitor none -serial null -serial stdio \
	    ${dtbcmd} > ${logfile} 2>&1 &
	pid=$!
	;;
    "realview-pb-a8" | "realview-pbx-a9" | \
    "realview-eb-mpcore" | "realview-eb" | \
    "versatileab" | "versatilepb" | \
    "highbank" | "midway" | "integratorcp")
	[[ ${dodebug} -ne 0 ]] && set -x
	${QEMU} -M ${mach} ${cpucmd} ${memcmd} \
	    -kernel arch/arm/boot/zImage -no-reboot \
	    -initrd ${rootfs} \
	    --append "rdinit=/sbin/init console=ttyAMA0,115200" \
	    -serial stdio -monitor null -nographic \
	    ${dtbcmd} > ${logfile} 2>&1 &
	pid=$!
	[[ ${dodebug} -ne 0 ]] && set +x
	;;
    "versatilepb-scsi" )
	[[ ${dodebug} -ne 0 ]] && set -x
	${QEMU} -M versatilepb -m 128 \
	    -kernel arch/arm/boot/zImage -no-reboot \
	    -snapshot \
	    -drive file=${rootfs},format=raw,if=scsi \
	    --append "root=/dev/sda rw mem=128M console=ttyAMA0,115200 console=tty" \
	    -nographic -serial stdio -monitor null \
	    ${dtbcmd} > ${logfile} 2>&1 &
	pid=$!
	[[ ${dodebug} -ne 0 ]] && set +x
	;;
    "vexpress-a9" | "vexpress-a15" | "vexpress-a15-a7")
	[[ ${dodebug} -ne 0 ]] && set -x
	${QEMU} -M ${mach} \
	    -kernel arch/arm/boot/zImage -no-reboot \
	    -snapshot \
	    -drive file=${rootfs},format=raw,if=sd \
	    -append "root=/dev/mmcblk0 rootwait rw console=ttyAMA0,115200 console=tty1" \
	    -nographic ${dtbcmd} > ${logfile} 2>&1 &
	pid=$!
	[[ ${dodebug} -ne 0 ]] && set +x
	;;
    "ast2500-evb" | "palmetto-bmc" | "romulus-bmc" | "witherspoon-bmc")
	[[ ${dodebug} -ne 0 ]] && set -x
	${QEMU} -M ${mach} \
		-nodefaults -nographic -serial stdio -monitor none \
		-kernel arch/arm/boot/zImage -no-reboot \
		-snapshot \
		${dtbcmd} \
		-append "rdinit=/sbin/init console=ttyS4,115200 earlyprintk" \
		-initrd ${rootfs} \
		> ${logfile} 2>&1 &
	pid=$!
	[[ ${dodebug} -ne 0 ]] && set +x
	;;
    *)
	echo "Missing build recipe for machine ${mach}"
	exit 1
    esac

    dowait ${pid} ${logfile} ${mode} waitlist[@]
    return $?
}

echo "Build reference: $(git describe)"
echo

runkernel versatile_defconfig versatilepb-scsi "" 128 \
	rootfs-armv5.ext2 auto aeabi:pci:scsi versatile-pb.dtb
retcode=$?
checkstate ${retcode}

runkernel versatile_defconfig versatileab "" 128 \
	rootfs-armv5.cpio auto "" versatile-ab.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel versatile_defconfig versatilepb "" 128 \
	rootfs-armv5.cpio auto "" versatile-pb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel vexpress_defconfig vexpress-a9 "" 128 \
	rootfs-armv5.ext2 auto regulator vexpress-v2p-ca9.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel vexpress_defconfig vexpress-a15 "" 128 \
	rootfs-armv5.ext2 auto regulator vexpress-v2p-ca15-tc1.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel imx_v4_v5_defconfig imx25-pdk "" 128 \
	rootfs-armv5.cpio manual nonand imx25-pdk.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel imx_v6_v7_defconfig kzm "" 128 \
	rootfs-armv5.cpio manual nodrm
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel imx_v6_v7_defconfig sabrelite "" 256 \
	rootfs-armv5.cpio manual nodrm imx6dl-sabrelite.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

if [[ "${runall}" -eq 1 ]]; then
  # Qemu does not accept drive command
  runkernel imx_v6_v7_defconfig sabrelite "" 256 \
	rootfs-armv7a.ext2 manual nodrm imx6dl-sabrelite.dtb
  retcode=$((${retcode} + $?))
  checkstate ${retcode}
fi

runkernel imx_v6_v7_defconfig mcimx6ul-evk "" 256 \
	rootfs-armv7a.cpio manual nodrm imx6ul-14x14-evk.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel imx_v6_v7_defconfig mcimx6ul-evk "" 256 \
	rootfs-armv7a.ext2 manual nodrm imx6ul-14x14-evk.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel multi_v7_defconfig beagle "" 256 \
	rootfs-armv5.ext2 auto "" omap3-beagle.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig beaglexm "" 512 \
	rootfs-armv5.ext2 auto "" omap3-beagle-xm.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig overo "" 256 \
	rootfs-armv5.ext2 auto "" omap3-overo-tobi.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel multi_v7_defconfig sabrelite "" 256 \
	rootfs-armv5.cpio manual "" imx6dl-sabrelite.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

if [[ "${runall}" -eq 1 ]]; then
  # Completely fails to boot, no message to console
  runkernel multi_v7_defconfig mcimx7d-sabre "" 256 \
	rootfs-armv7a.cpio manual "" imx7d-sdb.dtb
  retcode=$((${retcode} + $?))
  checkstate ${retcode}
fi

runkernel multi_v7_defconfig vexpress-a9 "" 128 \
	rootfs-armv5.ext2 auto "" vexpress-v2p-ca9.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig vexpress-a15 "" 128 \
	rootfs-armv7a.ext2 auto "" vexpress-v2p-ca15-tc1.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

# Local qemu v2.7+ has minimal support for vexpress-a15-a7
runkernel multi_v7_defconfig vexpress-a15-a7 "" 256 \
	rootfs-armv7a.ext2 auto "" vexpress-v2p-ca15_a7.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel multi_v7_defconfig xilinx-zynq-a9 "" 128 \
	rootfs-armv5.ext2 auto "" zynq-zc702.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig xilinx-zynq-a9 "" 128 \
	rootfs-armv5.ext2 auto "" zynq-zc706.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel multi_v7_defconfig xilinx-zynq-a9 "" 128 \
	rootfs-armv5.ext2 auto "" zynq-zed.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel multi_v7_defconfig cubieboard "" 128 \
	rootfs-armv5.cpio manual "" sun4i-a10-cubieboard.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel multi_v7_defconfig raspi2 "" "" \
	rootfs-armv7a.ext2 manual "" bcm2836-rpi-2-b.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel multi_v7_defconfig virt "" "" \
	rootfs-armv7a.ext2 auto ""
retcode=$((${retcode} + $?))
checkstate ${retcode}

if [ ${runall} -eq 1 ]; then
    # highbank boots with updated qemu, but generates warnings to the console
    # due to ignored SMC calls.
    runkernel multi_v7_defconfig highbank cortex-a9 2G \
	rootfs-armv7a.cpio auto "" highbank.dtb
    retcode=$((${retcode} + $?))
    checkstate ${retcode}
fi

runkernel multi_v7_defconfig midway "" 2G \
	rootfs-armv7a.cpio auto "" ecx-2000.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel multi_v7_defconfig smdkc210 "" 128 \
	rootfs-armv5.cpio manual cpuidle exynos4210-smdkv310.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel exynos_defconfig smdkc210 "" 128 \
	rootfs-armv5.cpio manual cpuidle exynos4210-smdkv310.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel omap2plus_defconfig beagle "" 256 \
	rootfs-armv5.ext2 auto "" omap3-beagle.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel omap2plus_defconfig beaglexm "" 512 \
	rootfs-armv5.ext2 auto "" omap3-beagle-xm.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel omap2plus_defconfig overo "" 256 \
	rootfs-armv5.ext2 auto "" omap3-overo-tobi.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel realview_defconfig realview-pb-a8 "" 512 \
	rootfs-armv5.cpio auto realview_pb arm-realview-pba8.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel realview_defconfig realview-pbx-a9 "" "" \
	rootfs-armv5.cpio auto realview_pb arm-realview-pbx-a9.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel realview_defconfig realview-eb cortex-a8 512 \
	rootfs-armv5.cpio manual realview_eb arm-realview-eb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel realview_defconfig realview-eb-mpcore "" 512 \
	rootfs-armv5.cpio manual realview_eb \
	arm-realview-eb-11mp-ctrevb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel realview-smp_defconfig realview-eb-mpcore "" 512 \
	rootfs-armv5.cpio manual realview_eb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel mainstone_defconfig mainstone "" "" \
	rootfs-armv5.cpio automatic aeabi
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel spitz_defconfig akita "" "" \
	rootfs-armv5.cpio automatic aeabi
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel spitz_defconfig spitz "" "" \
	rootfs-armv5.cpio automatic aeabi
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel pxa_defconfig akita "" "" \
	rootfs-armv5.cpio automatic nofdt
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel pxa_defconfig borzoi "" "" \
	rootfs-armv5.cpio automatic nofdt
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel pxa_defconfig mainstone "" "" \
	rootfs-armv5.cpio automatic nofdt
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel pxa_defconfig spitz "" "" \
	rootfs-armv5.cpio automatic nofdt
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel pxa_defconfig terrier "" "" \
	rootfs-armv5.cpio automatic nofdt
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel pxa_defconfig tosa "" "" \
	rootfs-armv5.cpio automatic nofdt
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel pxa_defconfig z2 "" "" \
	rootfs-armv5.cpio automatic nofdt
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel collie_defconfig collie "" "" \
	busybox-armv4.cpio manual aeabi
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel integrator_defconfig integratorcp "" 128 \
	rootfs-armv5.cpio automatic "" integratorcp.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g4_defconfig palmetto-bmc "" 512 \
	rootfs-armv5.cpio automatic "" aspeed-bmc-opp-palmetto.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g5_defconfig witherspoon-bmc "" 512 \
	rootfs-armv5.cpio automatic "" aspeed-bmc-opp-witherspoon.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g5_defconfig ast2500-evb "" 512 \
	rootfs-armv5.cpio automatic "" aspeed-ast2500-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g5_defconfig romulus-bmc "" 512 \
	rootfs-armv5.cpio automatic "" aspeed-bmc-opp-romulus.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel mps2_defconfig "mps2-an385" "cortex-m3" "" \
	rootfs-arm-m3.cpio manual initrd mps2-an385.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

if [ ${runall} -eq 1 ]; then
    # Generates runtime warning "sunxi_musb_ep_offset called with non 0 offset"
    # which may be caused by qemu. The call originates from ep_config_from_hw(),
    # which calls musb_read_fifosize(), which in turn calls the function
    # with parameter MUSB_FIFOSIZE=0x0f.
    runkernel sunxi_defconfig cubieboard "" 128 \
	rootfs-armv7a.cpio manual "" sun4i-a10-cubieboard.dtb
    retcode=$((${retcode} + $?))
    checkstate ${retcode}
fi

exit ${retcode}
