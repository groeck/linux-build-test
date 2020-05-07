#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

config=$1
variant=$2

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-mips64}

rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)

case ${rel} in
v3.16)
	PATH_MIPS=/opt/kernel/gcc-4.9.0-nolibc/mips-linux/bin
	PREFIX=mips-linux-
	;;
*)
	PATH_MIPS=/opt/kernel/gcc-8.3.0-nolibc/mips64-linux/bin
	PREFIX=mips64-linux-
	;;
esac

cpu="-cpu 5KEc"

# machine specific information
ARCH=mips
KERNEL_IMAGE=vmlinux
QEMU_MACH=malta

PATH=${PATH_MIPS}:${PATH}

skip_316="mips64:malta_defconfig:initrd \
	mips64:malta_defconfig:smp:ide:rootfs \
	mips64:malta_defconfig:smp:usb-xhci:rootfs \
	mips64:malta_defconfig:smp:usb-ehci:rootfs \
	mips64:malta_defconfig:smp:scsi[53C810]:rootfs \
	mips64:malta_defconfig:smp:scsi[DC395]:rootfs \
	mips64:malta_defconfig:smp:scsi[AM53C974]:rootfs \
	mips64:malta_defconfig:smp:scsi[MEGASAS2]:rootfs \
	mips64:malta_defconfig:nosmp:ide:rootfs"

patch_defconfig()
{
    local defconfig=$1
    local fixups=${2//:/ }
    local fixup

    # 64 bit build
    echo "CONFIG_32BIT=n" >> ${defconfig}
    echo "CONFIG_CPU_MIPS32_R1=n" >> ${defconfig}
    echo "CONFIG_CPU_MIPS64_R1=y" >> ${defconfig}
    echo "CONFIG_64BIT=y" >> ${defconfig}

    # Support N32 and O32 binaries
    echo "CONFIG_MIPS32_O32=y" >> ${defconfig}
    echo "CONFIG_MIPS32_N32=y" >> ${defconfig}

    # Build a big endian image
    echo "CONFIG_CPU_LITTLE_ENDIAN=n" >> ${defconfig}
    echo "CONFIG_CPU_BIG_ENDIAN=y" >> ${defconfig}

    for fixup in ${fixups}; do
	if [[ "${fixup}" == "smp" ]]; then
	    echo "CONFIG_MIPS_MT_SMP=y" >> ${defconfig}
	    echo "CONFIG_SCHED_SMT=y" >> ${defconfig}
	    echo "CONFIG_NR_CPUS=8" >> ${defconfig}
	elif [[ "${fixup}" == "nosmp" ]]; then
	    echo "CONFIG_MIPS_MT_SMP=n" >> ${defconfig}
	    echo "CONFIG_SCHED_SMT=n" >> ${defconfig}
	fi
    done

    # Any of the following result in crashes due to lack of memory,
    # at least with v3.18.y.
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
    local build="mips64:${defconfig}"
    local cache="${defconfig}${fixup//smp*/smp}"

    if [[ "${rootfs}" == *.cpio* ]]; then
	build+=":initrd"
    else
	build+=":${fixup}"
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

runkernel malta_defconfig smp rootfs-n32.cpio.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:ide rootfs-n32.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:sdhci:mmc rootfs-n64.ext2.gz
retcode=$((retcode + $?))

if [[ ${runall} -ne 0 ]]; then
    # QID timeout, hang
    runkernel malta_defconfig smp:nvme rootfs-n32.ext2.gz
    retcode=$((retcode + $?))
fi

runkernel malta_defconfig smp:usb-xhci rootfs-n32.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:usb-ehci rootfs-n32.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:usb-uas-xhci rootfs-n64.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:scsi[53C810] rootfs-n32.ext2.gz
retcode=$((retcode + $?))

if [[ ${runall} -ne 0 ]]; then
    # sym0: interrupted SCRIPT address not found
    runkernel malta_defconfig smp:scsi[53C895A] rootfs-n32.ext2.gz
    retcode=$((retcode + $?))
fi

runkernel malta_defconfig smp:scsi[DC395] rootfs-n64.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:scsi[AM53C974] rootfs-n32.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:scsi[MEGASAS] rootfs-n64.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:scsi[MEGASAS2] rootfs-n32.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig smp:scsi[FUSION] rootfs-n64.ext2.gz
retcode=$((retcode + $?))

runkernel malta_defconfig nosmp:ide rootfs-n32.ext2.gz
retcode=$((retcode + $?))
runkernel malta_defconfig nosmp:sdhci:mmc rootfs-n64.ext2.gz
retcode=$((retcode + $?))

exit ${retcode}
