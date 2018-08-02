#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

config=$1
variant=$2

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-mips}

rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
PATH_MIPS=/opt/kernel/mips/gcc-5.4.0/usr/bin
PREFIX=mips-linux-

# machine specific information
rootfs=busybox-mips.ext3
ARCH=mips
KERNEL_IMAGE=vmlinux
QEMU_MACH=malta

PATH=${PATH_MIPS}:${PATH}

patch_defconfig()
{
    local defconfig=$1
    local fixups=${2//:/ }
    local fixup

    echo "CONFIG_DEVTMPFS=y" >> ${defconfig}
    echo "CONFIG_BLK_DEV_INITRD=y" >> ${defconfig}

    # Build a big endian image
    echo "CONFIG_CPU_LITTLE_ENDIAN=n" >> ${defconfig}
    echo "CONFIG_CPU_BIG_ENDIAN=y" >> ${defconfig}

    # MMC/SDHCI
    echo "CONFIG_MMC=y" >> ${defconfig}
    echo "CONFIG_MMC_SDHCI=y" >> ${defconfig}
    echo "CONFIG_MMC_SDHCI_PCI=y" >> ${defconfig}

    # SCSI
    echo "CONFIG_SCSI=y" >> ${defconfig}
    echo "CONFIG_BLK_DEV_SD=y" >> ${defconfig}
    echo "CONFIG_SCSI_DC395x=y" >> ${defconfig}
    echo "CONFIG_SCSI_AM53C974=y" >> ${defconfig}
    echo "CONFIG_MEGARAID_SAS=y" >> ${defconfig}
    echo "CONFIG_FUSION=y" >> ${defconfig}
    echo "CONFIG_FUSION_SAS=y" >> ${defconfig}
    echo "CONFIG_SCSI_SYM53C8XX_2=y" >> ${defconfig}

    # NVME
    echo "CONFIG_BLK_DEV_NVME=y" >> ${defconfig}

    # USB
    echo "CONFIG_USB=y" >> ${defconfig}
    echo "CONFIG_USB_XHCI_HCD=y" >> ${defconfig}
    echo "CONFIG_USB_STORAGE=y" >> ${defconfig}
    echo "CONFIG_USB_UAS=y" >> ${defconfig}

    for fixup in ${fixups}; do
	if [[ "${fixup}" == "smp" ]]; then
	    echo "CONFIG_MIPS_MT_SMP=y" >> ${defconfig}
	elif [[ "${fixup}" == "nosmp" ]]; then
	    echo "CONFIG_MIPS_MT_SMP=n" >> ${defconfig}
	fi
    done
}

cached_config=""

runkernel()
{
    local defconfig=$1
    local fixup=$2
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Boot successful" "Rebooting")
    local build="${ARCH}:${defconfig}:${fixup}"
    local initcli
    local diskcmd

    if [ -n "${config}" -a "${config}" != "${defconfig}" ]
    then
	echo "Skipping ${build} ... "
	return 0
    fi

    if [ -n "${variant}" -a "${variant}" != "${fixup}" ]
    then
	echo "Skipping ${build} ... "
	return 0
    fi

    echo -n "Building ${build} ... "

    if [ "${cached_config}" != "${defconfig}${fixup%:*}" ]; then
	if ! dosetup -f "${fixup}" "${rootfs}" "${defconfig}"; then
	    return 1
	fi
	cached_config="${defconfig}${fixup%:*}"
    else
	setup_rootfs "${rootfs}"
    fi

    echo -n "running ..."

    if [[ "${fixup}" == *sata ]]; then
	diskcmd="-drive file=${rootfs},format=raw,if=ide"
	local hddev="hda"
	# The actual configuration determines if the root file system
	# is /dev/sda (CONFIG_ATA) or /dev/hda (CONFIG_IDE).
	# CONFIG_ATA is enabled in kernel version 4.1 and later.
	if grep -q "CONFIG_ATA=y" .config; then
	    hddev="sda"
	fi
	initcli="root=/dev/${hddev} rw"
    elif [[ "${fixup}" == *mmc ]]; then
	initcli="root=/dev/mmcblk0 rw rootwait"
	diskcmd="-device sdhci-pci -device sd-card,drive=d0"
	diskcmd+=" -drive file=${rootfs},format=raw,if=none,id=d0"
    elif [[ "${fixup}" == *nvme ]]; then
	initcli="root=/dev/nvme0n1 rw"
	diskcmd="-device nvme,serial=foo,drive=d0"
	diskcmd+=" -drive file=${rootfs},if=none,format=raw,id=d0"
    elif [[ "${fixup}" = *usb ]]; then
	initcli="root=/dev/sda rw rootwait"
	diskcmd="-usb -device qemu-xhci -device usb-storage,drive=d0"
	diskcmd+=" -drive file=${rootfs},if=none,id=d0,format=raw"
    elif [[ "${fixup}" == *usb-uas ]]; then
	initcli="root=/dev/sda rw rootwait"
	diskcmd="-usb -device qemu-xhci -device usb-uas,id=uas"
	diskcmd+=" -device scsi-hd,bus=uas.0,scsi-id=0,lun=0,drive=d0"
	diskcmd+=" -drive file=${rootfs},if=none,format=raw,id=d0"
    fi

    [[ ${dodebug} -ne 0 ]] && set -x

    ${QEMU} -kernel ${KERNEL_IMAGE} -M ${QEMU_MACH} \
	${diskcmd} \
	-vga cirrus -no-reboot -m 128 \
	--append "${initcli} mem=128M console=ttyS0 console=tty ${extracli} doreboot" \
	-nographic -monitor none > ${logfile} 2>&1 &
    pid=$!

    [[ ${dodebug} -ne 0 ]] && set +x

    dowait ${pid} ${logfile} automatic waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel malta_defconfig nosmp:sata
retcode=$?
runkernel malta_defconfig smp:sata
retcode=$((retcode + $?))
if [[ ${runall} -eq 1 ]]; then
    # Kernel bug detected[#1]: Workqueue: nvme-reset-wq nvme_reset_work
    # (in nvme_pci_reg_read64)
    runkernel malta_defconfig smp:nvme
    retcode=$((retcode + $?))
fi
runkernel malta_defconfig smp:usb
retcode=$((retcode + $?))
runkernel malta_defconfig smp:usb-uas
retcode=$((retcode + $?))
runkernel malta_defconfig smp:mmc
retcode=$((retcode + $?))

exit ${retcode}
