#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

machine=$1
cputype=$2

# Note: Upstream qemu v6.1 and later fail for Opteron_G4 and Opteron_G5
QEMU=${QEMU:-${QEMU_BIN}/qemu-system-x86_64}
ARCH=x86_64

PATH_X86="/opt/kernel/${DEFAULT_CC}/x86_64-linux/bin"
PREFIX="x86_64-linux-"

PATH=${PATH_X86}:${PATH}

patch_defconfig()
{
    local defconfig=$1

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

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	pbuild+=":initrd"
    elif [[ "${rootfs%.gz}" == *iso ]]; then
	pbuild+=":cd"
    else
	pbuild+=":hd"
    fi

    if ! match_params "${machine}@${mach}" "${cputype}@${cpu}"; then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    echo -n "Building ${pbuild} ... "

    if ! checkskip "${build}" ; then
	return 0
    fi

    if ! dosetup -c  "${config}" -F "${fixup}" "${rootfs}" "${defconfig}"; then
	if [[ __dosetup_rc -eq 2 ]]; then
	    return 0
	fi
	return 1
    fi

    kvm=""
    if [ "${cpu}" = "kvm64" ]; then
	kvm="-enable-kvm"
    fi

    execute manual waitlist[@] \
      ${QEMU} -kernel arch/x86/boot/bzImage \
	-M ${mach} -cpu ${cpu} ${kvm} -no-reboot \
	${extra_params} \
	--append "earlycon=uart8250,io,0x3f8,9600n8 ${initcli} console=ttyS0" \
	-d unimp,guest_errors \
	-nographic -monitor none

    return $?
}

echo "Build reference: $(git describe)"
echo

retcode=0

# runkernel defconfig kvm64 q35
# retcode=$((retcode + $?))
runkernel defconfig smp:net,e1000:mem256:ata Broadwell-noTSX q35 rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig smp:net,e1000e:mem256:ata Cascadelake-Server q35 rootfs.iso
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig smp2:net,i82801:efi:mem512:nvme IvyBridge q35 rootfs.btrfs
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig smp4:net,ne2k_pci:efi32:mem1G:usb SandyBridge q35 rootfs.squashfs
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig smp8:net,ne2k_pci:mem1G:usb-hub SandyBridge q35 rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig smp:net,pcnet:mem2G:usb-uas Haswell q35 rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig smp2:net,rtl8139:efi:mem4G:sdhci:mmc Skylake-Client q35 rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}

# Repeat 'tulip' boot for all three variants (efi, efi32, non-efi)
# to catch potential efi related issues. Use the opportunity to also
# test different CPUs.
runkernel defconfig smp4:net,tulip:efi32:mem256:scsi[DC395] Conroe q35 rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig smp2:net,tulip:efi:mem256:scsi[DC395] Denverton q35 rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig smp:net,tulip:mem256:scsi[DC395] EPYC-Milan q35 rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig smp:net,virtio-net:mem512:scsi[AM53C974] Nehalem q35 rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig smp:net,virtio-net-old:mem512:scsi[AM53C974] Nehalem q35 rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}

runkernel defconfig smp2:net,usb-ohci:efi:mem1G:scsi[53C810] Westmere-IBRS q35 rootfs.iso
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig smp4:net,e1000-82544gc:efi32:mem2G:scsi[53C895A] Skylake-Server q35 rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig smp:pci-bridge:net,usb-uhci:mem4G:scsi[FUSION] EPYC pc rootfs.btrfs
retcode=$((retcode + $?))
checkstate ${retcode}
# efi combined with scsi[FUSION] fails
runkernel defconfig smp2:net,e1000-82545em:efi:mem8G:scsi[MEGASAS] EPYC-IBPB q35 rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig smp4:net,i82559c:efi32:mem256:scsi[MEGASAS2] Opteron_G5 q35 rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig smp4:net,i82559c:mem256:scsi[MEGASAS2] Opteron_G5 q35 rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig smp4:net,i82559c:mem256:scsi[MEGASAS2] Opteron_G5 pc rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig smp:net,i82559er:mem512 phenom pc rootfs.cpio
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig smp2:net,i82562:efi:mem1G Opteron_G1 q35 rootfs.cpio
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig smp:net,usb:efi32:mem2G:scsi[virtio-pci] Opteron_G2 pc rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig smp:net,usb:efi32:mem2G:scsi[virtio-pci-old] Opteron_G2 pc rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig smp2:net,i82559a:mem4G:virtio-pci core2duo q35 rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig smp4:net,i82558b:efi:mem8G:virtio Broadwell q35 rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig smp2:net,i82558a:efi32:mem1G:virtio Nehalem q35 rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}

runkernel defconfig preempt:smp4:net,ne2k_pci:efi:mem2G:virtio Icelake-Client q35 rootfs.iso
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig preempt:smp8:net,i82557a:mem4G:nvme Icelake-Server q35 rootfs.btrfs
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig preempt:smp2:net,i82558b:efi32:mem1G:sdhci:mmc Skylake-Client-IBRS q35 rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig preempt:smp6:net,i82550:mem512 KnightsMill q35 rootfs.cpio
retcode=$((retcode + $?))
checkstate ${retcode}

runkernel defconfig smp2:net,usb-ohci:efi:mem1G:scsi[53C810] Cooperlake q35 rootfs-x86.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig smp4:net,e1000:mem2G:scsi[53C895A] EPYC-Rome q35 rootfs-x86.ext2
retcode=$((retcode + $?))
checkstate ${retcode}

runkernel defconfig nosmp:net,e1000:mem1G:usb Opteron_G3 pc rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig nosmp:net,ne2k_pci:efi:mem512:ata Opteron_G4 q35 rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig nosmp:net,pcnet:efi32:mem2G:ata Haswell-noTSX-IBRS q35 rootfs.ext2
retcode=$((retcode + $?))

exit ${retcode}
