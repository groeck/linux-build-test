#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

config=$1
variant=$2
fs=$3

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-mips64}

PATH_MIPS="/opt/kernel/${DEFAULT_CC}/mips64-linux/bin"
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

    # Enable flash boot
    enable_config "${defconfig}" CONFIG_MTD_PHYSMAP CONFIG_MTD_PHYSMAP_OF

    for fixup in ${fixups}; do
        case "${fixup}" in
	"ps4")
	    # Some file systems only work with 4k page size
	    disable_config "${defconfig}" CONFIG_PAGE_SIZE_16KB
	    enable_config "${defconfig}" CONFIG_PAGE_SIZE_4KB
	    ;;
	"fstest")
	    # File system support
	    enable_config "${defconfig}" CONFIG_F2FS_FS
	    enable_config "${defconfig}" CONFIG_EXFAT_FS
	    enable_config "${defconfig}" CONFIG_HFSPLUS_FS
	    enable_config "${defconfig}" CONFIG_HFS_FS
	    enable_config "${defconfig}" CONFIG_JFS_FS
	    enable_config "${defconfig}" CONFIG_NILFS2_FS
	    enable_config "${defconfig}" CONFIG_XFS_FS

	    enable_config "${defconfig}" CONFIG_EROFS_FS
	    enable_config "${defconfig}" CONFIG_GFS2_FS
	    enable_config "${defconfig}" CONFIG_MINIX_FS
	    ;;
	"smp")
	    enable_config "${defconfig}" CONFIG_MIPS_MT_SMP
	    enable_config "${defconfig}" CONFIG_SCHED_SMT
	    ;;
	"nosmp")
	    disable_config "${defconfig}" CONFIG_MIPS_MT_SMP
	    disable_config "${defconfig}" CONFIG_SCHED_SMT
	    ;;
	esac
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
	build+=":${rootfs##*.}"
    fi

    if ! match_params "${config}@${defconfig}" "${variant}@${fixup}" "${fs}@${rootfs}"; then
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

echo "Build reference: $(git describe --match 'v*')"
echo

retcode=0

# Disable CD support to avoid DMA memory allocation errors

runkernel malta_defconfig nocd:smp:net=e1000 rootfs-n32.cpio
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:net=e1000:flash4,1,1 rootfs-n64.squashfs
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:net=e1000-82544gc:ide rootfs-n32.ext2
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:net=i82801:sdhci-mmc rootfs-n64.ext2
retcode=$((retcode + $?))

runkernel malta_defconfig nocd:smp:net=pcnet:nvme rootfs-n32.ext2
retcode=$((retcode + $?))

runkernel malta_defconfig nocd:smp:net=ne2k_pci:usb-xhci rootfs-n32.${btrfs}
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:net=pcnet:usb-ehci rootfs-n32.ext2
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:net=rtl8139:usb-uas-xhci rootfs-n64.ext2
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:net=tulip:scsi[53C810] rootfs-n32.ext2
retcode=$((retcode + $?))

if [[ ${runall} -ne 0 ]]; then
    # Run all file system tests, even those known to fail
    runkernel malta_defconfig fstest:ps4:nocd:smp:net=e1000:ide rootfs-n32.btrfs
    retcode=$((retcode + $?))
    runkernel malta_defconfig fstest:ps4:nocd:smp:net=e1000:ide rootfs-n32.erofs
    retcode=$((retcode + $?))
    runkernel malta_defconfig fstest:ps4:nocd:smp:net=e1000:ide rootfs-n32.f2fs
    retcode=$((retcode + $?))
    runkernel malta_defconfig fstest:nocd:smp:net=e1000:ide rootfs-n32.btrfs
    retcode=$((retcode + $?))
    runkernel malta_defconfig fstest:nocd:smp:net=e1000:ide rootfs-n32.erofs
    retcode=$((retcode + $?))
    runkernel malta_defconfig fstest:nocd:smp:net=e1000:ide rootfs-n32.f2fs
    retcode=$((retcode + $?))
    runkernel malta_defconfig fstest:nocd:smp:net=e1000:ide:fstest=exfat rootfs-n32.ext2
    retcode=$((retcode + $?))
    runkernel malta_defconfig fstest:nocd:smp:net=e1000:ide:fstest=hfs rootfs-n32.ext2
    retcode=$((retcode + $?))
    runkernel malta_defconfig fstest:nocd:smp:net=e1000:ide:fstest=hfs+ rootfs-n32.ext2
    retcode=$((retcode + $?))
    runkernel malta_defconfig fstest:nocd:smp:net=e1000:ide:fstest=gfs2 rootfs-n32.ext2
    retcode=$((retcode + $?))
    runkernel malta_defconfig fstest:nocd:smp:net=e1000:ide:fstest=jfs rootfs-n32.ext2
    retcode=$((retcode + $?))
    runkernel malta_defconfig fstest:nocd:smp:net=e1000:ide:fstest=minix rootfs-n32.ext2
    retcode=$((retcode + $?))
    runkernel malta_defconfig fstest:nocd:smp:net=e1000:ide:fstest=nilfs2 rootfs-n32.ext2
    retcode=$((retcode + $?))
    runkernel malta_defconfig fstest:nocd:smp:net=e1000:ide:fstest=xfs rootfs-n32.ext2
    retcode=$((retcode + $?))

fi

if [[ ${runall} -ne 0 ]]; then
    # sym0: interrupted SCRIPT address not found
    runkernel malta_defconfig nocd:smp:scsi[53C895A] rootfs-n32.ext2
    retcode=$((retcode + $?))
fi

runkernel malta_defconfig nocd:smp:net=virtio-net:scsi[DC395] rootfs-n64.ext2
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:net=i82562:scsi[AM53C974]${exfat} rootfs-n32.ext2
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:pci-bridge:net=e1000:scsi[MEGASAS] rootfs-n64.ext2
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:pci-bridge:net=rtl8139:scsi[MEGASAS2] rootfs-n32.ext2
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:smp:net=ne2k_pci:scsi[FUSION] rootfs-n64.${btrfs}
retcode=$((retcode + $?))

runkernel malta_defconfig nocd:nosmp:net=pcnet:ide rootfs-n32.ext2
retcode=$((retcode + $?))
runkernel malta_defconfig nocd:nosmp:pci-bridge:net=tulip:sdhci-mmc rootfs-n64.ext2
retcode=$((retcode + $?))

exit ${retcode}
