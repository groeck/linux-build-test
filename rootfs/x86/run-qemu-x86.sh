#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

_mach=$1
_cpu=$2
_variant=$3

# Note: Upstream qemu v6.1 and later fail for Opteron_G4 and Opteron_G5
QEMU=${QEMU:-${QEMU_BIN}/qemu-system-i386}
ARCH=i386

PATH_X86="/opt/kernel/${DEFAULT_CC}/x86_64-linux/bin"
PREFIX="x86_64-linux-"

PATH=${PATH_X86}:${PATH}

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

    # Enable TPM testing
    echo "CONFIG_TCG_TPM=y" >> ${defconfig}
    echo "CONFIG_TCG_TIS=y" >> ${defconfig}
    echo "CONFIG_TCG_CRB=y" >> ${defconfig}

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

build_reference "${PREFIX}gcc" "${QEMU}"

retcode=0

runkernel defconfig smp:ata:net=rtl8139 Broadwell q35 rootfs.ext2
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel defconfig smp:tpm-tis:ata:net=e1000 Icelake-Server q35 rootfs.iso
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel defconfig smp2:tpm-tis:efi32:nvme:net=e1000e IvyBridge q35 rootfs.btrfs
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel defconfig smp4:usb:net=i82550 SandyBridge q35 rootfs.ext2
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel defconfig smp:usb-uas:net=i82562 Haswell q35 rootfs.ext2
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel defconfig smp2:efi32:sdhci-mmc:net=i82801 Skylake-Client q35 rootfs.ext2
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel defconfig smp4:scsi[DC395]:net=ne2k_pci Conroe q35 rootfs.ext2
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel defconfig smp6:scsi[AM53C974]:net=pcnet Nehalem q35 rootfs.ext2
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel defconfig smp:tpm-crb:efi32:scsi[53C810]:net=virtio-net-pci Westmere-IBRS q35 rootfs.ext2
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel defconfig smp2:tpm-crb:scsi[53C895A]:net=tulip Skylake-Server q35 rootfs.iso
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel defconfig smp:efi32:pci-bridge:scsi[MEGASAS]:net=e1000 EPYC pc rootfs.ext2
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel defconfig smp:pci-bridge:scsi[MEGASAS2]:net=e1000 EPYC-IBPB q35 rootfs.ext2
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel defconfig smp:efi32:scsi[FUSION]:net=usb Opteron_G5 q35 rootfs.squashfs
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel defconfig smp:net=i82557a phenom pc rootfs.cpio
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel defconfig smp:efi32:net=i82558a Opteron_G1 q35 rootfs.cpio
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel defconfig smp:ata:net=i82559a Opteron_G2 pc rootfs.ext2
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel defconfig smp:efi32:usb:net=i82559er core2duo q35 rootfs.ext2
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel defconfig smp:nvme:net=i82562 pentium3 q35 rootfs.ext2
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel defconfig pae:smp:net=e1000 Penryn pc rootfs.cpio
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel defconfig pae:smp:efi32:usb:net=pcnet Westmere pc rootfs.ext2
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel defconfig pae:smp:nvme:net=i82562 pentium3 q35 rootfs.ext2
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel defconfig nosmp:usb:net=e1000 Opteron_G3 pc rootfs.ext2
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel defconfig nosmp:efi32:ata:net=pcnet Opteron_G4 q35 rootfs.ext2
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel defconfig nosmp:ata:net=rtl8139 n270 q35 rootfs.ext2
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel defconfig nosmp:nvme:net=i82562 Westmere q35 rootfs.ext2
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel defconfig pae:nosmp:net=ne2k_pci pentium3 q35 rootfs.cpio
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel defconfig pae:nosmp:nvme:net=i82562 pentium3 q35 rootfs.ext2
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel defconfig pae:nosmp:efi32:sdhci-mmc:net=i82557b coreduo q35 rootfs.ext2
retcode=$((${retcode} + $?))

exit ${retcode}
