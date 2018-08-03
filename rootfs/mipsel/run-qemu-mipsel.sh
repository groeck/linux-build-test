#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

_cpu=$1
config=$2
variant=$3

rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
PATH_MIPS=/opt/kernel/gcc-7.3.0-nolibc/mips-linux/bin
QEMU=${QEMU:-${QEMU_BIN}/qemu-system-mipsel}
PREFIX=mips-linux-

# machine specific information
ARCH=mips
KERNEL_IMAGE=vmlinux
QEMU_MACH=malta

PATH=${PATH_MIPS}:${PATH}

patch_defconfig()
{
    local defconfig=$1
    local fixups=${2//:/ }
    local fixup

    # Enable DEVTMPFS and BLK_DEV_INITRD for initrd support
    # DEVTMPFS needs to be explicitly enabled for v3.14 and older kernels.
    echo "CONFIG_DEVTMPFS=y" >> ${defconfig}
    echo "CONFIG_DEVTMPFS_MOUNT=y" >> ${defconfig}
    echo "CONFIG_BLK_DEV_INITRD=y" >> ${defconfig}

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
    local cpu=$1
    local defconfig=$2
    local fixup="$3"
    local rootfs=$4
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Boot successful" "Rebooting")
    local build="mipsel:${cpu}:${defconfig}:${fixup%:*}"
    local buildconfig="${defconfig}:${fixup%:*}"

    if [[ "${rootfs}" == *cpio* ]]; then
	build+=":initrd"
    else
	build+=":${fixup##*:}"
	build+=":rootfs"
    fi

    if [ -n "${_cpu}" -a "${_cpu}" != "${cpu}" ]
    then
	echo "Skipping ${build} ... "
	return 0
    fi

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

    if [ "${cached_config}" != "${buildconfig}" ]; then
	if ! dosetup -f "${fixup}" "${rootfs}" "${defconfig}"; then
	    return 1
	fi
	cached_config="${buildconfig}"
    else
	setup_rootfs "${rootfs}"
    fi

    rootfs="${rootfs%.gz}"

    echo -n "running ..."

    if ! common_diskcmd "${fixup##*:}" "${rootfs}"; then
	return 1
    fi

    [[ ${dodebug} -ne 0 ]] && set -x

    ${QEMU} -kernel ${KERNEL_IMAGE} -M ${QEMU_MACH} -cpu ${cpu} \
	-vga cirrus -no-reboot -m 128 \
	${diskcmd} \
	--append "${initcli} mem=128M console=ttyS0 ${extracli}" \
	-nographic > ${logfile} 2>&1 &
    pid=$!

    [[ ${dodebug} -ne 0 ]] && set +x

    dowait ${pid} ${logfile} automatic waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel 24Kf malta_defconfig smp:ata rootfs.cpio.gz
retcode=$?
runkernel 24Kf malta_defconfig smp:ata rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))

if [[ ${runall} -ne 0 ]]; then
    # Kernel bug detected[#1]:
    # Workqueue: nvme-reset-wq nvme_reset_work
    runkernel 24Kf malta_defconfig smp:nvme rootfs-mipselr1.ext2.gz
    retcode=$((retcode + $?))
fi

runkernel 24Kf malta_defconfig smp:usb-xhci rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))
runkernel 24Kc malta_defconfig smp:usb-uas-xhci rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))
runkernel 24KEc malta_defconfig smp:mmc rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))
runkernel 34Kf malta_defconfig smp:scsi[53C810] rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))
runkernel 74Kf malta_defconfig smp:scsi[53C895A] rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))
runkernel M14Kc malta_defconfig smp:scsi[DC395] rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))
runkernel 24Kf malta_defconfig smp:scsi[AM53C974] rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))
runkernel 24Kf malta_defconfig smp:scsi[MEGASAS] rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))
runkernel 24Kf malta_defconfig smp:scsi[MEGASAS2] rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))
runkernel 24Kf malta_defconfig smp:scsi[FUSION] rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))

runkernel mips32r6-generic malta_qemu_32r6_defconfig smp:ata rootfs-mipselr6.ext2.gz
retcode=$((retcode + $?))

runkernel 24Kf malta_defconfig nosmp:ata rootfs.cpio.gz
retcode=$((retcode + $?))
runkernel 24Kf malta_defconfig nosmp:ata rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))

exit ${retcode}
