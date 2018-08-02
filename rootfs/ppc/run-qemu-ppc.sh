#!/bin/bash

shopt -s extglob

progdir=$(cd $(dirname $0); pwd)
. ${progdir}/../scripts/config.sh
. ${progdir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

machine=$1
variant=$2
config=$3

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-ppc}

# machine specific information
# PATH_PPC=/opt/poky/1.4.0-1/sysroots/x86_64-pokysdk-linux/usr/bin/ppc64e5500-poky-linux
PATH_PPC=/opt/poky/1.5.1/sysroots/x86_64-pokysdk-linux/usr/bin/powerpc64-poky-linux
PREFIX=powerpc64-poky-linux-
ARCH=powerpc
QEMU_MACH=mac99

PATH=${PATH_PPC}:${PATH}

skip_316="powerpc:mpc8544ds:mpc85xx_defconfig:scsi:rootfs \
	powerpc:mpc8544ds:mpc85xx_defconfig:sata:rootfs \
	powerpc:mpc8544ds:mpc85xx_smp_defconfig:scsi:rootfs \
	powerpc:mpc8544ds:mpc85xx_smp_defconfig:sata:rootfs"

skip_318="powerpc:mpc8544ds:mpc85xx_defconfig:scsi:rootfs \
	powerpc:mpc8544ds:mpc85xx_defconfig:sata:rootfs \
	powerpc:mpc8544ds:mpc85xx_smp_defconfig:scsi:rootfs \
	powerpc:mpc8544ds:mpc85xx_smp_defconfig:sata:rootfs"

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
	if [ "${fixup}" = "scsi[AM53C974]" ]; then
	    echo "CONFIG_SCSI=y" >> ${defconfig}
	    echo "CONFIG_BLK_DEV_SD=y" >> ${defconfig}
	    echo "CONFIG_SCSI_AM53C974=y" >> ${defconfig}
	fi
	if [ "${fixup}" = "usbdisk" ]; then
	    echo "CONFIG_SCSI=y" >> ${defconfig}
	    echo "CONFIG_BLK_DEV_SD=y" >> ${defconfig}
	    echo "CONFIG_USB_STORAGE=y" >> ${defconfig}
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
    local pbuild="${ARCH}:${mach}:${defconfig}"
    local build="${defconfig}"
    local diskcmd
    local cli

    if [ -n "${fixup}" ]; then
	pbuild="${pbuild}:${fixup}"
	# ignore basic scsi/sata build qualifiers for build cache
	if [[ ${fixup} != "sata" && ${fixup} != "scsi" ]]; then
	    build+="${fixup}"
	fi
    fi
    if [[ "${rootfs%.gz}" == *cpio ]]; then
	# For initrd builds, disk build qualifiers are irrelevant for the user
	pbuild="${pbuild%:+(sata|usbdisk|scsi*)}:initrd"
    else
	pbuild+=":rootfs"
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

    if [ "${build}" != "${cached_defconfig}" ]
    then
	dosetup -f "${fixup}" -b "${pbuild}" "${rootfs}" "${defconfig}"
	retcode=$?
	if [ ${retcode} -ne 0 ]
	then
	    if [ ${retcode} -eq 2 ]
	    then
		return 0
	    fi
	    return 1
	fi
	cached_defconfig="${build}"
    else
	if ! checkskip "${pbuild}"; then
	    return 0
	fi
	setup_rootfs "${rootfs}"
    fi

    rootfs="${rootfs%.gz}"

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
	local if="if=ide"
	local extra=""
	local extracli=""
	local rootdev="sda"
	if grep -q "CONFIG_IDE=y" .config; then
	    rootdev=hda
	fi
	if [[ "${fixup}" == *scsi ]]; then
	    if="id=d0"
	    extra="-device lsi53c895a -device scsi-hd,drive=d0"
	    rootdev="sda"
	elif [[ "${fixup}" == *scsi\[AM53C974\] ]]; then
	    if="id=d0"
	    extra="-device am53c974 -device scsi-hd,drive=d0"
	    rootdev="sda"
	elif [[ "${fixup}" == *sata* ]]; then
	    if="id=d0"
	    extra="-device sii3112 -device ide-hd,drive=d0"
	elif [[ "${fixup}" == *usbdisk* ]]; then
	    if="id=d0"
	    extra="-device usb-storage,drive=d0"
	    extracli="rootwait"
	fi
	diskcmd="${extra} -drive file=${rootfs},format=raw,${if}"
	cli="root=/dev/${rootdev} rw ${extracli}"
    fi

    case "${mach}" in
    sam460ex)
	# Fails with v4.4.y
	# earlycon="earlycon=uart8250,mmio,0x4ef600300,115200n8"
	;;
    virtex-ml507)
	# fails with v4.4.y
	# earlycon="earlycon"
	;;
    bamboo|mpc8544ds)
	# Not needed
        earlycon=""
	;;
    *)
        earlycon=""
	;;
    esac

    [[ ${dodebug} -ne 0 ]] && set -x

    ${QEMU} -kernel ${kernel} -M ${mach} -m 256 ${cpu} -no-reboot \
	${diskcmd} \
	${dtbcmd} \
	--append "${cli} ${earlycon} mem=256M console=${tty}" \
	-monitor none -nographic > ${logfile} 2>&1 &
    pid=$!

    [[ ${dodebug} -ne 0 ]] && set +x

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
runkernel mpc85xx_defconfig scsi mpc8544ds "" ttyS0 rootfs.ext2.gz arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
runkernel mpc85xx_defconfig sata mpc8544ds "" ttyS0 rootfs.ext2.gz arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
runkernel mpc85xx_smp_defconfig "" mpc8544ds "" ttyS0 rootfs.cpio.gz arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
runkernel mpc85xx_smp_defconfig scsi mpc8544ds "" ttyS0 rootfs.ext2.gz arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
runkernel mpc85xx_smp_defconfig sata mpc8544ds "" ttyS0 rootfs.ext2.gz arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
# specify scsi[AM53C974] for initrd to avoid rebuilding the image.
runkernel 44x/bamboo_defconfig "devtmpfs:scsi[AM53C974]" bamboo "" ttyS0 rootfs.cpio.gz vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/bamboo_defconfig "devtmpfs:scsi[AM53C974]" bamboo "" ttyS0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/bamboo_defconfig "devtmpfs:smp:scsi[AM53C974]"  bamboo "" ttyS0 rootfs.cpio.gz vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/bamboo_defconfig "devtmpfs:smp:scsi[AM53C974]" bamboo "" ttyS0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))
# specify usbdisk for initrd to avoid rebuilding the image.
runkernel 44x/canyonlands_defconfig devtmpfs:usbdisk sam460ex "" ttyS0 rootfs.cpio.gz vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/canyonlands_defconfig devtmpfs:usbdisk sam460ex "" ttyS0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))
runkernel pmac32_defconfig devtmpfs:zilog mac99 "" ttyPZ0 rootfs.cpio.gz vmlinux
retcode=$((${retcode} + $?))
runkernel pmac32_defconfig devtmpfs:zilog mac99 "" ttyPZ0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))

exit ${retcode}
