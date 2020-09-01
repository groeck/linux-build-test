#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

_mach=$1
_cpu=$2
_variant=$3

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-i386}
ARCH=i386

PATH_X86=/opt/kernel/gcc-8.3.0-nolibc/x86_64-linux/bin
PREFIX="x86_64-linux-"

PATH=${PATH_X86}:${PATH}

skip_44="defconfig:smp6:scsi[AM53C974] \
	defconfig:smp4:scsi[DC395]"

patch_defconfig()
{
    local defconfig=$1
    local fixups=${2//:/ }
    local fixup

    for fixup in ${fixups}; do
	case "${fixup}" in
	pae)
	    echo "CONFIG_HIGHMEM64G=y" >> ${defconfig}
	    ;;
	*)
	    ;;
	esac
    done

    # Causes problems on shutdown (lack of reboot message)
    echo "CONFIG_LOCK_TORTURE_TEST=n" >> ${defconfig}
    echo "CONFIG_RCU_TORTURE_TEST=n" >> ${defconfig}
}

runkernel()
{
    local defconfig=$1
    local fixup=$2
    local cpu=$3
    local mach=$4
    local rootfs=$5
    local drive
    local waitlist=("machine restart" "Restarting" "Boot successful" "Rebooting")
    local pbuild="${ARCH}:${mach}:${cpu}:${defconfig}:${fixup}"
    local build="${defconfig}:${fixup}"
    local config="${defconfig}:${fixup//smp*/smp}"

    if [[ "${rootfs}" == *cpio ]]; then
	pbuild+=":initrd"
    elif [[ "${rootfs%.gz}" == *iso ]]; then
	pbuild+=":cd"
    else
	pbuild+=":hd"
    fi

    if ! match_params "${_cpu}@${cpu}" "${_mach}@${mach}" "${_variant}@${fixup}"; then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    echo -n "Building ${pbuild} ... "

    if ! checkskip "${build}" ; then
	return 0
    fi

    if ! dosetup -c "${config}" -F "${fixup}" "${rootfs}" "${defconfig}"; then
	if [[ __dosetup_rc -eq 2 ]]; then
	    return 0
	fi
	return 1
    fi

    execute manual waitlist[@] \
      ${QEMU} -kernel arch/x86/boot/bzImage \
	-M ${mach} -cpu ${cpu} -no-reboot -m 256 \
	${extra_params} \
	--append "earlycon=uart8250,io,0x3f8,9600n8 ${initcli} mem=256M console=ttyS0" \
	-nographic \
	-d unimp,guest_errors

    return $?
}

echo "Build reference: $(git describe)"
echo

retcode=0

runkernel defconfig smp:ata Broadwell q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp:ata Icelake-Server q35 rootfs.iso
retcode=$((${retcode} + $?))
runkernel defconfig smp2:efi32:nvme IvyBridge q35 rootfs.btrfs
retcode=$((${retcode} + $?))
runkernel defconfig smp4:usb SandyBridge q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp:usb-uas Haswell q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp2:efi32:sdhci:mmc Skylake-Client q35 rootfs.ext2
retcode=$((${retcode} + $?))

runkernel defconfig smp4:scsi[DC395] Conroe q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp6:scsi[AM53C974] Nehalem q35 rootfs.ext2
retcode=$((${retcode} + $?))

runkernel defconfig smp:efi32:scsi[53C810] Westmere-IBRS q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp2:scsi[53C895A] Skylake-Server q35 rootfs.iso
retcode=$((${retcode} + $?))
runkernel defconfig smp:efi32:scsi[MEGASAS] EPYC pc rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp:scsi[MEGASAS2] EPYC-IBPB q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp:efi32:scsi[FUSION] Opteron_G5 q35 rootfs.squashfs
retcode=$((${retcode} + $?))
runkernel defconfig smp phenom pc rootfs.cpio
retcode=$((${retcode} + $?))
runkernel defconfig smp:efi32 Opteron_G1 q35 rootfs.cpio
retcode=$((${retcode} + $?))
runkernel defconfig smp:ata Opteron_G2 pc rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp:efi32:usb core2duo q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig pae:smp Penryn pc rootfs.cpio
retcode=$((${retcode} + $?))
runkernel defconfig pae:smp:efi32:usb Westmere pc rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig nosmp:usb Opteron_G3 pc rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig nosmp:efi32:ata Opteron_G4 q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig nosmp:ata n270 q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig pae:nosmp pentium3 q35 rootfs.cpio
retcode=$((${retcode} + $?))
runkernel defconfig pae:nosmp:nvme pentium3 q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig pae:nosmp:efi32:sdhci:mmc coreduo q35 rootfs.ext2
retcode=$((${retcode} + $?))

exit ${retcode}
