#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

config=$1
variant=$2

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-mips}

PATH_MIPS=/opt/kernel/${DEFAULT_CC}/mips-linux/bin
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
    disable_config "${defconfig}" CONFIG_CPU_LITTLE_ENDIAN
    enable_config "${defconfig}" CONFIG_CPU_BIG_ENDIAN
    enable_config "${defconfig}" CONFIG_MTD_PHYSMAP CONFIG_MTD_PHYSMAP_OF

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

echo "Build reference: $(git describe --match 'v*')"
echo

# Disable CD support to avoid DMA memory allocation errors

runkernel malta_defconfig nocd:smp:net=e1000 rootfs.cpio.gz
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:net=pcnet:flash,4,1,1 rootfs.squashfs
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:net=pcnet:ide rootfs.ext2.gz
retcode=$((retcode + $?))

runkernel malta_defconfig nocd:smp:net=i82558b:nvme rootfs.ext2.gz
retcode=$((retcode + $?))

runkernel malta_defconfig nocd:smp:net=e1000:usb-xhci rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:net=e1000-82545em:usb-uas-xhci rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:net=i82801:usb-ehci rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:net=ne2k_pci:sdhci-mmc rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:net=pcnet:scsi[53C810] rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:net=rtl8139:scsi[53C895A] rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:net=tulip:scsi[DC395] rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:net=virtio-net:scsi[AM53C974] rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:net=i82550:scsi[MEGASAS] rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:net=i82558a:scsi[MEGASAS2] rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:net=i82562:scsi[FUSION] rootfs.ext2.gz
retcode=$((retcode + $?))

runkernel malta_defconfig nocd:nosmp:net=e1000 rootfs.cpio.gz
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:nosmp:ide:net=pcnet rootfs.ext2.gz
retcode=$((retcode + $?))

exit ${retcode}
