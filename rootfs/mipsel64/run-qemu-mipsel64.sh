#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

config=$1
variant=$2

skip_316="mipsel64:malta_defconfig:r1:smp:scsi[DC395]:hd"

skip_49="mipsel64:64r6el_defconfig:notests:smp:ide:hd
	mipsel64:64r6el_defconfig:notests:smp:ide:cd"

QEMU_FULOONG="${QEMU:-${QEMU_V30_BIN}/qemu-system-mips64el}"
QEMU="${QEMU:-${QEMU_BIN}/qemu-system-mips64el}"

rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
case "${rel}" in
v3.16)
	# v3.16 needs the old version of gcc
	PATH_MIPS=/opt/kernel/gcc-4.9.4-nolibc/mips64-linux/bin
	PREFIX=mips64-linux-
	;;
*)
	PATH_MIPS=/opt/kernel/gcc-7.3.0-nolibc/mips64-linux/bin
	PREFIX=mips64-linux-
	;;
esac

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
	r1)
	    echo "CONFIG_CPU_MIPS64_R1=y" >> ${defconfig}
	    ;;
	r2)
	    echo "CONFIG_CPU_MIPS64_R2=y" >> ${defconfig}
	    ;;
	nosmp)
	    echo "CONFIG_MIPS_MT_SMP=n" >> ${defconfig}
	    echo "CONFIG_SCHED_SMT=n" >> ${defconfig}
	    ;;
	smp)
	    echo "CONFIG_MIPS_MT_SMP=y" >> ${defconfig}
	    echo "CONFIG_SCHED_SMT=y" >> ${defconfig}
	    echo "CONFIG_NR_CPUS=8" >> ${defconfig}
	    ;;
	esac
    done

    echo "CONFIG_BINFMT_MISC=y" >> ${defconfig}
    echo "CONFIG_64BIT=y" >> ${defconfig}

    echo "CONFIG_MIPS32_O32=y" >> ${defconfig}
    echo "CONFIG_MIPS32_N32=y" >> ${defconfig}

    # Avoid DMA memory allocation errors
    echo "CONFIG_DEBUG_WW_MUTEX_SLOWPATH=n" >> ${defconfig}
    echo "CONFIG_DEBUG_LOCK_ALLOC=n" >> ${defconfig}
    echo "CONFIG_PROVE_LOCKING=n" >> ${defconfig}
}

runkernel()
{
    local defconfig=$1
    local mach=$2
    local rootfs=$3
    local fixup=$4
    local pid
    local retcode
    local logfile="$(__mktemp)"
    local waitlist=("Restarting system" "Boot successful" "Rebooting")
    local build="mipsel64:${defconfig}:${fixup}"
    local buildconfig="${defconfig}:${fixup//smp*/smp}"
    local wait="automatic"
    local mem
    local kernel

    if [[ "${rootfs}" == *cpio ]]; then
	build+=":initrd"
    elif [[ "${rootfs%.gz}" == *iso ]]; then
	build+=":cd"
    else
	build+=":hd"
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

    echo -n "running ..."

    case ${mach} in
    "malta")
	kernel="vmlinux"
	mem="256"
	;;
    "fulong2e")
	QEMU="${QEMU_FULOONG}"		# crashes or stalls with later versions
	kernel="vmlinux"
	extra_params+=" -vga none"	# fulong2e v3.1+ crashes if vga is enabled
	mem="256"
	;;
    "boston")
	mem=1G
	kernel="arch/mips/boot/vmlinux.gz.itb"
	extra_params+=" -dtb arch/mips/boot/dts/img/boston.dtb"
	wait="manual"
	;;
    esac

    [[ ${dodebug} -ne 0 ]] && set -x
    ${QEMU} -M ${mach} -kernel "${kernel}" \
	-no-reboot -m "${mem}" \
	${extra_params} \
	--append "${initcli} console=ttyS0" \
	-nographic -serial stdio -monitor none \
	> ${logfile} 2>&1 &
    pid=$!
    [[ ${dodebug} -ne 0 ]] && set +x

    dowait ${pid} ${logfile} ${wait} waitlist[@]
    return $?
}

echo "Build reference: $(git describe)"
echo

# Lack of memory for tests
runkernel malta_defconfig malta rootfs.mipsel64r1.ext2 r1:nosmp:ide
retcode=$?
runkernel malta_defconfig malta rootfs.mipsel64r1.cpio r1:smp
retcode=$((retcode + $?))
runkernel malta_defconfig malta rootfs.mipsel64r1.ext2 r1:smp:ide
retcode=$((retcode + $?))
runkernel malta_defconfig malta rootfs.mipsel64r1.iso r1:smp:ide
retcode=$((retcode + $?))
runkernel malta_defconfig malta rootfs.mipsel64r1.ext2 r1:smp:usb-xhci
retcode=$((retcode + $?))
runkernel malta_defconfig malta rootfs.mipsel64r1.ext2 r1:smp:usb-ehci
retcode=$((retcode + $?))
runkernel malta_defconfig malta rootfs.mipsel64r1.ext2 r1:smp:usb-uas-xhci
retcode=$((retcode + $?))
runkernel malta_defconfig malta rootfs.mipsel64r1.ext2 r1:smp:sdhci:mmc
retcode=$((retcode + $?))
if [[ ${runall} -ne 0 ]]; then
    # interrupts don't work, resulting in random timeouts
    runkernel malta_defconfig malta rootfs.mipsel64r1.ext2 r1:smp:nvme
    retcode=$((retcode + $?))
fi
runkernel malta_defconfig malta rootfs.mipsel64r1.ext2 r1:smp:scsi[DC395]
retcode=$((retcode + $?))
runkernel malta_defconfig malta rootfs.mipsel64r1.ext2 r1:smp:scsi[FUSION]
retcode=$((retcode + $?))
runkernel malta_defconfig malta rootfs.mipsel64r1.iso r1:smp:scsi[53C895A]
retcode=$((retcode + $?))
# Note: Other boot configurations fail
runkernel fuloong2e_defconfig fulong2e rootfs.mipsel.ext3 nosmp:ide
retcode=$((retcode + $?))
# Image fails to boot with tests enabled
runkernel 64r6el_defconfig boston rootfs.mipsel64r6.ext2 notests:smp:ide
retcode=$((retcode + $?))
runkernel 64r6el_defconfig boston rootfs.mipsel64r6.iso notests:smp:ide
retcode=$((retcode + $?))

exit ${retcode}
