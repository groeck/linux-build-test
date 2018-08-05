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

runkernel()
{
    local defconfig=$1
    local fixup=$2
    local rootfs=$3
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Boot successful" "Rebooting")
    local build="${ARCH}:${defconfig}"
    local cache="${defconfig}${fixup%:*}"

    if [[ "${rootfs}" == *.cpio* ]]; then
	build+=":${fixup%:*}"
	build+=":initrd"
    else
	build+=":${fixup}"
	build+=":rootfs"
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

    if ! dosetup -f "${fixup}" -c "${cache}" "${rootfs}" "${defconfig}"; then
	return 1
    fi

    echo -n "running ..."

    if ! common_diskcmd "${fixup##*:}" "${rootfs}"; then
	return 1
    fi

    [[ ${dodebug} -ne 0 ]] && set -x

    ${QEMU} -kernel ${KERNEL_IMAGE} -M ${QEMU_MACH} \
	${diskcmd} \
	-vga cirrus -no-reboot -m 128 \
	--append "${initcli} mem=128M console=ttyS0 console=tty ${extracli}" \
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

runkernel malta_defconfig smp:ata rootfs.cpio.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:ata rootfs.ext2.gz
retcode=$((retcode + $?))

if [[ ${runall} -eq 1 ]]; then
    # Kernel bug detected[#1]: Workqueue: nvme-reset-wq nvme_reset_work
    # (in nvme_pci_reg_read64)
    runkernel malta_defconfig smp:nvme rootfs.ext2.gz
    retcode=$((retcode + $?))
fi

runkernel malta_defconfig smp:usb-xhci rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:usb-uas-xhci rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:mmc rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:scsi[53C810] rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:scsi[53C895A] rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:scsi[DC395] rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:scsi[AM53C974] rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:scsi[MEGASAS] rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:scsi[MEGASAS2] rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:scsi[FUSION] rootfs.ext2.gz
retcode=$((retcode + $?))

runkernel malta_defconfig nosmp:ata rootfs.cpio.gz
retcode=$?
runkernel malta_defconfig nosmp:ata rootfs.ext2.gz
retcode=$?

exit ${retcode}
