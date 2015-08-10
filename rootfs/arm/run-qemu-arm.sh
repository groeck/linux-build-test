#!/bin/bash

PREFIX=arm-poky-linux-gnueabi-
ARCH=arm
# PATH_ARM=/opt/poky/1.3/sysroots/x86_64-pokysdk-linux/usr/bin/armv5te-poky-linux-gnueabi
PATH_ARM=/opt/poky/1.4.2/sysroots/x86_64-pokysdk-linux/usr/bin/armv7a-vfp-neon-poky-linux-gnueabi

PATH=${PATH_ARM}:${PATH}

dir=$(cd $(dirname $0); pwd)

skip_32="arm:vexpress-a15:qemu_arm_vexpress_defconfig \
	arm:vexpress-a9:multi_v7_defconfig \
	arm:vexpress-a15:multi_v7_defconfig \
	arm:xilinx-zynq-a9:multi_v7_defconfig"
skip_34="arm:versatilepb:qemu_arm_versatile_defconfig \
	arm:vexpress-a15:qemu_arm_vexpress_defconfig \
	arm:vexpress-a9:multi_v7_defconfig \
	arm:vexpress-a15:multi_v7_defconfig \
	arm:xilinx-zynq-a9:multi_v7_defconfig"
skip_310="arm:vexpress-a9:multi_v7_defconfig \
	arm:vexpress-a15:multi_v7_defconfig \
	arm:xilinx-zynq-a9:multi_v7_defconfig"
skip_312="arm:xilinx-zynq-a9:multi_v7_defconfig"
skip_314="arm:xilinx-zynq-a9:multi_v7_defconfig"
skip_318="arm:xilinx-zynq-a9:multi_v7_defconfig"

. ${dir}/../scripts/common.sh

cached_config=""

runkernel()
{
    local defconfig=$1
    local mach=$2
    local cpu=$3
    local rootfs=$4
    local mode=$5
    local dtb=$6
    local dtbfile="arch/arm/boot/dts/${dtb}"
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Boot successful" "Rebooting" "Restarting")
    local rel=$(git describe | cut -f1 -d- | cut -f1,2 -d. | sed -e 's/\.//' | sed -e 's/v//')
    local tmp="skip_${rel}"
    local skip=(${!tmp})
    local s
    local build=${ARCH}:${mach}:${defconfig}

    echo -n "Building ${build} ... "

    for s in ${skip[*]}
    do
	if [ "$s" = "${build}" ]
	then
	    echo "skipped"
	    return 0
	fi
    done

    if [ "${cached_config}" != "${defconfig}" ]
    then
	# KALLSYMS_EXTRA_PASS is needed for earlier kernels (3.2, 3.4) due to
	# a bug in kallsyms which would be too difficult to back-port.
	# See upstream commits f6537f2f0e and 7122c3e915.
	dosetup ${ARCH} ${PREFIX} "KALLSYMS_EXTRA_PASS=1" ${rootfs} ${defconfig}
	retcode=$?
	if [ ${retcode} -ne 0 ]
	then
	    return 1
	fi
    fi

    cached_config=${defconfig}

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
    "xilinx-zynq-a9")
	/opt/buildbot/bin/qemu-system-arm -M ${mach} \
	    -kernel arch/arm/boot/zImage -no-reboot \
	    -drive file=${rootfs},if=sd \
	    -append "root=/dev/mmcblk0 rw console=ttyPS0 doreboot" \
	    -nographic -monitor none -serial null -serial stdio \
	    ${dtbcmd} > ${logfile} 2>&1 &
	pid=$!
	;;
    "realview-pb-a8" | "realview-eb-mpcore" | "realview-eb")
	/opt/buildbot/bin/qemu-system-arm -M ${mach} ${cpucmd} -m 512 \
	    -kernel arch/arm/boot/zImage -no-reboot \
	    -initrd ${rootfs} \
	    --append "rdinit=/sbin/init console=ttyAMA0,115200 doreboot" \
	    -serial stdio -monitor null -nographic \
	    ${dtbcmd} > ${logfile} 2>&1 &
	pid=$!
	;;
    "versatilepb")
	/opt/buildbot/bin/qemu-system-arm -M ${mach} -m 128 \
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

runkernel qemu_arm_versatile_defconfig versatilepb "" \
	core-image-minimal-qemuarm.ext3 auto
retcode=$?
runkernel qemu_arm_vexpress_defconfig vexpress-a9 "" \
	core-image-minimal-qemuarm.ext3 auto vexpress-v2p-ca9.dtb
retcode=$((${retcode} + $?))
runkernel qemu_arm_vexpress_defconfig vexpress-a15 "" \
	core-image-minimal-qemuarm.ext3 auto vexpress-v2p-ca15-tc1.dtb
retcode=$((${retcode} + $?))
runkernel multi_v7_defconfig vexpress-a9 "" \
	core-image-minimal-qemuarm.ext3 auto vexpress-v2p-ca9.dtb
retcode=$((${retcode} + $?))
runkernel multi_v7_defconfig vexpress-a15 "" \
	core-image-minimal-qemuarm.ext3 auto vexpress-v2p-ca15-tc1.dtb
retcode=$((${retcode} + $?))

runkernel multi_v7_defconfig xilinx-zynq-a9 "" \
	core-image-minimal-qemuarm.ext3 auto zynq-zc702.dtb
retcode=$((${retcode} + $?))

runkernel qemu_arm_realview_pb_defconfig realview-pb-a8 "" \
	busybox-arm.cpio auto
retcode=$((${retcode} + $?))
runkernel qemu_arm_realview_eb_defconfig realview-eb-mpcore "" \
	core-image-minimal-qemuarm.cpio manual
retcode=$((${retcode} + $?))
runkernel qemu_arm_realview_eb_defconfig realview-eb cortex-a8 \
	core-image-minimal-qemuarm.cpio manual
retcode=$((${retcode} + $?))

exit ${retcode}
