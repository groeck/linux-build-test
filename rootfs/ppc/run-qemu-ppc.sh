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
	if [ "${fixup}" = "zilog" ]; then
	    echo "CONFIG_SERIAL_PMACZILOG=y" >> ${defconfig}
	    echo "CONFIG_SERIAL_PMACZILOG_TTYS=n" >> ${defconfig}
	    echo "CONFIG_SERIAL_PMACZILOG_CONSOLE=y" >> ${defconfig}
	fi
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
    local tty=$5
    local rootfs=$6
    local kernel=$7
    local dts=$8
    local dtbcmd=""
    local pid
    local retcode
    local logfile="$(mktemp)"
    local waitlist=("Restarting" "Boot successful" "Rebooting")
    local pbuild="${mach}:${defconfig}"
    local diskcmd
    local cli

    if [ -n "${fixup}" ]; then
	pbuild="${pbuild}:${fixup}"
    fi
    if [[ "${rootfs%.gz}" == *cpio ]]; then
	pbuild+=":rootfs"
    else
	pbuild+=":initrd"
    fi

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

    if [[ -n "${cpu}" ]]; then
	cpu="-cpu ${cpu}"
    fi

    if [ -n "${dts}" -a -e "${dts}" ]; then
	local dtb="${dts/.dts/.dtb}"
	dtbcmd="-dtb ${dtb}"
	dtc -I dts -O dtb ${dts} -o ${dtb} >/dev/null 2>&1
    fi

    if [[ "${rootfs}" == *cpio ]]; then
	diskcmd="-initrd ${rootfs}"
	cli="rdinit=/sbin/init"
    else
	diskcmd="-drive file=${rootfs},format=raw,if=ide"
	local rootdev="sda"
	if grep -q "CONFIG_IDE=y" .config; then
	    rootdev=hda
	fi
	cli="root=/dev/${rootdev} rw"
    fi

    ${QEMU} -kernel ${kernel} -M ${mach} -m 256 ${cpu} -no-reboot \
	${diskcmd} \
	${dtbcmd} \
	--append "${cli} mem=256M console=${tty}" \
	-monitor none -nographic > ${logfile} 2>&1 &
    pid=$!

    dowait ${pid} ${logfile} automatic waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

VIRTEX440_DTS=arch/powerpc/boot/dts/virtex440-ml507.dts

runkernel qemu_ppc_book3s_defconfig nosmp mac99 G4 ttyS0 rootfs.ext2.gz \
	vmlinux
retcode=$?
runkernel qemu_ppc_book3s_defconfig nosmp g3beige G3 ttyS0 rootfs.ext2.gz \
	vmlinux
retcode=$((${retcode} + $?))
runkernel qemu_ppc_book3s_defconfig smp mac99 G4 ttyS0 rootfs.ext2.gz \
	vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/virtex5_defconfig devtmpfs virtex-ml507 "" ttyS0 rootfs.cpio.gz \
	vmlinux ${VIRTEX440_DTS}
retcode=$((${retcode} + $?))
runkernel mpc85xx_defconfig "" mpc8544ds "" ttyS0 rootfs.cpio.gz arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
runkernel mpc85xx_smp_defconfig "" mpc8544ds "" ttyS0 rootfs.cpio.gz arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
runkernel 44x/bamboo_defconfig devtmpfs bamboo "" ttyS0 rootfs.cpio.gz vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/bamboo_defconfig devtmpfs:smp bamboo "" ttyS0 rootfs.cpio.gz vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/canyonlands_defconfig devtmpfs sam460ex "" ttyS0 rootfs.cpio.gz vmlinux
retcode=$((${retcode} + $?))
runkernel pmac32_defconfig devtmpfs:zilog mac99 "" ttyPZ0 rootfs.cpio.gz vmlinux
retcode=$((${retcode} + $?))
runkernel pmac32_defconfig devtmpfs:zilog mac99 "" ttyPZ0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))

exit ${retcode}
