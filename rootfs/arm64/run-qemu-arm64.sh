#!/bin/bash

machine=$1
config=$2

QEMU=${QEMU:-/opt/buildbot/qemu-install/v2.7/bin/qemu-system-aarch64}
PREFIX=aarch64-linux-
ARCH=arm64
PATH_ARM64=/opt/kernel/aarch64/gcc-5.2/usr/bin

PATH=${PATH_ARM64}:${PATH}

dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

skip_32="arm64:xlnx-ep108:smp:defconfig \
	arm64:xlnx-ep108:nosmp:defconfig"
skip_34="arm64:xlnx-ep108:smp:defconfig \
	arm64:xlnx-ep108:nosmp:defconfig"
skip_310="arm64:xlnx-ep108:smp:defconfig \
	arm64:xlnx-ep108:nosmp:defconfig"
skip_312="arm64:xlnx-ep108:smp:defconfig \
	arm64:xlnx-ep108:nosmp:defconfig"
skip_316="arm64:xlnx-ep108:smp:defconfig \
	arm64:xlnx-ep108:nosmp:defconfig"
skip_318="arm64:xlnx-ep108:smp:defconfig \
	arm64:xlnx-ep108:nosmp:defconfig"

patch_defconfig()
{
    local defconfig=$1
    local fixup=$2

    sed -i -e '/CONFIG_SMP/d' ${defconfig}

    if [ "${fixup}" = "nosmp" ]
    then
	echo "# CONFIG_SMP is not set" >> ${defconfig}
    else
	echo "CONFIG_SMP=y" >> ${defconfig}
    fi
}

runkernel()
{
    local mach=$1
    local defconfig=$2
    local fixup=$3
    local rootfs=$4
    local dtb=$5
    local ddtb=$(basename -s .dtb ""${dtb})
    local dtbfile="arch/arm64/boot/dts/${dtb}"
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Restarting system" "Boot successful" "Rebooting")
    local build=${ARCH}:${mach}:${fixup}:${defconfig}
    local pbuild=${build}
    local rel=$(git describe | cut -f1 -d- | cut -f1,2 -d. | sed -e 's/\.//' | sed -e 's/v//')
    local tmp="skip_${rel}"
    local skip=(${!tmp})

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
	dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig} generic ${fixup}
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

    # if we have a dtb file use it
    local dtbcmd=""
    if [ -n "${dtb}" -a -f "${dtbfile}" ]
    then
	dtbcmd="-dtb ${dtbfile}"
    fi

    echo -n "running ..."

    case ${mach} in
    "virt")
	${QEMU} -machine ${mach} -cpu cortex-a57 \
	-machine type=virt -nographic -smp 1 -m 512 \
	-kernel arch/arm64/boot/Image -initrd ${rootfs} -no-reboot \
	-append "console=ttyAMA0" > ${logfile} 2>&1 &

	pid=$!
	dowait ${pid} ${logfile} manual waitlist[@]
	retcode=$?
	;;
    "xlnx-ep108")
	${QEMU} -M ${mach} -kernel arch/arm64/boot/Image -m 2048 \
		-nographic -serial mon:stdio \
		-monitor none \
		${dtbcmd} \
		-no-reboot -initrd ${rootfs} \
		--append "rdinit=/sbin/init console=ttyPS0 doreboot" \
		> ${logfile} 2>&1 &
	pid=$!
	dowait ${pid} ${logfile} automatic waitlist[@]
	retcode=$?
	;;
    esac

    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel virt defconfig smp rootfs.arm64.cpio
retcode=$?
# Needs changes in root file system to correctly handle reboot
runkernel xlnx-ep108 defconfig smp busybox-arm64.cpio xilinx/zynqmp-ep108.dtb
retcode=$((${retcode} + $?))
runkernel virt defconfig nosmp rootfs.arm64.cpio
retcode=$((${retcode} + $?))
runkernel xlnx-ep108 defconfig nosmp busybox-arm64.cpio xilinx/zynqmp-ep108.dtb
retcode=$((${retcode} + $?))

exit ${retcode}
