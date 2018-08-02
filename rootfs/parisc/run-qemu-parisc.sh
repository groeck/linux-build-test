#!/bin/bash

_fixup=$1

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-hppa}

PREFIX=hppa-linux-
ARCH=parisc

PATH_PARISC=/opt/kernel/hppa/gcc-7.3.0/bin
PATH=${PATH}:${PATH_PARISC}

cached_config=""

patch_defconfig()
{
    local defconfig=$1

    # NVME
    echo "CONFIG_BLK_DEV_NVME=y" >> ${defconfig}

    # SCSI controller drivers
    echo "CONFIG_SCSI_DC395x=y" >> ${defconfig}
    echo "CONFIG_SCSI_AM53C974=y" >> ${defconfig}
    echo "CONFIG_MEGARAID_SAS=y" >> ${defconfig}
    echo "CONFIG_SCSI_SYM53C8XX_2=y" >> ${defconfig}
    echo "CONFIG_FUSION=y" >> ${defconfig}
    echo "CONFIG_FUSION_SAS=y" >> ${defconfig}

    # MMC/SDHCI support
    echo "CONFIG_MMC=y" >> ${defconfig}
    echo "CONFIG_MMC_SDHCI=y" >> ${defconfig}
    echo "CONFIG_MMC_SDHCI_PCI=y" >> ${defconfig}

    # USB
    echo "CONFIG_USB_XHCI_HCD=y" >> ${defconfig}
    echo "CONFIG_USB_STORAGE=y" >> ${defconfig}

    # USB-UAS (USB Attached SCSI)
    echo "CONFIG_USB_UAS=y" >> ${defconfig}

    # ATA
    echo "CONFIG_ATA=y" >> ${defconfig}
    echo "CONFIG_PATA_CMD64X=y" >> ${defconfig}
}

runkernel()
{
    local defconfig=$1
    local fixup=$2
    local rootfs=$3
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("reboot: Restarting system" "Boot successful" "Requesting system reboot")
    local build="${ARCH}:${defconfig}"
    local initcli
    local diskcmd

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	build+=":initrd"
	initcli="rdinit=/sbin/init"
	diskcmd="-initrd ${rootfs%.gz}"
    else
	build+="${fixup:+:${fixup}}:rootfs"
	if [[ "${fixup}" == "sata" ]]; then
	    initcli="root=/dev/sda rw"
	    diskcmd="-device cmd646-ide,id=ata"
	    diskcmd+=" -device ide-hd,bus=ata.0,drive=d0"
	    diskcmd+=" -drive file=${rootfs%.gz},if=none,id=d0,format=raw"
	elif [[ "${fixup}" == "mmc" ]]; then
	    initcli="root=/dev/mmcblk0 rw rootwait"
	    diskcmd="-device sdhci-pci -device sd-card,drive=d0"
	    diskcmd+=" -drive file=${rootfs%.gz},format=raw,if=none,id=d0"
	elif [[ "${fixup}" == "usb" ]]; then
	    initcli="root=/dev/sda rw rootwait"
	    diskcmd="-usb -device qemu-xhci -device usb-storage,drive=d0"
	    diskcmd+=" -drive file=${rootfs%.gz},if=none,id=d0,format=raw"
	elif [[ "${fixup}" == "usb-uas" ]]; then
	    initcli="root=/dev/sda rw rootwait"
	    diskcmd="-usb -device qemu-xhci -device usb-uas,id=uas"
	    diskcmd+=" -device scsi-hd,bus=uas.0,scsi-id=0,lun=0,drive=d0"
	    diskcmd+=" -drive file=${rootfs%.gz},if=none,format=raw,id=d0"
	elif [[ "${fixup}" == "nvme" ]]; then
	    initcli="root=/dev/nvme0n1 rw"
	    diskcmd="-device nvme,serial=foo,drive=d0"
	    diskcmd+=" -drive file=${rootfs%.gz},if=none,format=raw,id=d0"
	else # scsi
	    initcli="root=/dev/sda"
	    local wwn
	    local device
	    local if
	    local id
	    case "${fixup}" in
	    "scsi")
		# default (53C810)
		if="scsi"
		;;
	    "scsi[53C895A]")
		device="lsi53c895a"
		;;
	    "scsi[DC395]")
		device="dc390"
		;;
	    "scsi[AM53C974]")
		device="am53c974"
		;;
	    "scsi[MEGASAS]")
		device="megasas"
		;;
	    "scsi[MEGASAS2]")
		device="megasas-gen2"
		;;
	    "scsi[FUSION]")
		device="mptsas1068"
		# wwn (World Wide Name) is mandatory for this device
		wwn="0x5000c50015ea71ac"
		;;
	    esac
	    diskcmd=""
	    if [[ -n "${device}" ]]; then
		diskcmd="-device ${device}"
		diskcmd+=" -device scsi-hd,drive=d0${wwn:+,wwn=${wwn}}"
		id="d0"
	    fi
	    diskcmd+=" -drive file=${rootfs%.gz},format=raw,if=${if:-none}${id:+,id=${id}}"
	fi
    fi

    if [ -n "${_fixup}" -a "${_fixup}" != "${fixup}" ]
    then
	echo "Skipping ${build} ... "
	return 0
    fi

    echo -n "Building ${build} ... "

    if [ "${cached_config}" != "${defconfig}" ]; then
	dosetup -f fixup "${rootfs}" "${defconfig}"
	if [ $? -ne 0 ]; then
	    return 1
	fi
	cached_config="${defconfig}"
    else
	setup_rootfs "${rootfs}"
    fi

    if [[ "${rootfs}" == *.gz ]]; then
	gunzip -f "${rootfs}"
	rootfs="${rootfs%.gz}"
    fi

    echo -n "running ..."

    [[ ${dodebug} -ne 0 ]] && set -x

    ${QEMU} -kernel vmlinux -no-reboot \
	${diskcmd} \
	-append "${initcli} console=ttyS0,115200 ${extracli}" \
	-nographic -monitor null > ${logfile} 2>&1 &
    pid=$!

    [[ ${dodebug} -ne 0 ]] && set +x

    dowait ${pid} ${logfile} automatic waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

retcode=0
runkernel defconfig initrd rootfs.cpio.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig mmc rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig nvme rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig sata rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig scsi rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig "scsi[53C895A]" rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig "scsi[DC395]" rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig "scsi[AM53C974]" rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}

if [[ ${runall} -ne 0 ]]; then
    # panic: arch/parisc/kernel/pci-dma.c: pcxl_alloc_range() Too many pages to map.
    runkernel defconfig "scsi[MEGASAS]" rootfs.ext2.gz
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel defconfig "scsi[MEGASAS2]" rootfs.ext2.gz
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel defconfig "scsi[FUSION]" rootfs.ext2.gz
    retcode=$((retcode + $?))
    checkstate ${retcode}
fi

runkernel defconfig usb rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig usb-uas rootfs.ext2.gz
retcode=$((retcode + $?))

exit ${retcode}
