#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

machine=$1
cputype=$2

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-x86_64}
ARCH=x86_64

# Older releases don't like gcc 6+
rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
case "${rel}" in
"v3.16"|"v3.18")
	PATH_X86=/opt/poky/1.3/sysroots/x86_64-pokysdk-linux/usr/bin/x86_64-poky-linux
	PREFIX="x86_64-poky-linux-"
	;;
*)
	PATH_X86=/opt/kernel/x86_64/gcc-6.3.0/usr/bin/
	PREFIX="x86_64-linux-"
	;;
esac

PATH=${PATH_X86}:${PATH}

skip_316="defconfig:smp:mem512:scsi[AM53C974] \
	defconfig:smp4:efi32:mem256:scsi[DC395]"

skip_318="defconfig:smp:mem512:scsi[AM53C974] \
	defconfig:smp4:efi32:mem256:scsi[DC395]"

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
    local pid
    local logfile="$(__mktemp)"
    local waitlist=("machine restart" "Restarting" "Boot successful" "Rebooting")
    local pbuild="${ARCH}:${mach}:${cpu}:${defconfig}:${fixup}"
    local build="${defconfig}:${fixup}"
    local config="${defconfig}:${fixup//smp*/smp}"

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	pbuild+=":initrd"
    else
	pbuild+=":rootfs"
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
	return 1
    fi

    echo -n "running ..."

    kvm=""
    if [ "${cpu}" = "kvm64" ]; then
	kvm="-enable-kvm"
    fi

    [[ ${dodebug} -ne 0 ]] && set -x

    ${QEMU} -kernel arch/x86/boot/bzImage \
	-M ${mach} -cpu ${cpu} ${kvm} -no-reboot \
	${extra_params} \
	--append "earlycon=uart8250,io,0x3f8,9600n8 ${initcli} console=ttyS0 console=tty doreboot" \
	-nographic > ${logfile} 2>&1 &
    pid=$!

    [[ ${dodebug} -ne 0 ]] && set +x

    dowait ${pid} ${logfile} manual waitlist[@]
    return $?
}

echo "Build reference: $(git describe)"
echo

retcode=0

# runkernel defconfig kvm64 q35
# retcode=$((${retcode} + $?))
runkernel defconfig smp:mem256:ata Broadwell-noTSX q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp2:efi:mem512:nvme IvyBridge q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp4:efi32:mem1G:usb SandyBridge q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp:mem2G:usb-uas Haswell q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp2:efi:mem4G:mmc Skylake-Client q35 rootfs.ext2
retcode=$((${retcode} + $?))

# if [ ${runall} -eq 1 ]; then
  runkernel defconfig smp4:efi32:mem256:scsi[DC395] Conroe q35 rootfs.ext2
  retcode=$((${retcode} + $?))
  runkernel defconfig smp:mem512:scsi[AM53C974] Nehalem q35 rootfs.ext2
  retcode=$((${retcode} + $?))
# fi

runkernel defconfig smp2:efi:mem1G:scsi[53C810] Westmere-IBRS q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp4:efi32:mem2G:scsi[53C895A] Skylake-Server q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp:mem4G:scsi[FUSION] EPYC pc rootfs.ext2
retcode=$((${retcode} + $?))
# efi combined with scsi[FUSION] fails
runkernel defconfig smp2:efi:mem8G:scsi[MEGASAS] EPYC-IBPB q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp4:efi32:mem256:scsi[MEGASAS2] Opteron_G5 q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp:mem512 phenom pc rootfs.cpio
retcode=$((${retcode} + $?))
runkernel defconfig smp2:efi:mem1G Opteron_G1 q35 rootfs.cpio
retcode=$((${retcode} + $?))
runkernel defconfig smp:efi32:mem2G:scsi[virtio-pci] Opteron_G2 pc rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp2:mem4G:virtio-pci core2duo q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp4:efi:mem8G:virtio Broadwell q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp2:efi32:mem1G:virtio Nehalem q35 rootfs.ext2
retcode=$((${retcode} + $?))

runkernel defconfig nosmp:mem1G:usb Opteron_G3 pc rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig nosmp:efi:mem512:ata Opteron_G4 q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig nosmp:efi32:mem2G:ata Haswell-noTSX-IBRS q35 rootfs.ext2
retcode=$((${retcode} + $?))

exit ${retcode}
