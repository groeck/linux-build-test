#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

config=$1
variant=$2

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-mips64}

PATH_MIPS=/opt/kernel/gcc-10.3.0-nolibc/mips64-linux/bin
PREFIX=mips64-linux-

cpu="-cpu 5KEc"

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

    # 64 bit build
    disable_config "${defconfig}" CONFIG_32BIT
    disable_config "${defconfig}" CONFIG_CPU_MIPS32_R1
    enable_config "${defconfig}" CONFIG_CPU_MIPS64_R1
    enable_config "${defconfig}" CONFIG_64BIT

    # Support N32 and O32 binaries
    enable_config "${defconfig}" CONFIG_MIPS32_O32
    enable_config "${defconfig}" CONFIG_MIPS32_N32

    # Build a big endian image
    disable_config "${defconfig}" CONFIG_CPU_LITTLE_ENDIAN
    enable_config "${defconfig}" CONFIG_CPU_BIG_ENDIAN

    for fixup in ${fixups}; do
	if [[ "${fixup}" == "smp" ]]; then
	    enable_config "${defconfig}" CONFIG_MIPS_MT_SMP
	    enable_config "${defconfig}" CONFIG_SCHED_SMT
	elif [[ "${fixup}" == "nosmp" ]]; then
	    disable_config "${defconfig}" CONFIG_MIPS_MT_SMP
	    disable_config "${defconfig}" CONFIG_SCHED_SMT
	fi
    done
}

runkernel()
{
    local defconfig=$1
    local fixup=$2
    local rootfs=$3
    local waitlist=("Boot successful" "Rebooting")
    local build="mips64:${defconfig}"
    local cache="${defconfig}${fixup//smp*/smp}"

    build+=":${fixup}"
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

    if ! dosetup -c "${cache}" -F "${fixup}" "${rootfs}" "${defconfig}"; then
	if [[ __dosetup_rc -eq 2 ]]; then
	    return 0
	fi
	return 1
    fi

    execute automatic waitlist[@] \
      ${QEMU} -kernel ${KERNEL_IMAGE} -M ${QEMU_MACH} \
	${cpu} \
	${extra_params} \
	-vga cirrus -no-reboot -m 256 \
	--append "${initcli} mem=256M console=ttyS0 console=tty ${extracli}" \
	-nographic

    return $?
}

echo "Build reference: $(git describe)"
echo

retcode=0

# Disable CD support to avoid DMA memory allocation errors

runkernel malta_defconfig nocd:smp:net,e1000 rootfs-n32.cpio.gz
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:net,e1000-82544gc:ide rootfs-n32.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:net,i82801:sdhci:mmc rootfs-n64.ext2.gz
retcode=$((retcode + $?))

if [[ ${runall} -ne 0 ]]; then
    # interrupts are unreliable, causing random timeouts
    runkernel malta_defconfig smp:net,pcnet:nvme rootfs-n32.ext2.gz
    retcode=$((retcode + $?))
fi

runkernel malta_defconfig nocd:smp:net,ne2k_pci:usb-xhci rootfs-n32.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:net,pcnet:usb-ehci rootfs-n32.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:net,rtl8139:usb-uas-xhci rootfs-n64.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:net,tulip:scsi[53C810] rootfs-n32.ext2.gz
retcode=$((retcode + $?))

if [[ ${runall} -ne 0 ]]; then
    # sym0: interrupted SCRIPT address not found
    runkernel malta_defconfig nocd:smp:scsi[53C895A] rootfs-n32.ext2.gz
    retcode=$((retcode + $?))
fi

runkernel malta_defconfig nocd:smp:net,virtio-net:scsi[DC395] rootfs-n64.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:net,i82562:scsi[AM53C974] rootfs-n32.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:pci-bridge:net,e1000:scsi[MEGASAS] rootfs-n64.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:pci-bridge:net,rtl8139:scsi[MEGASAS2] rootfs-n32.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:net,ne2k_pci:scsi[FUSION] rootfs-n64.ext2.gz
retcode=$((retcode + $?))

runkernel malta_defconfig nocd:nosmp:net,pcnet:ide rootfs-n32.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:nosmp:pci-bridge:net,tulip:sdhci:mmc rootfs-n64.ext2.gz
retcode=$((retcode + $?))

exit ${retcode}
