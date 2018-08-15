#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

machine=$1
cputype=$2

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-x86_64}
ARCH=x86_64

# Older releases don't like gcc 6+
rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
case "${rel}" in
"v3.16"|"v3.18")
	PATH_X86=/opt/poky/1.3/sysroots/x86_64-pokysdk-linux/usr/bin/x86_64-poky-linux
	PREFIX="x86_64-poky-linux-"
	;;
*)
	PATH_X86=/opt/kernel/x86_64/gcc-6.3.0/usr/bin/
	PREFIX="x86_64-linux-"
	;;
esac

PATH=${PATH_X86}:${PATH}

skip_316="defconfig:smp:scsi[AM53C974] \
	defconfig:smp:scsi[DC395] \
	defconfig:nosmp:scsi[AM53C974] \
	defconfig:nosmp:scsi[DC395]"

skip_318="defconfig:smp:scsi[AM53C974] \
	defconfig:smp:scsi[DC395] \
	defconfig:nosmp:scsi[AM53C974] \
	defconfig:nosmp:scsi[DC395]"

patch_defconfig()
{
    local defconfig=$1
    local fixups=${2//:/ }
    local fixup

    for fixup in ${fixups}; do
      if [[ "${fixup}" = "nosmp" ]]; then
	echo "CONFIG_SMP=n" >> ${defconfig}
      fi
    done

    # Always enable SCSI controller drivers and NVME
    echo "CONFIG_BLK_DEV_NVME=y" >> ${defconfig}
    echo "CONFIG_SCSI_LOWLEVEL=y" >> ${defconfig}
    echo "CONFIG_SCSI_DC395x=y" >> ${defconfig}
    echo "CONFIG_SCSI_AM53C974=y" >> ${defconfig}
    echo "CONFIG_SCSI_SYM53C8XX_2=y" >> ${defconfig}
    echo "CONFIG_MEGARAID_SAS=y" >> ${defconfig}
    echo "CONFIG_FUSION=y" >> ${defconfig}
    echo "CONFIG_FUSION_SAS=y" >> ${defconfig}

    # Always enable MMC/SDHCI support
    echo "CONFIG_MMC=y" >> ${defconfig}
    echo "CONFIG_MMC_SDHCI=y" >> ${defconfig}
    echo "CONFIG_MMC_SDHCI_PCI=y" >> ${defconfig}

    # Enable USB-UAS (USB Attached SCSI)
    echo "CONFIG_USB_UAS=y" >> ${defconfig}

    # Virtualization
    echo "CONFIG_VIRTIO=y" >> ${defconfig}
    echo "CONFIG_VIRTIO_PCI=y" >> ${defconfig}
    echo "CONFIG_VIRTIO_PCI_LEGACY=y" >> ${defconfig}
    echo "CONFIG_VIRTIO_BALLOON=y" >> ${defconfig}
    echo "CONFIG_VIRTIO_MMIO=y" >> ${defconfig}
    echo "CONFIG_BLK_MQ_VIRTIO=y" >> ${defconfig}
    echo "CONFIG_VIRTIO_BLK=y" >> ${defconfig}
    echo "CONFIG_VIRTIO_BLK_SCSI=y" >> ${defconfig}
    echo "CONFIG_SCSI_VIRTIO=y" >> ${defconfig}
}

runkernel()
{
    local defconfig=$1
    local fixup=$2
    local cpu=$3
    local mach=$4
    local rootfs=$5
    local drive
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("machine restart" "Restarting" "Boot successful" "Rebooting")
    local pbuild="${ARCH}:${mach}:${cpu}:${defconfig}:${fixup}"
    local build="${defconfig}:${fixup}"
    local config="${defconfig}:${fixup%:*}"

    if [[ "${rootfs}" == *cpio ]]; then
	pbuild+=":initrd"
    else
	pbuild+=":rootfs"
    fi

    if [ -n "${machine}" -a "${machine}" != "${mach}" ]
    then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    if [ -n "${cputype}" -a "${cputype}" != "${cpu}" ]
    then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    echo -n "Building ${pbuild} ... "

    if ! checkskip "${build}" ; then
	return 0
    fi

    if ! dosetup -c  "${config}" -f "${fixup}" "${rootfs}" "${defconfig}"; then
	return 1
    fi

    echo -n "running ..."

    if ! common_diskcmd "${fixup##*:}" "${rootfs}"; then
	return 1
    fi

    kvm=""
    mem="-m 256"
    if [ "${cpu}" = "kvm64" ]
    then
	kvm="-enable-kvm -smp 4"
	mem="-m 1024"
    fi

    [[ ${dodebug} -ne 0 ]] && set -x

    ${QEMU} -kernel arch/x86/boot/bzImage \
	-M ${mach} -cpu ${cpu} ${kvm} -no-reboot ${mem} \
	${diskcmd} \
	--append "earlycon=uart8250,io,0x3f8,9600n8 ${initcli} console=ttyS0 console=tty doreboot" \
	-nographic > ${logfile} 2>&1 &
    pid=$!

    [[ ${dodebug} -ne 0 ]] && set +x

    dowait ${pid} ${logfile} manual waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

retcode=0

# runkernel defconfig kvm64 q35
# retcode=$((${retcode} + $?))
runkernel defconfig smp:ata Broadwell-noTSX q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp:nvme IvyBridge q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp:usb SandyBridge q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp:usb-uas Haswell q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp:mmc Skylake-Client q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp:scsi[DC395] Conroe q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp:scsi[AM53C974] Nehalem q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp:scsi[53C810] Westmere-IBRS q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp:scsi[53C895A] Skylake-Server q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp:scsi[MEGASAS] EPYC pc rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp:scsi[MEGASAS2] EPYC-IBPB q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp:scsi[FUSION] Opteron_G5 q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp phenom pc rootfs.cpio
retcode=$((${retcode} + $?))
runkernel defconfig smp Opteron_G1 q35 rootfs.cpio
retcode=$((${retcode} + $?))
runkernel defconfig smp:scsi[virtio-pci] Opteron_G2 pc rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp:virtio-pci core2duo q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp:virtio Broadwell q35 rootfs.ext2
retcode=$((${retcode} + $?))

runkernel defconfig nosmp:usb Opteron_G3 pc rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig nosmp:ata Opteron_G4 q35 rootfs.ext2
retcode=$((${retcode} + $?))

exit ${retcode}
