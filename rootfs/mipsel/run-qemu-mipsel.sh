#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

_cpu=$1
config=$2
variant=$3

# Compile failure with gcc 10.3.0 in v5.10.y and malta_qemu_32r6_defconfig
PATH_MIPS=/opt/kernel/gcc-9.3.0-nolibc/mips-linux/bin
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

    for fixup in ${fixups}; do
	if [[ "${fixup}" == "smp" ]]; then
	    enable_config "${defconfig}" CONFIG_MIPS_MT_SMP
	elif [[ "${fixup}" == "nosmp" ]]; then
	    disable_config "${defconfig}" CONFIG_MIPS_MT_SMP
	fi
    done
}

runkernel()
{
    local cpu=$1
    local defconfig=$2
    local fixup="$3"
    local rootfs=$4
    local waitlist=("Boot successful" "Rebooting")
    local build="mipsel:${cpu}:${defconfig}:${fixup}"
    local buildconfig="${defconfig}:${fixup//smp*/smp}"

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":rootfs"
    fi

    if ! match_params "${_cpu}@${cpu}" "${config}@${defconfig}" "${variant}@${fixup}"; then
	echo "Skipping ${build} ... "
	return 0
    fi

    echo -n "Building ${build} ... "

    if ! checkskip "${build}" ; then
	return 0
    fi

    if ! dosetup -c "${buildconfig}" -F "${fixup}" "${rootfs}" "${defconfig}"; then
	if [[ __dosetup_rc -eq 2 ]]; then
	    return 0
	fi
	return 1
    fi

    execute automatic waitlist[@] \
      ${QEMU} -kernel ${KERNEL_IMAGE} -M ${QEMU_MACH} -cpu ${cpu} \
	-vga cirrus -no-reboot \
	${extra_params} \
	--append "${initcli} console=ttyS0 ${extracli}" \
	-nographic

    return $?
}

echo "Build reference: $(git describe)"
echo

# Most images fail to instantiate CD ROM because there is an insufficient
# amount of DMA memory.

runkernel 24Kf malta_defconfig nocd:smp:net,e1000 rootfs.cpio.gz
retcode=$?
runkernel 24Kf malta_defconfig nocd:smp:net,i82550:ide rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))

if [[ ${runall} -ne 0 ]]; then
    # nvme nvme0: I/O 97 QID 1 timeout, completion polled
    runkernel 24Kf malta_defconfig nocd:smp:nvme rootfs-mipselr1.ext2.gz
    retcode=$((retcode + $?))
fi

runkernel 24Kf malta_defconfig nocd:smp:net,i82801:usb-xhci rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))
runkernel 24Kf malta_defconfig nocd:smp:net,i82550:usb-ehci rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))
runkernel 24Kc malta_defconfig nocd:smp:net,ne2k_pci:usb-uas-xhci rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))
runkernel 24KEc malta_defconfig nocd:smp:net,pcnet:sdhci:mmc rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))
runkernel 34Kf malta_defconfig nocd:smp:net,rtl8139:scsi[53C810] rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))
runkernel 74Kf malta_defconfig nocd:smp:net,tulip:scsi[53C895A] rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))
runkernel M14Kc malta_defconfig nocd:smp:net,virtio-net:scsi[DC395] rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))
runkernel 24Kf malta_defconfig nocd:smp:net,i82558a:scsi[AM53C974] rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))
runkernel 24Kf malta_defconfig nocd:smp:net,i82562:scsi[MEGASAS] rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))
runkernel 24Kf malta_defconfig nocd:smp:scsi[MEGASAS2] rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))
runkernel 24Kf malta_defconfig nocd:smp:scsi[FUSION] rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))

runkernel mips32r6-generic malta_qemu_32r6_defconfig nocd:smp:net,pcnet:ide rootfs-mipselr6.ext2.gz
retcode=$((retcode + $?))

runkernel 24Kf malta_defconfig nosmp:net,pcnet rootfs.cpio.gz
retcode=$((retcode + $?))
runkernel 24Kf malta_defconfig nosmp:ide:net,rtl8139 rootfs-mipselr1.ext2.gz
retcode=$((retcode + $?))

exit ${retcode}
