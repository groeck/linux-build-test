#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

config=$1
variant=$2

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-mips}

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

    # Build a big endian image
    echo "CONFIG_CPU_LITTLE_ENDIAN=n" >> ${defconfig}
    echo "CONFIG_CPU_BIG_ENDIAN=y" >> ${defconfig}

    for fixup in ${fixups}; do
	if [[ "${fixup}" == "smp" ]]; then
	    echo "CONFIG_MIPS_MT_SMP=y" >> ${defconfig}
	elif [[ "${fixup}" == "nosmp" ]]; then
	    echo "CONFIG_MIPS_MT_SMP=n" >> ${defconfig}
	fi
    done

    # Avoid spurious DMA memory allocation errors
    echo "CONFIG_DEBUG_WW_MUTEX_SLOWPATH=n" >> ${defconfig}
    echo "CONFIG_DEBUG_LOCK_ALLOC=n" >> ${defconfig}
    echo "CONFIG_PROVE_LOCKING=n" >> ${defconfig}
}

runkernel()
{
    local defconfig=$1
    local fixup=$2
    local rootfs=$3
    local waitlist=("Boot successful" "Rebooting")
    local build="${ARCH}:${defconfig}:${fixup}"
    local cache="${defconfig}${fixup//smp*/smp}"

    if [[ "${rootfs}" == *.cpio* ]]; then
	build+=":initrd"
    else
	build+=":rootfs"
    fi

    if ! match_params "${config}@${defconfig}" "${variant}@${fixup}"; then
	echo "Skipping ${build} ... "
	return 0
    fi

    echo -n "Building ${build} ... "

    if ! checkskip "${build}" ; then
	return 0
    fi

    if ! dosetup -F "${fixup}" -c "${cache}" "${rootfs}" "${defconfig}"; then
	return 1
    fi

    execute automatic waitlist[@] \
      ${QEMU} -kernel ${KERNEL_IMAGE} -M ${QEMU_MACH} \
	${extra_params} \
	-vga cirrus -no-reboot \
	--append "${initcli} console=ttyS0 console=tty ${extracli}" \
	-nographic -monitor none

    return $?
}

echo "Build reference: $(git describe)"
echo

runkernel malta_defconfig smp:net,e1000 rootfs.cpio.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:net,pcnet:ide rootfs.ext2.gz
retcode=$((retcode + $?))

if [[ ${runall} -eq 1 ]]; then
    # Kernel bug detected[#1]: Workqueue: nvme-reset-wq nvme_reset_work
    # (in nvme_pci_reg_read64)
    runkernel malta_defconfig smp:nvme rootfs.ext2.gz
    retcode=$((retcode + $?))
fi

runkernel malta_defconfig smp:net,e1000:usb-xhci rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:net,e1000-82545em:usb-uas-xhci rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:net,i82801:usb-ehci rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:net,ne2k_pci:sdhci:mmc rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:net,pcnet:scsi[53C810] rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:net,rtl8139:scsi[53C895A] rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:net,tulip:scsi[DC395] rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:net,virtio-net:scsi[AM53C974] rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:net,i82550:scsi[MEGASAS] rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:net,i82558a:scsi[MEGASAS2] rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:net,i82562:scsi[FUSION] rootfs.ext2.gz
retcode=$((retcode + $?))

runkernel malta_defconfig nosmp rootfs.cpio.gz
retcode=$((retcode + $?))
runkernel malta_defconfig nosmp:ide rootfs.ext2.gz
retcode=$((retcode + $?))

exit ${retcode}
