#!/bin/bash

PREFIX=arm-poky-linux-gnueabi-
ARCH=arm
# PATH_ARM=/opt/poky/1.3/sysroots/x86_64-pokysdk-linux/usr/bin/armv5te-poky-linux-gnueabi
PATH_ARM=/opt/poky/1.4.2/sysroots/x86_64-pokysdk-linux/usr/bin/armv7a-vfp-neon-poky-linux-gnueabi

PATH=${PATH_ARM}:${PATH}

dir=$(cd $(dirname $0); pwd)

# multi_v7_defconfig only exists starting with v3.10.
# versatileab/versatilepb need different binaries prior to 3.14.

skip_32="arm:highbank:multi_v7_defconfig \
	arm:kzm:imx_v6_v7_defconfig \
	arm:smdkc210:exynos_defconfig \
	arm:smdkc210:multi_v7_defconfig \
	arm:versatileab:versatile_defconfig \
	arm:versatilepb:versatile_defconfig \
	arm:vexpress-a9:multi_v7_defconfig \
	arm:vexpress-a15:multi_v7_defconfig \
	arm:vexpress-a15:qemu_arm_vexpress_defconfig \
	arm:xilinx-zynq-a9:multi_v7_defconfig"
skip_34="arm:highbank:multi_v7_defconfig \
	arm:smdkc210:exynos_defconfig \
	arm:smdkc210:multi_v7_defconfig \
	arm:versatileab:versatile_defconfig \
	arm:versatilepb:versatile_defconfig \
	arm:versatilepb-qemu:qemu_arm_versatile_defconfig \
	arm:vexpress-a9:multi_v7_defconfig \
	arm:vexpress-a15:multi_v7_defconfig \
	arm:vexpress-a15:qemu_arm_vexpress_defconfig \
	arm:xilinx-zynq-a9:multi_v7_defconfig"
skip_310="arm:smdkc210:multi_v7_defconfig \
	arm:versatileab:versatile_defconfig \
	arm:versatilepb:versatile_defconfig \
	arm:vexpress-a9:multi_v7_defconfig \
	arm:vexpress-a15:multi_v7_defconfig \
	arm:xilinx-zynq-a9:multi_v7_defconfig"
skip_312="arm:smdkc210:multi_v7_defconfig \
	arm:versatileab:versatile_defconfig \
	arm:versatilepb:versatile_defconfig \
	arm:xilinx-zynq-a9:multi_v7_defconfig"
skip_314="arm:smdkc210:multi_v7_defconfig \
	arm:xilinx-zynq-a9:multi_v7_defconfig"
skip_318="arm:smdkc210:multi_v7_defconfig"

. ${dir}/../scripts/common.sh

cached_config=""

patch_defconfig()
{
    local defconfig=$1
    local fixup=$2

    # We need DEVTMPFS for initrd images.

    if [ "${fixup}" = "devtmpfs" ]
    then
	sed -i -e '/CONFIG_DEVTMPFS/d' ${defconfig}
	echo "CONFIG_DEVTMPFS=y" >> ${defconfig}
    fi

    # CPUIDLE causes Exynos targets to run really slow.

    if [ "${fixup}" = "cpuidle" ]
    then
	sed -i -e '/CONFIG_CPU_IDLE/d' ${defconfig}
	sed -i -e '/CONFIG_ARM_EXYNOS_CPUIDLE/d' ${defconfig}
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

    if [ -n "${dtb}" ]
    then
	pbuild="${build}:$(echo ${dtb} | sed -e 's/.dtb//')"
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
    "kzm")
	/opt/buildbot/bin/qemu-system-arm -M ${mach} \
	    -kernel arch/arm/boot/zImage  -no-reboot \
	    -initrd ${rootfs} \
	    -append "rdinit=/sbin/init console=ttymxc0,115200 doreboot" \
	    -nographic -monitor none -serial stdio \
	    ${dtbcmd} > ${logfile} 2>&1 &
	pid=$!
	;;
    "smdkc210")
	/opt/buildbot/bin/qemu-system-arm -M ${mach} -smp 2 \
	    -kernel arch/arm/boot/zImage -no-reboot \
	    -initrd ${rootfs} \
	    -append "rdinit=/sbin/init console=ttySAC0,115200n8 doreboot" \
	    -nographic -monitor none -serial stdio \
	    ${dtbcmd} > ${logfile} 2>&1 &
	pid=$!
	;;
    "xilinx-zynq-a9")
	/opt/buildbot/bin/qemu-system-arm -M ${mach} \
	    -kernel arch/arm/boot/zImage -no-reboot \
	    -drive file=${rootfs},if=sd \
	    -append "root=/dev/mmcblk0 rw console=ttyPS0 doreboot" \
	    -nographic -monitor none -serial null -serial stdio \
	    ${dtbcmd} > ${logfile} 2>&1 &
	pid=$!
	;;
    "realview-pb-a8" | "realview-eb-mpcore" | "realview-eb" | \
    "versatileab" | "versatilepb" | "highbank" )
	/opt/buildbot/bin/qemu-system-arm -M ${mach} ${cpucmd} -m ${mem} \
	    -kernel arch/arm/boot/zImage -no-reboot \
	    -initrd ${rootfs} \
	    --append "rdinit=/sbin/init console=ttyAMA0,115200 doreboot" \
	    -serial stdio -monitor null -nographic \
	    ${dtbcmd} > ${logfile} 2>&1 &
	pid=$!
	;;
    "versatilepb-qemu")
	/opt/buildbot/bin/qemu-system-arm -M versatilepb -m 128 \
	    -kernel arch/arm/boot/zImage -no-reboot \
	    -drive file=${rootfs},if=scsi \
	    --append "root=/dev/sda rw mem=128M console=ttyAMA0,115200 console=tty doreboot" \
	    -nographic -serial stdio -monitor null \
	    ${dtbcmd} > ${logfile} 2>&1 &
	pid=$!
	;;
    "vexpress-a9" | "vexpress-a15")
	/opt/buildbot/bin/qemu-system-arm -M ${mach} \
	    -kernel arch/arm/boot/zImage -no-reboot \
	    -drive file=${rootfs},if=sd \
	    -append "root=/dev/mmcblk0 rw console=ttyAMA0,115200 console=tty1 doreboot" \
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

runkernel qemu_arm_versatile_defconfig versatilepb-qemu "" 128 \
	core-image-minimal-qemuarm.ext3 auto
retcode=$?

runkernel versatile_defconfig versatileab "" 128 \
	core-image-minimal-qemuarm.cpio auto devtmpfs
retcode=$((${retcode} + $?))
runkernel versatile_defconfig versatilepb "" 128 \
	core-image-minimal-qemuarm.cpio auto devtmpfs
retcode=$((${retcode} + $?))

runkernel qemu_arm_vexpress_defconfig vexpress-a9 "" 128 \
	core-image-minimal-qemuarm.ext3 auto "" vexpress-v2p-ca9.dtb
retcode=$((${retcode} + $?))
runkernel qemu_arm_vexpress_defconfig vexpress-a15 "" 128 \
	core-image-minimal-qemuarm.ext3 auto "" vexpress-v2p-ca15-tc1.dtb
retcode=$((${retcode} + $?))

runkernel imx_v6_v7_defconfig kzm "" 128 \
	core-image-minimal-qemuarm.cpio manual
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

# highbank boots with updated qemu, but generates warnings to the console
# due to ignored SMC calls. Also, the highbank dts file uses CPU IDs
# starting with 0x900, which isn't supported by qemu. As a result, the boot
# CPU is not detected, which causes a warning in kernels prior to v3.14.
# This is distracting, so disable for now.
# runkernel multi_v7_defconfig highbank cortex-a9 2G \
# 	core-image-minimal-qemuarm.cpio auto "" highbank.dtb
# retcode=$((${retcode} + $?))

# smdkc210 stopped working in -next; it now requires DMA support
# on serial lines which qemu does not support.
# runkernel multi_v7_defconfig smdkc210 "" 128 \
# 	core-image-minimal-qemuarm.cpio manual cpuidle exynos4210-smdkv310.dtb
# retcode=$((${retcode} + $?))
# runkernel exynos_defconfig smdkc210 "" 128 \
# 	core-image-minimal-qemuarm.cpio manual cpuidle exynos4210-smdkv310.dtb
# retcode=$((${retcode} + $?))

runkernel qemu_arm_realview_pb_defconfig realview-pb-a8 "" 512 \
	busybox-arm.cpio auto
retcode=$((${retcode} + $?))

runkernel qemu_arm_realview_eb_defconfig realview-eb-mpcore "" 512 \
	core-image-minimal-qemuarm.cpio manual
retcode=$((${retcode} + $?))
runkernel qemu_arm_realview_eb_defconfig realview-eb cortex-a8 512 \
	core-image-minimal-qemuarm.cpio manual
retcode=$((${retcode} + $?))

exit ${retcode}
