#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

machine=$1
option=$2
config=$3

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-aarch64}
PREFIX=aarch64-linux-
ARCH=arm64
PATH_ARM64=/opt/kernel/gcc-7.3.0-nolibc/aarch64-linux/bin

PATH=${PATH}:${PATH_ARM64}

# Xilinx boards don't work on v3.x kernels
# Root file systems only work in v4.9+ (virt) and v4.14 (Xilinx).
# Exceptions:
# - virt:defconfig:smp:virtio:rootfs works from v4.4
# - xlnx-zcu102:defconfig:smp:sata:rootfs:xilinx/zynqmp-zcu102 works from v4.4
skip_316="virt:defconfig:smp:usb:rootfs \
	virt:defconfig:smp:virtio:rootfs \
	virt:defconfig:smp:nvme:rootfs \
	virt:defconfig:smp:mmc:rootfs \
	virt:defconfig:smp:scsi[DC395]:rootfs \
	virt:defconfig:smp:scsi[AM53C974]:rootfs \
	virt:defconfig:smp:scsi[MEGASAS]:rootfs \
	virt:defconfig:nosmp:rootfs"
skip_318="virt:defconfig:smp:usb:rootfs \
	virt:defconfig:smp:virtio:rootfs \
	virt:defconfig:smp:nvme:rootfs \
	virt:defconfig:smp:mmc:rootfs \
	virt:defconfig:smp:scsi[DC395]:rootfs \
	virt:defconfig:smp:scsi[AM53C974]:rootfs \
	virt:defconfig:smp:scsi[MEGASAS]:rootfs \
	virt:defconfig:nosmp:rootfs"
skip_44="xlnx-zcu102:defconfig:smp:sd:rootfs \
	xlnx-zcu102:defconfig:nosmp:sd:rootfs \
	virt:defconfig:smp:usb:rootfs \
	virt:defconfig:smp:scsi[DC395]:rootfs \
	virt:defconfig:smp:scsi[AM53C974]:rootfs \
	virt:defconfig:smp:scsi[MEGASAS]:rootfs \
	virt:defconfig:nosmp:rootfs"
skip_49="raspi3:defconfig:smp:initrd \
	raspi3:defconfig:smp:sd:rootfs \
	xlnx-zcu102:defconfig:smp:sd:rootfs \
	xlnx-zcu102:defconfig:nosmp:sd:rootfs"

patch_defconfig()
{
    local defconfig=$1
    local fixups=${2//:/ }
    local fixup

    for fixup in ${fixups}; do
	if [ "${fixup}" = "nosmp" ]; then
	    echo "CONFIG_SMP=n" >> ${defconfig}
	fi
	if [ "${fixup}" = "smp" ]; then
	    echo "CONFIG_SMP=y" >> ${defconfig}
	fi
    done

    # Always enable SCSI controller drivers and NVME
    echo "CONFIG_BLK_DEV_NVME=y" >> ${defconfig}
    echo "CONFIG_SCSI_DC395x=y" >> ${defconfig}
    echo "CONFIG_SCSI_AM53C974=y" >> ${defconfig}
    echo "CONFIG_MEGARAID_SAS=y" >> ${defconfig}

    # Always enable MMC/SDHCI support
    echo "CONFIG_MMC=y" >> ${defconfig}
    echo "CONFIG_MMC_SDHCI=y" >> ${defconfig}
    echo "CONFIG_MMC_SDHCI_PCI=y" >> ${defconfig}
}

runkernel()
{
    local mach=$1
    local defconfig=$2
    local fixup="$3"
    local rootfs=$4
    local dtb=$5
    local pid
    local retcode
    local logfile=$(mktemp)
    local waitlist=("Restarting system" "Boot successful" "Rebooting")
    local build="${mach}:${defconfig}:${fixup}"

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	build+=":initrd"
	initcli="rdinit=/sbin/init"
	diskcmd="-initrd ${rootfs%.gz}"
    else
	build+=":rootfs"
	if [[ "${fixup}" = *usb* ]]; then
	    initcli="root=/dev/sda rw rootwait"
	    diskcmd="-usb -device qemu-xhci -device usb-storage,drive=d0"
	    diskcmd+=" -drive file=${rootfs%.gz},if=none,id=d0,format=raw"
	elif [[ "${fixup}" == *virtio* ]]; then
	    initcli="root=/dev/vda rw"
	    diskcmd="-device virtio-blk-pci,drive=d0"
	    diskcmd+=" -drive file=${rootfs%.gz},if=none,id=d0,format=raw"
	elif [[ "${fixup}" == *sata* ]]; then
	    initcli="root=/dev/sda rw"
	    diskcmd="-device ide-hd,drive=d0"
	    diskcmd+=" -drive file=${rootfs%.gz},id=d0,format=raw"
	elif [[ "${fixup}" == *mmc* ]]; then
	    initcli="root=/dev/mmcblk0 rw rootwait"
	    diskcmd="-device sdhci-pci -device sd-card,drive=d0"
	    diskcmd+=" -drive file=${rootfs%.gz},format=raw,if=none,id=d0"
	elif [[ "${fixup}" == *nvme* ]]; then
	    initcli="root=/dev/nvme0n1 rw"
	    diskcmd="-device nvme,serial=foo,drive=d0 \
		-drive file=${rootfs%.gz},if=none,format=raw,id=d0"
	elif [[ "${fixup}" == *scsi* ]]; then
	    initcli="root=/dev/sda rw"
	    case "${fixup##*:}" in
	    "scsi[DC395]")
		device="dc390"
		;;
	    "scsi[AM53C974]")
		device="am53c974"
		;;
	    "scsi[MEGASAS]")
		device="megasas-gen2"
		;;
	    esac
	    diskcmd="-device "${device}" -device scsi-hd,drive=d0 \
		     -drive file=${rootfs%.gz},if=none,format=raw,id=d0"
	else
	    local index=0
	    if [[ "${fixup}" == *sd1* ]]; then
		index=1
	    fi
	    initcli="root=/dev/mmcblk0 rw rootwait"
	    diskcmd="-drive file=${rootfs%.gz},if=sd,format=raw,index=${index}"
	fi
    fi

    local pbuild="${ARCH}:${build}${dtb:+:${dtb%.dtb}}"

    if [ -n "${machine}" -a "${machine}" != "${mach}" ]; then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    if [ -n "${option}" -a "${option}" != "${fixup}" ]; then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    if [ -n "${config}" -a "${config}" != "${defconfig}" ]
    then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    if [[ -n "${dtb}" && ! -e "arch/arm64/boot/dts/${dtb/.dtb/.dts}" ]]; then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    echo -n "Building ${pbuild} ... "

    if ! checkskip "${build}"; then
	return 0
    fi

    if [[ "${cached_config}" != "${defconfig}:${fixup%:*}" ]]; then
	if ! dosetup -f "${fixup}" "${rootfs}" "${defconfig}"; then
	    return 1
	fi
	cached_config="${defconfig}:${fixup%:*}"
    else
	setup_rootfs "${rootfs}"
    fi

    if [[ "${rootfs}" == *.gz ]]; then
	gunzip -f "${rootfs}"
	rootfs="${rootfs%.gz}"
    fi

    echo -n "running ..."

    case ${mach} in
    "virt")
	[[ ${dodebug} -ne 0 ]] && set -x
	${QEMU} -M ${mach} -cpu cortex-a57 \
		-nographic -smp 1 -m 512 \
		-monitor none \
		-kernel arch/arm64/boot/Image -no-reboot \
		${diskcmd} \
		-append "console=ttyAMA0 ${initcli}" \
		> ${logfile} 2>&1 &
	pid=$!
	[[ ${dodebug} -ne 0 ]] && set +x
	waitflag="manual"
	;;
    "raspi3")
	[[ ${dodebug} -ne 0 ]] && set -x
	${QEMU} -M ${mach} -m 1024 \
	    -kernel arch/arm64/boot/Image -no-reboot \
	    --append "earlycon=uart8250,mmio32,0x3f215040 ${initcli} console=ttyS1,115200" \
	    ${diskcmd} \
	    ${dtb:+-dtb arch/arm64/boot/dts/${dtb}} \
	    -nographic -monitor null -serial null -serial stdio \
	    > ${logfile} 2>&1 &
	pid=$!
	[[ ${dodebug} -ne 0 ]] && set +x
	waitflag="manual"
	;;
    "xlnx-zcu102")
	[[ ${dodebug} -ne 0 ]] && set -x
	${QEMU} -M ${mach} -kernel arch/arm64/boot/Image -m 2048 \
		-nographic -serial stdio -monitor none -no-reboot \
		${dtb:+-dtb arch/arm64/boot/dts/${dtb}} \
		${diskcmd} \
		--append "${initcli} console=ttyPS0 earlycon=cdns,mmio,0xFF000000,115200n8" \
		> ${logfile} 2>&1 &
	pid=$!
	[[ ${dodebug} -ne 0 ]] && set +x
	waitflag="automatic"
	;;
    esac

    dowait ${pid} ${logfile} ${waitflag} waitlist[@]
    retcode=$?

    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel virt defconfig smp rootfs.cpio.gz
retcode=$?
runkernel virt defconfig smp:usb rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig smp:virtio rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig smp:nvme rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig smp:mmc rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig "smp:scsi[DC395]" rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig "smp:scsi[AM53C974]" rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel virt defconfig "smp:scsi[MEGASAS]" rootfs.ext2.gz
retcode=$((retcode + $?))

runkernel xlnx-zcu102 defconfig smp rootfs.cpio.gz xilinx/zynqmp-ep108.dtb
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig smp:sd rootfs.ext2.gz xilinx/zynqmp-ep108.dtb
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig smp:sata rootfs.ext2.gz xilinx/zynqmp-ep108.dtb
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig smp rootfs.cpio.gz xilinx/zynqmp-zcu102-rev1.0.dtb
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig smp:sd1 rootfs.ext2.gz xilinx/zynqmp-zcu102-rev1.0.dtb
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig smp:sata rootfs.ext2.gz xilinx/zynqmp-zcu102-rev1.0.dtb
retcode=$((retcode + $?))

runkernel raspi3 defconfig smp rootfs.cpio.gz broadcom/bcm2837-rpi-3-b.dtb
retcode=$((retcode + $?))
runkernel raspi3 defconfig smp:sd rootfs.ext2.gz broadcom/bcm2837-rpi-3-b.dtb
retcode=$((retcode + $?))

runkernel virt defconfig nosmp rootfs.cpio.gz
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig nosmp rootfs.cpio.gz xilinx/zynqmp-ep108.dtb
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig nosmp:sd rootfs.ext2.gz xilinx/zynqmp-ep108.dtb
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig nosmp rootfs.cpio.gz xilinx/zynqmp-zcu102-rev1.0.dtb
retcode=$((retcode + $?))
runkernel xlnx-zcu102 defconfig nosmp:sd1 rootfs.ext2.gz xilinx/zynqmp-zcu102-rev1.0.dtb
retcode=$((retcode + $?))

exit ${retcode}
