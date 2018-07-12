#!/bin/bash

machine=$1
variant=$2
config=$3

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh
QEMU=${QEMU:-${QEMU_BIN}/qemu-system-ppc}

# machine specific information
# PATH_PPC=/opt/poky/1.4.0-1/sysroots/x86_64-pokysdk-linux/usr/bin/ppc64e5500-poky-linux
PATH_PPC=/opt/poky/1.5.1/sysroots/x86_64-pokysdk-linux/usr/bin/powerpc64-poky-linux
PREFIX=powerpc64-poky-linux-
ARCH=powerpc
QEMU_MACH=mac99

PATH=${PATH_PPC}:${PATH}

patch_defconfig()
{
    local defconfig=$1
    local fixups=${2//:/ }
    local fixup

    for fixup in ${fixups}; do
	if [ "${fixup}" = "devtmpfs" ]; then
	    echo "CONFIG_DEVTMPFS=y" >> ${defconfig}
	fi
	if [ "${fixup}" = "nosmp" ]; then
	    echo "CONFIG_SMP=n" >> ${defconfig}
	fi
	if [ "${fixup}" = "smp" ]; then
	    echo "CONFIG_SMP=y" >> ${defconfig}
	fi
    done
}

cached_defconfig=""

runkernel()
{
    local defconfig=$1
    local fixup=$2
    local mach=$3
    local cpu=$4
    local rootfs=$5
    local kernel=$6
    local dts=$7
    local dtb
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Restarting" "Boot successful" "Rebooting")
    local smp
    local pbuild

    if [ -n "${fixup}" ]; then
	smp=":${fixup}"
    fi

    pbuild="${ARCH}:${mach}${smp}:${defconfig}"

    if [ -n "${machine}" -a "${machine}" != "${mach}" ]
    then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    if [ -n "${variant}" -a "${variant}" != "${fixup}" ]
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

    if [ "${defconfig}_${fixup}" != "${cached_defconfig}" ]
    then
	dosetup -f "${fixup}" "${rootfs}" "${defconfig}"
	retcode=$?
	if [ ${retcode} -ne 0 ]
	then
	    if [ ${retcode} -eq 2 ]
	    then
		return 0
	    fi
	    return 1
	fi
	cached_defconfig="${defconfig}_${fixup}"
    else
	setup_rootfs "${rootfs}"
    fi

    if [[ "${rootfs}" == *.gz ]]; then
	gunzip -f "${rootfs}"
	rootfs="${rootfs%.gz}"
    fi

    echo -n "running ..."

    if [[ "${rootfs}" == *ext2 ]]; then
	${QEMU} -kernel ${kernel} -M ${mach} -cpu ${cpu} \
	    -drive file=${rootfs},format=raw,if=ide \
	    -usb -usbdevice wacom-tablet -no-reboot -m 128 \
	    --append "root=/dev/hda rw mem=128M console=ttyS0 console=tty doreboot" \
	    -nographic > ${logfile} 2>&1 &
    else
	dtbcmd=""
	if [ -n "${dts}" -a -e "${dts}" ]
	then
	    dtb=$(echo ${dts} | sed -e 's/\.dts/\.dtb/')
	    dtbcmd="-dtb ${dtb}"
	    dtc -I dts -O dtb ${dts} -o ${dtb} >/dev/null 2>&1
	fi
	${QEMU} -kernel ${kernel} -M ${mach} -no-reboot -m 256 \
	    --append "rdinit=/sbin/init console=ttyS0 console=tty doreboot" \
	    ${dtbcmd} -monitor none -nographic \
	    -initrd ${rootfs} > ${logfile} 2>&1 &
    fi

    pid=$!

    dowait ${pid} ${logfile} automatic waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

VIRTEX440_DTS=arch/powerpc/boot/dts/virtex440-ml507.dts

runkernel qemu_ppc_book3s_defconfig nosmp mac99 G4 rootfs.ext2.gz \
	vmlinux
retcode=$?
runkernel qemu_ppc_book3s_defconfig nosmp g3beige G3 rootfs.ext2.gz \
	vmlinux
retcode=$((${retcode} + $?))
runkernel qemu_ppc_book3s_defconfig smp mac99 G4 rootfs.ext2.gz \
	vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/virtex5_defconfig devtmpfs virtex-ml507 "" rootfs.cpio.gz \
	vmlinux ${VIRTEX440_DTS}
retcode=$((${retcode} + $?))
runkernel mpc85xx_defconfig "" mpc8544ds "" rootfs.cpio.gz arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
runkernel mpc85xx_smp_defconfig "" mpc8544ds "" rootfs.cpio.gz arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
runkernel 44x/bamboo_defconfig devtmpfs bamboo "" rootfs.cpio.gz vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/bamboo_defconfig devtmpfs:smp bamboo "" rootfs.cpio.gz vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/canyonlands_defconfig devtmpfs sam460ex "" rootfs.cpio.gz vmlinux
retcode=$((${retcode} + $?))

exit ${retcode}
