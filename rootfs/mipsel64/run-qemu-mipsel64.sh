#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

config=$1
variant=$2

QEMU="${QEMU:-${QEMU_BIN}/qemu-system-mips64el}"

PATH_MIPS="/opt/kernel/${DEFAULT_CC}/mips64-linux/bin"

PREFIX=mips64-linux-

# machine specific information
ARCH=mips
PATH=${PATH_MIPS}:${PATH}

# Called from dosetup() to patch the configuration file.
patch_defconfig()
{
    local defconfig=$1
    local fixups=${2//:/ }
    local fixup

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
	    enable_config ${defconfig} CONFIG_EROFS_FS
	    enable_config ${defconfig} CONFIG_EXFAT_FS
	    enable_config ${defconfig} CONFIG_F2FS_FS
	    enable_config ${defconfig} CONFIG_GFS2_FS
	    enable_config ${defconfig} CONFIG_HFS_FS
	    enable_config ${defconfig} CONFIG_HFSPLUS_FS
	    enable_config ${defconfig} CONFIG_JFS_FS
	    enable_config ${defconfig} CONFIG_MINIX_FS
	    enable_config ${defconfig} CONFIG_NILFS2_FS
	    enable_config ${defconfig} CONFIG_XFS_FS
	    ;;
	"r1")
	    enable_config "${defconfig}" CONFIG_CPU_MIPS64_R1
	    ;;
	"r2")
	    enable_config "${defconfig}" CONFIG_CPU_MIPS64_R2
	    ;;
	"nosmp")
	    disable_config "${defconfig}" CONFIG_MIPS_MT_SMP CONFIG_SCHED_SMT
	    ;;
	"smp")
	    enable_config "${defconfig}" CONFIG_MIPS_MT_SMP CONFIG_SCHED_SMT
	    ;;
	esac
    done


    enable_config "${defconfig}" CONFIG_BINFMT_MISC CONFIG_64BIT
    enable_config "${defconfig}" CONFIG_MIPS32_O32 CONFIG_MIPS32_N32

    # Enable flash boot
    enable_config "${defconfig}" CONFIG_MTD_PHYSMAP CONFIG_MTD_PHYSMAP_OF

    # Avoid DMA memory allocation errors
    disable_config "${defconfig}" CONFIG_DEBUG_WW_MUTEX_SLOWPATH CONFIG_DEBUG_LOCK_ALLOC CONFIG_PROVE_LOCKING
}

runkernel()
{
    local defconfig=$1
    local mach=$2
    local rootfs=$3
    local fixup=$4
    local waitlist=("Restarting system" "Boot successful" "Rebooting")
    local build="mipsel64:${defconfig}:${fixup}"
    local buildconfig="${defconfig}:${fixup//smp*/smp}"
    local wait="automatic"
    local mem
    local kernel

    if [[ "${rootfs}" == *cpio ]]; then
	build+=":initrd"
    elif [[ "${rootfs}" == *iso ]]; then
	build+=":cd"
    else
	build+=":${rootfs##*.}"
    fi

    if ! match_params "${config}@${defconfig}" "${variant}@${fixup}"; then
	echo "Skipping ${build} ... "
	return 0
    fi

    echo -n "Building ${build} ... "

    if ! checkskip "${build}"; then
	return 0;
    fi

    if ! dosetup -c "${buildconfig}" -F "${fixup}" "${rootfs}" "${defconfig}"; then
	if [[ __dosetup_rc -eq 2 ]]; then
	    return 0
	fi
	return 1
    fi

    case ${mach} in
    "malta")
	kernel="vmlinux"
	mem="256"
	;;
    "boston")
	mem=1G
	kernel="arch/mips/boot/vmlinux.gz.itb"
	extra_params+=" -dtb arch/mips/boot/dts/img/boston.dtb"
	wait="manual"
	;;
    esac

    execute ${wait} waitlist[@] \
      ${QEMU} -M ${mach} -kernel "${kernel}" \
	-no-reboot -m "${mem}" \
	${extra_params} \
	--append "${initcli} console=ttyS0" \
	-nographic -serial stdio -monitor none

    return $?
}

echo "Build reference: $(git describe --match 'v*')"
echo

# erofs is only supported in v5.4 and later
if [[ ${linux_version_code} -ge $(kernel_version 5 4) ]]; then
    erofs="erofs"
else
    erofs="ext2"
fi

# With malta_defconfig, btrfs only works with v6.1 and later and otherwise
# fails to run init
if [[ ${linux_version_code} -ge $(kernel_version 6 1) ]]; then
    btrfs="btrfs"
else
    btrfs="ext2"
fi

# Network tests:
# - i82551 fails to instantiate

if [[ ${runall} -ne 0 ]]; then
    # Run all file system tests, even those known to fail
    runkernel malta_defconfig malta rootfs.mipsel64r1_n64.btrfs fstest:ps4:r1:smp:ide:net=e1000
    retcode=$((retcode + $?))
    runkernel malta_defconfig malta rootfs.mipsel64r1_n64.erofs fstest:ps4:r1:smp:ide:net=e1000
    retcode=$((retcode + $?))
    runkernel malta_defconfig malta rootfs.mipsel64r1_n64.f2fs fstest:ps4:r1:smp:ide:net=e1000
    retcode=$((retcode + $?))
    runkernel malta_defconfig malta rootfs.mipsel64r1_n64.btrfs fstest:r1:smp:ide:net=e1000
    retcode=$((retcode + $?))
    runkernel malta_defconfig malta rootfs.mipsel64r1_n64.erofs fstest:r1:smp:ide:net=e1000
    retcode=$((retcode + $?))
    runkernel malta_defconfig malta rootfs.mipsel64r1_n64.f2fs fstest:r1:smp:ide:net=e1000
    retcode=$((retcode + $?))
    runkernel malta_defconfig malta rootfs.mipsel64r1_n64.ext2 fstest:r1:smp:ide:net=e1000:fstest=exfat
    retcode=$((retcode + $?))
    runkernel malta_defconfig malta rootfs.mipsel64r1_n64.ext2 fstest:r1:smp:ide:net=e1000:fstest=gfs2
    retcode=$((retcode + $?))
    runkernel malta_defconfig malta rootfs.mipsel64r1_n64.ext2 fstest:r1:smp:ide:net=e1000:fstest=hfs
    retcode=$((retcode + $?))
    runkernel malta_defconfig malta rootfs.mipsel64r1_n64.ext2 fstest:r1:smp:ide:net=e1000:fstest=hfs+
    retcode=$((retcode + $?))
    runkernel malta_defconfig malta rootfs.mipsel64r1_n64.ext2 fstest:r1:smp:ide:net=e1000:fstest=jfs
    retcode=$((retcode + $?))
    runkernel malta_defconfig malta rootfs.mipsel64r1_n64.ext2 fstest:r1:smp:ide:net=e1000:fstest=minix
    retcode=$((retcode + $?))
    runkernel malta_defconfig malta rootfs.mipsel64r1_n64.ext2 fstest:r1:smp:ide:net=e1000:fstest=nilfs2
    retcode=$((retcode + $?))
    runkernel malta_defconfig malta rootfs.mipsel64r1_n64.ext2 fstest:r1:smp:ide:net=e1000:fstest=xfs
    retcode=$((retcode + $?))
fi

runkernel malta_defconfig malta rootfs.mipsel64r1_n64.ext2 r1:nosmp:ide:net=e1000
retcode=$?
runkernel malta_defconfig malta rootfs.mipsel64r1_n64.cpio r1:smp:net=pcnet
retcode=$((retcode + $?))
runkernel malta_defconfig malta rootfs.mipsel64r1_n64.squashfs r1:smp:net=pcnet:flash4,1,1
retcode=$((retcode + $?))
runkernel malta_defconfig malta rootfs.mipsel64r1_n32.ext2 r1:smp:ide:net=i82550
retcode=$((retcode + $?))
runkernel malta_defconfig malta rootfs.mipsel64r1_n64.iso r1:smp:ide:net=i82558a
retcode=$((retcode + $?))
runkernel malta_defconfig malta rootfs.mipsel64r1_n32.ext2 r1:smp:usb-xhci:net=usb-ohci
retcode=$((retcode + $?))
runkernel malta_defconfig malta rootfs.mipsel64r1_n64.ext2 r1:smp:usb-ehci:net=ne2k_pci
retcode=$((retcode + $?))
runkernel malta_defconfig malta rootfs.mipsel64r1_n32.ext2 r1:smp:usb-uas-xhci:net=rtl8139
retcode=$((retcode + $?))
runkernel malta_defconfig malta rootfs.mipsel64r1_n64.ext2 r1:smp:sdhci-mmc:net=i82801
retcode=$((retcode + $?))
runkernel malta_defconfig malta rootfs.mipsel64r1_n64.${btrfs} r1:smp:net=pcnet:nvme
retcode=$((retcode + $?))
runkernel malta_defconfig malta rootfs.mipsel64r1_n32.${btrfs} r1:smp:scsi[DC395]:net=virtio-net
retcode=$((retcode + $?))
runkernel malta_defconfig malta rootfs.mipsel64r1_n64.ext2 r1:smp:scsi[FUSION]:net=tulip
retcode=$((retcode + $?))
runkernel malta_defconfig malta rootfs.mipsel64r1_n64.iso r1:smp:scsi[53C895A]:net=i82559er
retcode=$((retcode + $?))
# Image fails to boot with tests enabled
# Network interfaces don't instantiate.
runkernel 64r6el_defconfig boston rootfs.mipsel64r6_n32.ext2 notests:nonet:smp:ide
retcode=$((retcode + $?))
runkernel 64r6el_defconfig boston rootfs.mipsel64r6_n32.${erofs} notests:nonet:smp:ide
retcode=$((retcode + $?))
runkernel 64r6el_defconfig boston rootfs.mipsel64r6_n32.f2fs notests:nonet:smp:ide
retcode=$((retcode + $?))
runkernel 64r6el_defconfig boston rootfs.mipsel64r6_n64.ext2 notests:nonet:smp:ide
retcode=$((retcode + $?))
runkernel 64r6el_defconfig boston rootfs.mipsel64r6_n64.${erofs} notests:nonet:smp:ide
retcode=$((retcode + $?))
runkernel 64r6el_defconfig boston rootfs.mipsel64r6_n64.f2fs notests:nonet:smp:ide
retcode=$((retcode + $?))
runkernel 64r6el_defconfig boston rootfs.mipsel64r6_n64.btrfs notests:nonet:smp:ide
retcode=$((retcode + $?))
runkernel 64r6el_defconfig boston rootfs.mipsel64r6_n64.iso notests:nonet:smp:ide
retcode=$((retcode + $?))

exit ${retcode}
