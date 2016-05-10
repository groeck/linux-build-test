#!/bin/bash

runall=0
if [ "$1" = "-a" ]
then
    runall=1
    shift
fi

machine=$1
config=$2
devtree=$3

QEMU=/opt/buildbot/bin/qemu-system-arm
QEMU_V26=/opt/buildbot/bin/qemu-v2.6/qemu-system-arm
# QEMU=/opt/buildbot/qemu/qemu/arm-softmmu/qemu-system-arm

PREFIX=arm-poky-linux-gnueabi-
ARCH=arm
# PATH_ARM=/opt/poky/1.3/sysroots/x86_64-pokysdk-linux/usr/bin/armv5te-poky-linux-gnueabi
PATH_ARM=/opt/poky/1.4.2/sysroots/x86_64-pokysdk-linux/usr/bin/armv7a-vfp-neon-poky-linux-gnueabi

PATH=${PATH_ARM}:${PATH}

progdir=$(cd $(dirname $0); pwd)

# multi_v7_defconfig only exists starting with v3.10.
# versatileab/versatilepb need different binaries prior to 3.14.
# beagle in 3.14 dumps a warning message to the console.
# imx25-pdk passes reliably starting with 3.12. 3.10 would require
# a patch (8bba8303b059, "ARM: imx_v4_v5_defconfig: Select
# CONFIG_MACH_IMX25_DT") to be applied.

skip_32="arm:beagle:omap2plus_defconfig \
	arm:beaglexm:omap2plus_defconfig \
	arm:imx25-pdk:imx_v4_v5_defconfig \
	arm:kzm:imx_v6_v7_defconfig \
	arm:mainstone:mainstone_defconfig \
	arm:overo:omap2plus_defconfig \
	arm:versatileab:versatile_defconfig \
	arm:versatilepb:versatile_defconfig \
	arm:vexpress-a9:vexpress_defconfig \
	arm:vexpress-a15:vexpress_defconfig"
skip_34="arm:akita:spitz_defconfig \
	arm:beagle:omap2plus_defconfig \
	arm:beaglexm:omap2plus_defconfig \
	arm:imx25-pdk:imx_v4_v5_defconfig \
	arm:mainstone:mainstone_defconfig \
	arm:overo:omap2plus_defconfig \
	arm:spitz:spitz_defconfig \
	arm:versatileab:versatile_defconfig \
	arm:versatilepb:versatile_defconfig \
	arm:versatilepb-scsi:versatile_defconfig \
	arm:vexpress-a9:vexpress_defconfig \
	arm:vexpress-a15:vexpress_defconfig"
skip_310="arm:akita:spitz_defconfig \
	arm:beagle:multi_v7_defconfig \
	arm:beagle:omap2plus_defconfig \
	arm:beaglexm:multi_v7_defconfig \
	arm:beaglexm:omap2plus_defconfig \
	arm:highbank:multi_v7_defconfig \
	arm:imx25-pdk:imx_v4_v5_defconfig \
	arm:mainstone:mainstone_defconfig \
	arm:overo:multi_v7_defconfig \
	arm:overo:omap2plus_defconfig \
	arm:smdkc210:multi_v7_defconfig \
	arm:spitz:spitz_defconfig \
	arm:versatileab:versatile_defconfig \
	arm:versatilepb:versatile_defconfig \
	arm:vexpress-a9:multi_v7_defconfig \
	arm:vexpress-a15:multi_v7_defconfig \
	arm:xilinx-zynq-a9:multi_v7_defconfig"
skip_312="arm:mainstone:mainstone_defconfig \
	arm:overo:multi_v7_defconfig \
	arm:overo:omap2plus_defconfig \
	arm:smdkc210:multi_v7_defconfig \
	arm:versatileab:versatile_defconfig \
	arm:versatilepb:versatile_defconfig \
	arm:xilinx-zynq-a9:multi_v7_defconfig"
skip_314="arm:beagle:multi_v7_defconfig \
	arm:beagle:omap2plus_defconfig \
	arm:mainstone:mainstone_defconfig \
	arm:overo:multi_v7_defconfig \
	arm:overo:omap2plus_defconfig \
	arm:smdkc210:multi_v7_defconfig \
	arm:xilinx-zynq-a9:multi_v7_defconfig"
skip_316="arm:mainstone:mainstone_defconfig \
	arm:smdkc210:multi_v7_defconfig"
skip_318="arm:mainstone:mainstone_defconfig \
	arm:smdkc210:multi_v7_defconfig"
skip_41="arm:versatilepb-scsi:versatile_defconfig"
skip_43="arm:versatilepb-scsi:versatile_defconfig"

. ${progdir}/../scripts/common.sh

cached_config=""

patch_defconfig()
{
    local defconfig=$1
    local fixup=$2

    # We need DEVTMPFS for initrd images.

    if [ "${fixup}" = "devtmpfs" -o "${fixup}" = "regulator" -o \
         "${fixup}" = "realview_eb" -o "${fixup}" = "realview_pb" -o \
	 "${fixup}" = "versatile" -o "${fixup}" = "pxa" -o "${fixup}" = "collie" ]
    then
	sed -i -e '/CONFIG_DEVTMPFS/d' ${defconfig}
	echo "CONFIG_DEVTMPFS=y" >> ${defconfig}
    fi

    # Non-generic pxa images as well as collie need to have BLK_DEV_INITRD
    # and EABI enabled.
    if [ "${fixup}" = "pxa" -o "${fixup}" = "collie" ]
    then
	sed -i -e '/CONFIG_BLK_DEV_INITRD/d' ${defconfig}
	echo "CONFIG_BLK_DEV_INITRD=y" >> ${defconfig}
	sed -i -e '/CONFIG_AEABI/d' ${defconfig}
	echo "CONFIG_AEABI=y" >> ${defconfig}
    fi

    # Versatile (scsi) needs to have AEABI, PCI and SCSI enabled.

    if [ "${fixup}" = "versatile" ]
    then
	sed -i -e '/CONFIG_AEABI/d' ${defconfig}
	echo "CONFIG_AEABI=y" >> ${defconfig}
	sed -i -e '/CONFIG_PCI/d' ${defconfig}
	echo "CONFIG_PCI=y" >> ${defconfig}
	echo "CONFIG_PCI_VERSATILE=y" >> ${defconfig}
	sed -i -e '/CONFIG_OF/d' ${defconfig}
	echo "CONFIG_OF=y" >> ${defconfig}
	echo "CONFIG_OF_PCI=y" >> ${defconfig}
	echo "CONFIG_OF_PCI_IRQ=y" >> ${defconfig}
	sed -i -e '/CONFIG_SCSI/d' ${defconfig}
	echo "CONFIG_SCSI=y" >> ${defconfig}
	echo "CONFIG_SCSI_SYM53C8XX_2=y" >> ${defconfig}
	sed -i -e '/CONFIG_BLK_DEV_SD/d' ${defconfig}
	echo "CONFIG_BLK_DEV_SD=y" >> ${defconfig}
    fi

    if [ "${fixup}" = "regulator" ]
    then
	sed -i -e '/CONFIG_REGULATOR/d' ${defconfig}
	sed -i -e '/CONFIG_REGULATOR_VEXPRESS/d' ${defconfig}
	echo "CONFIG_REGULATOR=y" >> ${defconfig}
	echo "CONFIG_REGULATOR_VEXPRESS=y" >> ${defconfig}
    fi

    # CPUIDLE causes Exynos targets to run really slow.

    if [ "${fixup}" = "cpuidle" ]
    then
	sed -i -e '/CONFIG_CPU_IDLE/d' ${defconfig}
	sed -i -e '/CONFIG_ARM_EXYNOS_CPUIDLE/d' ${defconfig}
    fi

    # For imx25, disable NAND (not supported as of qemu 2.5, causes
    # a runtime warning).

    if [ "${fixup}" = "imx25" ]
    then
	sed -i -e '/CONFIG_MTD_NAND_MXC/d' ${defconfig}
    fi

    # imx25 and realview need initrd support

    if [ "${fixup}" = "imx25" -o "${fixup}" = "realview_eb" -o \
	 "${fixup}" = "realview_pb" ]
    then
	sed -i -e '/CONFIG_BLK_DEV_INITRD/d' ${defconfig}
	echo "CONFIG_BLK_DEV_INITRD=y" >> ${defconfig}
    fi

    # Older versions of realview config files need additional CPU support.

    if [ "${fixup}" = "realview_eb" ]
    then
	sed -i -e '/CONFIG_REALVIEW_EB_A9MP/d' ${defconfig}
	echo "CONFIG_REALVIEW_EB_A9MP=y" >> ${defconfig}
	sed -i -e '/CONFIG_REALVIEW_EB_ARM11MP_REVB/d' ${defconfig}
	echo "CONFIG_REALVIEW_EB_ARM11MP_REVB=y" >> ${defconfig}
	sed -i -e '/CONFIG_MACH_REALVIEW_PBX/d' ${defconfig}
	echo "CONFIG_MACH_REALVIEW_PBX=y" >> ${defconfig}
	sed -i -e '/CONFIG_MACH_REALVIEW_PB1176/d' ${defconfig}
	echo "CONFIG_MACH_REALVIEW_PB1176=y" >> ${defconfig}
    fi

    # Similar for PB-A8. Also disable some EB and incompatible PB
    # configurations.

    if [ "${fixup}" = "realview_pb" ]
    then
	sed -i -e '/CONFIG_REALVIEW_EB/d' ${defconfig}
	sed -i -e '/CONFIG_MACH_REALVIEW_PB11/d' ${defconfig}
	sed -i -e '/CONFIG_MACH_REALVIEW_PBX/d' ${defconfig}
	echo "CONFIG_MACH_REALVIEW_PBX=y" >> ${defconfig}
	sed -i -e '/CONFIG_MACH_REALVIEW_PBA8/d' ${defconfig}
	echo "CONFIG_MACH_REALVIEW_PBA8=y" >> ${defconfig}
    fi
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
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Restarting" "Boot successful" "Rebooting")
    local rel=$(git describe | cut -f1 -d- | cut -f1,2 -d. | sed -e 's/\.//' | sed -e 's/v//')
    local tmp="skip_${rel}"
    local skip=(${!tmp})
    local s
    local build=${ARCH}:${mach}:${defconfig}
    local pbuild=${build}

    if [ -n "${ddtb}" ]
    then
	pbuild="${build}:${ddtb}"
    fi

    if [ -n "${machine}" -a "${machine}" != "${mach}" ]
    then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    if [ -n "${config}" -a "${config}" != "${defconfig}" ]
    then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    if [ -n "${devtree}" -a "${devtree}" != "${ddtb}" ]
    then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    echo -n "Building ${pbuild} ... "

    for s in ${skip[*]}
    do
	if [ "$s" = "${build}" ]
	then
	    echo "skipped"
	    return 0
	fi
    done

    if [ "${cached_config}" != "${defconfig}:${fixup}" ]
    then
	# KALLSYMS_EXTRA_PASS is needed for earlier kernels (3.2, 3.4) due to
	# a bug in kallsyms which would be too difficult to back-port.
	# See upstream commits f6537f2f0e and 7122c3e915.
	dosetup ${ARCH} ${PREFIX} "KALLSYMS_EXTRA_PASS=1" ${rootfs} ${defconfig} "" ${fixup}
	retcode=$?
	if [ ${retcode} -eq 2 ]
	then
	    return 0
	fi
	if [ ${retcode} -ne 0 ]
	then
	    return 1
	fi
    else
	setup_rootfs ${rootfs}
    fi

    cached_config="${defconfig}:${fixup}"

    echo -n "running ..."

    # if we have a dtb file use it
    dtbcmd=""
    if [ -n "${dtb}" -a -f "${dtbfile}" ]
    then
	dtbcmd="-dtb ${dtbfile}"
    fi

    # Specify CPU if necssary
    cpucmd=""
    if [ -n "${cpu}" ]
    then
	cpucmd="-cpu ${cpu}"
    fi

    case ${mach} in
    "raspi2")
	${QEMU_V26} -M ${mach} \
	    -kernel arch/arm/boot/zImage -no-reboot \
	    -drive file=${rootfs},format=raw,if=sd \
	    --append "root=/dev/mmcblk0 rootwait rw earlyprintk console=ttyAMA0 doreboot" \
	    ${dtbcmd} \
	    -nographic -monitor null -serial stdio \
	    > ${logfile} 2>&1 &
	pid=$!
	;;
    "collie")
	${QEMU} -M ${mach} \
	    -kernel arch/arm/boot/zImage -no-reboot \
	    -initrd ${rootfs} \
	    --append "rdinit=/sbin/init console=ttySA1 doreboot" \
	    -monitor null -nographic \
	    > ${logfile} 2>&1 &
	pid=$!
	;;
    "mainstone" | "z2")
        dd if=/dev/zero of=/tmp/flash bs=262144 count=128 >/dev/null 2>&1
	# dd if=${rootfs} of=/tmp/flash bs=262144 seek=17 conv=notrunc
	# then boot from /dev/mtdblock2 (requires mtd to be built into kernel)
	${QEMU} -M ${mach} ${cpucmd} \
	    -kernel arch/arm/boot/zImage -no-reboot \
	    -initrd ${rootfs} \
	    -drive file=/tmp/flash,format=raw,if=pflash \
	    -drive file=/tmp/flash,format=raw,if=pflash \
	    --append "rdinit=/sbin/init console=ttyS0 doreboot" \
	    -monitor null -nographic \
	    > ${logfile} 2>&1 &
	pid=$!
	;;
    "akita" | "borzoi" | "spitz" | "tosa" | "terrier")
	${QEMU} -M ${mach} ${cpucmd} \
	    -kernel arch/arm/boot/zImage -no-reboot \
	    -initrd ${rootfs} \
	    --append "rdinit=/sbin/init console=ttyS0 doreboot" \
	    -monitor null -nographic \
	    > ${logfile} 2>&1 &
	pid=$!
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
	/opt/buildbot/bin/linaro/qemu-system-arm -M ${mach} \
	    -m ${mem} -clock unix -no-reboot \
	    -drive file=sd.img,format=raw,if=sd,cache=writeback \
	    -device usb-mouse -device usb-kbd \
	    -serial stdio -monitor none -nographic \
	    > ${logfile} 2>&1 &
	pid=$!
        ;;
    "kzm" | "imx25-pdk" )
	${QEMU} -M ${mach} \
	    -kernel arch/arm/boot/zImage  -no-reboot \
	    -initrd ${rootfs} \
	    -append "rdinit=/sbin/init console=ttymxc0,115200 doreboot" \
	    -nographic -monitor none -serial stdio \
	    ${dtbcmd} > ${logfile} 2>&1 &
	pid=$!
	;;
    "smdkc210")
	${QEMU} -M ${mach} -smp 2 \
	    -kernel arch/arm/boot/zImage -no-reboot \
	    -initrd ${rootfs} \
	    -append "rdinit=/sbin/init console=ttySAC0,115200n8 doreboot" \
	    -nographic -monitor none -serial stdio \
	    ${dtbcmd} > ${logfile} 2>&1 &
	pid=$!
	;;
    "xilinx-zynq-a9")
	${QEMU} -M ${mach} \
	    -kernel arch/arm/boot/zImage -no-reboot \
	    -drive file=${rootfs},format=raw,if=sd \
	    -append "root=/dev/mmcblk0 rootwait rw console=ttyPS0 doreboot" \
	    -nographic -monitor none -serial null -serial stdio \
	    ${dtbcmd} > ${logfile} 2>&1 &
	pid=$!
	;;
    "realview-pb-a8" | "realview-eb-mpcore" | "realview-eb" | \
    "versatileab" | "versatilepb" | "highbank" | "midway" | "integratorcp")
	${QEMU} -M ${mach} ${cpucmd} -m ${mem} \
	    -kernel arch/arm/boot/zImage -no-reboot \
	    -initrd ${rootfs} \
	    --append "rdinit=/sbin/init console=ttyAMA0,115200 doreboot" \
	    -serial stdio -monitor null -nographic \
	    ${dtbcmd} > ${logfile} 2>&1 &
	pid=$!
	;;
    "versatilepb-scsi" )
	${QEMU} -M versatilepb -m 128 \
	    -kernel arch/arm/boot/zImage -no-reboot \
	    -drive file=${rootfs},format=raw,if=scsi \
	    --append "root=/dev/sda rw mem=128M console=ttyAMA0,115200 console=tty doreboot" \
	    -nographic -serial stdio -monitor null \
	    ${dtbcmd} > ${logfile} 2>&1 &
	pid=$!
	;;
    "vexpress-a9" | "vexpress-a15")
	${QEMU} -M ${mach} \
	    -kernel arch/arm/boot/zImage -no-reboot \
	    -drive file=${rootfs},format=raw,if=sd \
	    -append "root=/dev/mmcblk0 rootwait rw console=ttyAMA0,115200 console=tty1 doreboot" \
	    -nographic ${dtbcmd} > ${logfile} 2>&1 &
	pid=$!
	;;
    *)
	echo "Missing build recipe for machine ${mach}"
	exit 1
    esac

    dowait ${pid} ${logfile} ${mode} waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel versatile_defconfig versatilepb-scsi "" 128 \
	core-image-minimal-qemuarm.ext3 auto versatile versatile-pb.dtb
retcode=$?

runkernel versatile_defconfig versatileab "" 128 \
	core-image-minimal-qemuarm.cpio auto devtmpfs versatile-ab.dtb
retcode=$((${retcode} + $?))
runkernel versatile_defconfig versatilepb "" 128 \
	core-image-minimal-qemuarm.cpio auto devtmpfs versatile-pb.dtb
retcode=$((${retcode} + $?))

runkernel vexpress_defconfig vexpress-a9 "" 128 \
	core-image-minimal-qemuarm.ext3 auto regulator vexpress-v2p-ca9.dtb
retcode=$((${retcode} + $?))
runkernel vexpress_defconfig vexpress-a15 "" 128 \
	core-image-minimal-qemuarm.ext3 auto regulator vexpress-v2p-ca15-tc1.dtb
retcode=$((${retcode} + $?))

runkernel imx_v4_v5_defconfig imx25-pdk "" 128 \
	core-image-minimal-qemuarm.cpio manual imx25 imx25-pdk.dtb
retcode=$((${retcode} + $?))

runkernel imx_v6_v7_defconfig kzm "" 128 \
	core-image-minimal-qemuarm.cpio manual
retcode=$((${retcode} + $?))

runkernel multi_v7_defconfig beagle "" 256 \
	core-image-minimal-qemuarm.cpio auto "" omap3-beagle.dtb
retcode=$((${retcode} + $?))
runkernel multi_v7_defconfig beaglexm "" 512 \
	core-image-minimal-qemuarm.cpio auto "" omap3-beagle-xm.dtb
retcode=$((${retcode} + $?))
runkernel multi_v7_defconfig overo "" 256 \
	core-image-minimal-qemuarm.cpio auto "" omap3-overo-tobi.dtb
retcode=$((${retcode} + $?))

runkernel multi_v7_defconfig vexpress-a9 "" 128 \
	core-image-minimal-qemuarm.ext3 auto "" vexpress-v2p-ca9.dtb
retcode=$((${retcode} + $?))
runkernel multi_v7_defconfig vexpress-a15 "" 128 \
	core-image-minimal-qemuarm.ext3 auto "" vexpress-v2p-ca15-tc1.dtb
retcode=$((${retcode} + $?))

runkernel multi_v7_defconfig xilinx-zynq-a9 "" 128 \
	core-image-minimal-qemuarm.ext3 auto "" zynq-zc702.dtb
retcode=$((${retcode} + $?))
runkernel multi_v7_defconfig xilinx-zynq-a9 "" 128 \
	core-image-minimal-qemuarm.ext3 auto "" zynq-zc706.dtb
retcode=$((${retcode} + $?))
runkernel multi_v7_defconfig xilinx-zynq-a9 "" 128 \
	core-image-minimal-qemuarm.ext3 auto "" zynq-zed.dtb
retcode=$((${retcode} + $?))

# Disabled by default for now due to warnings from uart driver (qemu 2.6.0-rc3).
# Underlying problem is that cprman is not implemented in qemu. The uart
# clock is derived from it, and reports a clock rate of 0.

if [ ${runall} -eq 1 ]
then
    runkernel multi_v7_defconfig raspi2 "" "" \
	core-image-minimal-qemuarm.ext3 manual "" bcm2836-rpi-2-b.dtb
    retcode=$((${retcode} + $?))
fi

# highbank boots with updated qemu, but generates warnings to the console
# due to ignored SMC calls. Also, the highbank dts file uses CPU IDs
# starting with 0x900, which isn't supported by qemu. As a result, the boot
# CPU is not detected, which causes a warning in kernels prior to v3.14.

if [ ${runall} -eq 1 ]
then
    runkernel multi_v7_defconfig highbank cortex-a9 2G \
	core-image-minimal-qemuarm.cpio auto "" highbank.dtb
    retcode=$((${retcode} + $?))
fi

runkernel multi_v7_defconfig midway "" 2G \
	core-image-minimal-qemuarm.cpio auto devtmpfs ecx-2000.dtb
retcode=$((${retcode} + $?))

runkernel multi_v7_defconfig smdkc210 "" 128 \
	core-image-minimal-qemuarm.cpio manual cpuidle exynos4210-smdkv310.dtb
retcode=$((${retcode} + $?))

runkernel exynos_defconfig smdkc210 "" 128 \
	core-image-minimal-qemuarm.cpio manual cpuidle exynos4210-smdkv310.dtb
retcode=$((${retcode} + $?))

runkernel omap2plus_defconfig beagle "" 256 \
	core-image-minimal-qemuarm.cpio auto "" omap3-beagle.dtb
retcode=$((${retcode} + $?))
runkernel omap2plus_defconfig beaglexm "" 512 \
	core-image-minimal-qemuarm.cpio auto "" omap3-beagle-xm.dtb
retcode=$((${retcode} + $?))
runkernel omap2plus_defconfig overo "" 256 \
	core-image-minimal-qemuarm.cpio auto "" omap3-overo-tobi.dtb
retcode=$((${retcode} + $?))

runkernel realview_defconfig realview-pb-a8 "" 512 \
	busybox-arm.cpio auto realview_pb
retcode=$((${retcode} + $?))

runkernel realview_defconfig realview-eb cortex-a8 512 \
	core-image-minimal-qemuarm.cpio manual realview_eb
retcode=$((${retcode} + $?))
runkernel realview_defconfig realview-eb-mpcore "" 512 \
	core-image-minimal-qemuarm.cpio manual realview_eb
retcode=$((${retcode} + $?))

runkernel realview-smp_defconfig realview-eb-mpcore "" 512 \
	core-image-minimal-qemuarm.cpio manual realview_eb
retcode=$((${retcode} + $?))

runkernel mainstone_defconfig mainstone "" "" \
	core-image-minimal-qemuarm.cpio automatic pxa
retcode=$((${retcode} + $?))

runkernel spitz_defconfig akita "" "" \
	core-image-minimal-qemuarm.cpio automatic pxa
retcode=$((${retcode} + $?))

runkernel spitz_defconfig spitz "" "" \
	core-image-minimal-qemuarm.cpio automatic pxa
retcode=$((${retcode} + $?))

runkernel pxa_defconfig akita "" "" \
	core-image-minimal-qemuarm.cpio automatic
retcode=$((${retcode} + $?))

runkernel pxa_defconfig borzoi "" "" \
	core-image-minimal-qemuarm.cpio automatic
retcode=$((${retcode} + $?))

runkernel pxa_defconfig mainstone "" "" \
	core-image-minimal-qemuarm.cpio automatic
retcode=$((${retcode} + $?))

runkernel pxa_defconfig spitz "" "" \
	core-image-minimal-qemuarm.cpio automatic
retcode=$((${retcode} + $?))

runkernel pxa_defconfig terrier "" "" \
	core-image-minimal-qemuarm.cpio automatic
retcode=$((${retcode} + $?))

runkernel pxa_defconfig tosa "" "" \
	core-image-minimal-qemuarm.cpio automatic
retcode=$((${retcode} + $?))

runkernel pxa_defconfig z2 "" "" \
	core-image-minimal-qemuarm.cpio automatic
retcode=$((${retcode} + $?))

runkernel collie_defconfig collie "" "" \
	busybox-armv4.cpio manual collie
retcode=$((${retcode} + $?))

runkernel integrator_defconfig integratorcp "" 128 \
	busybox-armv4.cpio automatic devtmpfs integratorcp.dtb
    retcode=$((${retcode} + $?))

exit ${retcode}
