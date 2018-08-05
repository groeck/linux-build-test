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
	powerpc:mpc8544ds:mpc85xx_defconfig:sata-sii3112:rootfs \
	powerpc:mpc8544ds:mpc85xx_smp_defconfig:scsi:rootfs \
	powerpc:mpc8544ds:mpc85xx_smp_defconfig:sata-sii3112:rootfs"

skip_318="powerpc:mpc8544ds:mpc85xx_defconfig:scsi:rootfs \
	powerpc:mpc8544ds:mpc85xx_defconfig:sata-sii3112:rootfs \
	powerpc:mpc8544ds:mpc85xx_smp_defconfig:scsi:rootfs \
	powerpc:mpc8544ds:mpc85xx_smp_defconfig:sata-sii3112:rootfs \
	powerpc:mpc8544ds:mpc85xx_smp_defconfig:scsi[MEGASAS2]:rootfs \
	powerpc:bamboo:44x/bamboo_defconfig:smp:scsi[DC395]:rootfs \
	powerpc:bamboo:44x/bamboo_defconfig:scsi[AM53C974]:rootfs \
	powerpc:bamboo:44x/bamboo_defconfig:smp:scsi[AM53C974]:rootfs"

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
	if [ "${fixup}" = "nosmp" ]; then
	    echo "CONFIG_SMP=n" >> ${defconfig}
	fi
	if [ "${fixup}" = "smp" ]; then
	    echo "CONFIG_SMP=y" >> ${defconfig}
	fi
    done

    # Enable BLK_DEV_INITRD
    echo "CONFIG_BLK_DEV_INITRD=y" >> ${defconfig}

    # devtmpfs
    echo "CONFIG_DEVTMPFS=y" >> ${defconfig}
    echo "CONFIG_DEVTMPFS_MOUNT=y" >> ${defconfig}

    # MMC/SDHCI support
    echo "CONFIG_MMC=y" >> ${defconfig}
    echo "CONFIG_MMC_SDHCI=y" >> ${defconfig}
    echo "CONFIG_MMC_SDHCI_PCI=y" >> ${defconfig}

    # NVME
    echo "CONFIG_BLK_DEV_NVME=y" >> ${defconfig}

    # SCSI/USB
    echo "CONFIG_SCSI=y" >> ${defconfig}
    echo "CONFIG_BLK_DEV_SD=y" >> ${defconfig}

    # SCSI
    echo "CONFIG_SCSI_AM53C974=y" >> ${defconfig}
    echo "CONFIG_SCSI_DC395x=y" >> ${defconfig}
    echo "CONFIG_SCSI_SYM53C8XX_2=y" >> ${defconfig}
    echo "CONFIG_MEGARAID_SAS=y" >> ${defconfig}
    echo "CONFIG_FUSION=y" >> ${defconfig}
    echo "CONFIG_FUSION_SAS=y" >> ${defconfig}

    # USB
    echo "CONFIG_USB=y" >> ${defconfig}
    echo "CONFIG_USB_XHCI_HCD=y" >> ${defconfig}
    echo "CONFIG_USB_EHCI_HCD=y" >> ${defconfig}
    echo "CONFIG_USB_OHCI_HCD=y" >> ${defconfig}
    echo "CONFIG_USB_STORAGE=y" >> ${defconfig}
    echo "CONFIG_USB_UAS=y" >> ${defconfig}
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

    if [ -n "${fixup}" ]; then
	pbuild="${pbuild}:${fixup}"
	# ignore disk build qualifiers for build cache
	if [[ "${fixup##*:}" != sata* && "${fixup##*:}" != scsi* &&
	      "${fixup##*:}" != usb* && "${fixup##*:}" != "nvme" &&
	      "${fixup##*:}" != "mmc" ]]; then
	    build+="${fixup}"
	fi
    fi
    if [[ "${rootfs%.gz}" == *cpio ]]; then
	pbuild+=":initrd"
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

    if ! checkskip "${pbuild}"; then
	return 0
    fi

    if ! dosetup -c "${build}" -f "${fixup:-fixup}" "${rootfs}" "${defconfig}"; then
	return 1
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

    if ! common_diskcmd "${fixup##*:}" "${rootfs}"; then
	return 1
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
	--append "${initcli} ${earlycon} mem=256M console=${tty}" \
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

runkernel qemu_ppc_book3s_defconfig nosmp:ata mac99 G4 ttyS0 rootfs.ext2.gz \
	vmlinux
retcode=$?
runkernel qemu_ppc_book3s_defconfig nosmp:ata g3beige G3 ttyS0 rootfs.ext2.gz \
	vmlinux
retcode=$((${retcode} + $?))
runkernel qemu_ppc_book3s_defconfig smp:ata mac99 G4 ttyS0 rootfs.ext2.gz \
	vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/virtex5_defconfig "" virtex-ml507 "" ttyS0 rootfs.cpio.gz \
	vmlinux ${VIRTEX440_DTS}
retcode=$((${retcode} + $?))
runkernel mpc85xx_defconfig "" mpc8544ds "" ttyS0 rootfs.cpio.gz arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
runkernel mpc85xx_defconfig scsi[53C895A] mpc8544ds "" ttyS0 rootfs.ext2.gz arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
runkernel mpc85xx_defconfig sata-sii3112 mpc8544ds "" ttyS0 rootfs.ext2.gz arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
runkernel mpc85xx_defconfig mmc mpc8544ds "" ttyS0 rootfs.ext2.gz arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
if [[ ${runall} -ne 0 ]]; then
    # nvme nvme0: I/O 23 QID 0 timeout, completion polled
    runkernel mpc85xx_defconfig nvme mpc8544ds "" ttyS0 rootfs.ext2.gz arch/powerpc/boot/uImage
    retcode=$((${retcode} + $?))
fi
runkernel mpc85xx_smp_defconfig "" mpc8544ds "" ttyS0 rootfs.cpio.gz arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
runkernel mpc85xx_smp_defconfig scsi[MEGASAS2] mpc8544ds "" ttyS0 rootfs.ext2.gz arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
runkernel mpc85xx_smp_defconfig scsi[53C895A] mpc8544ds "" ttyS0 rootfs.ext2.gz arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
runkernel mpc85xx_smp_defconfig sata-sii3112 mpc8544ds "" ttyS0 rootfs.ext2.gz arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
runkernel 44x/bamboo_defconfig "" bamboo "" ttyS0 rootfs.cpio.gz vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/bamboo_defconfig "scsi[AM53C974]" bamboo "" ttyS0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/bamboo_defconfig smp bamboo "" ttyS0 rootfs.cpio.gz vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/bamboo_defconfig "smp:scsi[DC395]" bamboo "" ttyS0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/bamboo_defconfig "smp:scsi[AM53C974]" bamboo "" ttyS0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))
if [[ ${runall} -ne 0 ]]; then
    # megaraid_sas 0000:00:02.0: Command pool empty!
    # Unable to handle kernel paging request for data at address 0x00000000
    # Faulting instruction address: 0xc024a5c8
    # Oops: Kernel access of bad area, sig: 11 [#1]
    # NIP [c024a5c8] megasas_issue_init_mfi+0x20/0x138
    runkernel 44x/bamboo_defconfig "smp:scsi[MEGASAS]" bamboo "" ttyS0 rootfs.ext2.gz vmlinux
    retcode=$((${retcode} + $?))
fi
runkernel 44x/bamboo_defconfig "smp:scsi[FUSION]" bamboo "" ttyS0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/bamboo_defconfig "smp:mmc" bamboo "" ttyS0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/bamboo_defconfig "smp:nvme" bamboo "" ttyS0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/canyonlands_defconfig "" sam460ex "" ttyS0 rootfs.cpio.gz vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/canyonlands_defconfig usb sam460ex "" ttyS0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))
runkernel pmac32_defconfig zilog mac99 "" ttyPZ0 rootfs.cpio.gz vmlinux
retcode=$((${retcode} + $?))
runkernel pmac32_defconfig zilog:ata mac99 "" ttyPZ0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))

exit ${retcode}
