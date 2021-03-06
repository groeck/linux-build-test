#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

config=$1
variant=$2

skip_49="mipsel64:64r6el_defconfig:notests:nonet:smp:ide:hd
	mipsel64:64r6el_defconfig:notests:nonet:smp:ide:cd"

QEMU="${QEMU:-${QEMU_BIN}/qemu-system-mips64el}"

# gcc 9.x and 10.x refuse to compile fuloong2e_defconfig
# for older kernels.
# cc1: error: '-mloongson-mmi' must be used with '-mhard-float'
PATH_MIPS=/opt/kernel/gcc-8.4.0-nolibc/mips64-linux/bin
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
	r1)
	    enable_config "${defconfig}" CONFIG_CPU_MIPS64_R1
	    ;;
	r2)
	    enable_config "${defconfig}" CONFIG_CPU_MIPS64_R2
	    ;;
	nosmp)
	    disable_config "${defconfig}" CONFIG_MIPS_MT_SMP
	    disable_config "${defconfig}" CONFIG_SCHED_SMT
	    ;;
	smp)
	    enable_config "${defconfig}" CONFIG_MIPS_MT_SMP
	    enable_config "${defconfig}" CONFIG_SCHED_SMT
	    ;;
	esac
    done

    enable_config "${defconfig}" CONFIG_BINFMT_MISC
    enable_config "${defconfig}" CONFIG_64BIT

    enable_config "${defconfig}" CONFIG_MIPS32_O32
    enable_config "${defconfig}" CONFIG_MIPS32_N32
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

    case ${mach} in
    "malta")
	kernel="vmlinux"
	mem="256"
	;;
    "fuloong2e")
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

echo "Build reference: $(git describe)"
echo

# Network tests:
# - i82551 fails to instantiate

runkernel malta_defconfig malta rootfs.mipsel64r1_n64.ext2 nocd:r1:nosmp:ide:net,e1000
retcode=$?
runkernel malta_defconfig malta rootfs.mipsel64r1_n64.cpio nocd:r1:smp:net,pcnet
retcode=$((retcode + $?))
runkernel malta_defconfig malta rootfs.mipsel64r1_n32.ext2 nocd:r1:smp:ide:net,i82550
retcode=$((retcode + $?))
runkernel malta_defconfig malta rootfs.mipsel64r1_n64.iso nocd:r1:smp:ide:net,i82558a
retcode=$((retcode + $?))
runkernel malta_defconfig malta rootfs.mipsel64r1_n32.ext2 nocd:r1:smp:usb-xhci:net,usb-ohci
retcode=$((retcode + $?))
runkernel malta_defconfig malta rootfs.mipsel64r1_n64.ext2 nocd:r1:smp:usb-ehci:net,ne2k_pci
retcode=$((retcode + $?))
runkernel malta_defconfig malta rootfs.mipsel64r1_n32.ext2 nocd:r1:smp:usb-uas-xhci:net,rtl8139
retcode=$((retcode + $?))
runkernel malta_defconfig malta rootfs.mipsel64r1_n64.ext2 nocd:r1:smp:sdhci:mmc:net,i82801
retcode=$((retcode + $?))
if [[ ${runall} -ne 0 ]]; then
    # interrupts are unreliable, resulting in random timeouts
    runkernel malta_defconfig malta rootfs.mipsel64r1_n64.ext2 nocd:r1:smp:net,pcnet:nvme
    retcode=$((retcode + $?))
fi
runkernel malta_defconfig malta rootfs.mipsel64r1_n32.ext2 nocd:r1:smp:scsi[DC395]:net,virtio-net
retcode=$((retcode + $?))
runkernel malta_defconfig malta rootfs.mipsel64r1_n64.ext2 nocd:r1:smp:scsi[FUSION]:net,tulip
retcode=$((retcode + $?))
runkernel malta_defconfig malta rootfs.mipsel64r1_n64.iso nocd:r1:smp:scsi[53C895A]:net,i82559er
retcode=$((retcode + $?))
# Note: Other boot configurations fail
runkernel fuloong2e_defconfig fuloong2e rootfs.mipsel.ext3 nosmp:ide
retcode=$((retcode + $?))
# Image fails to boot with tests enabled
# Network interfaces don't instantiate.
runkernel 64r6el_defconfig boston rootfs.mipsel64r6_n32.ext2 notests:nonet:smp:ide
retcode=$((retcode + $?))
runkernel 64r6el_defconfig boston rootfs.mipsel64r6_n64.ext2 notests:nonet:smp:ide
retcode=$((retcode + $?))
runkernel 64r6el_defconfig boston rootfs.mipsel64r6_n64.iso notests:nonet:smp:ide
retcode=$((retcode + $?))

exit ${retcode}
