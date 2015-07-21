#!/bin/bash

PREFIX=arm-poky-linux-gnueabi-
ARCH=arm
rootfs=core-image-minimal-qemuarm.ext3
# PATH_ARM=/opt/poky/1.3/sysroots/x86_64-pokysdk-linux/usr/bin/armv5te-poky-linux-gnueabi
PATH_ARM=/opt/poky/1.4.2/sysroots/x86_64-pokysdk-linux/usr/bin/armv7a-vfp-neon-poky-linux-gnueabi

PATH=${PATH_ARM}:${PATH}

dir=$(cd $(dirname $0); pwd)

skip_34="arm:qemu_arm_versatile_defconfig"

. ${dir}/../scripts/common.sh

runkernel()
{
    local defconfig=$1
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Boot successful" "Rebooting" "Restarting")

    echo -n "Building ${ARCH}:${defconfig} ... "

    # KALLSYMS_EXTRA_PASS is needed for earlier kernels (3.2, 3.4) due to
    # a bug in kallsyms which would be too difficult to back-port.
    # See upstream commits f6537f2f0e and 7122c3e915.
    dosetup ${ARCH} ${PREFIX} "KALLSYMS_EXTRA_PASS=1" ${rootfs} ${defconfig}
    retcode=$?
    if [ ${retcode} -eq 2 ]
    then
        return 0
    fi
    if [ ${retcode} -ne 0 ]
    then
	return 1
    fi

    echo -n "running ..."

    if [ "${defconfig}" = "qemu_arm_versatile_defconfig" ]
    then
      /opt/buildbot/bin/qemu-system-arm  -M versatilepb \
	-kernel arch/arm/boot/zImage \
	-drive file=${rootfs},if=scsi -no-reboot \
	-m 128 \
	--append "root=/dev/sda rw mem=128M console=ttyAMA0,115200 console=tty doreboot" \
	-nographic > ${logfile} 2>&1 & 
      pid=$!
    else
      # if we have a dtb file use it
      # Note: vexpress-v2p-ca15_a7.dtb with "-M vexpress-a15" also works
      # with the same kernel and root file system.
      dtb=""
      if [ -e arch/arm/boot/dts/vexpress-v2p-ca9.dtb ]
      then
          dtb="-dtb arch/arm/boot/dts/vexpress-v2p-ca9.dtb"
      fi
      /opt/buildbot/bin/qemu-system-arm -M vexpress-a9 \
	-kernel arch/arm/boot/zImage \
	-drive file=${rootfs},if=sd -no-reboot \
	-append "root=/dev/mmcblk0 rw console=ttyAMA0,115200 console=tty1 doreboot" \
	-nographic ${dtb} > ${logfile} 2>&1 &
      pid=$!
    fi

    pid=$!
    dowait ${pid} ${logfile} auto waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel qemu_arm_versatile_defconfig
retcode=$?
runkernel qemu_arm_vexpress_defconfig
retcode=$((${retcode} + $?))

exit ${retcode}
