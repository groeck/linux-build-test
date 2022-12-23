#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

machine=$1
_fixup=$2
config=$3

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-sparc64}

PREFIX=sparc64-linux-
ARCH=sparc64
# PATH_SPARC=/opt/kernel/gcc-10.3.0-nolibc/sparc64-linux/bin
PATH_SPARC=/opt/kernel/${DEFAULT_CC}/sparc64-linux/bin

PATH=${PATH_SPARC}:${PATH}

patch_defconfig()
{
    local defconfig=$1
    local fixup=$2

    # enable ATA instead of IDE.
    echo "CONFIG_IDE=n" >> ${defconfig}
    echo "CONFIG_ATA=y" >> ${defconfig}
    # enable the ATA controller
    echo "CONFIG_PATA_CMD64X=y" >> ${defconfig}
    # enable ethernet interface
    echo "CONFIG_NET_VENDOR_SUN=y" >> ${defconfig}
    echo "CONFIG_HAPPYMEAL=y" >> ${defconfig}
}

runkernel()
{
    local defconfig=$1
    local mach=$2
    local fixup=$3
    local rootfs=$4
    local waitlist=("Power down" "Boot successful" "Poweroff")
    local build="${ARCH}:${mach}:${fixup}"

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	build+=":initrd"
    elif [[ "${rootfs%.gz}" == *iso ]]; then
	build+=":cd"
    else
	build+=":hd"
    fi

    if ! match_params "${machine}@${mach}" "${_fixup}@${fixup}" "${config}@${defconfig}"; then
	echo "Skipping ${build} ... "
	return 0
    fi

    echo -n "Building ${build} ... "

    if ! checkskip "${build}" ; then
	return 0
    fi

    pcibus_set_root "pciB"

    if ! dosetup -c "${defconfig}:${fixup//smp*/smp}" -F "${fixup}" "${rootfs}" "${defconfig}"; then
	if [[ __dosetup_rc -eq 2 ]]; then
	    return 0
	fi
	return 1
    fi

    # Explicitly select TI UltraSparc IIi. Non-TI CPUs (including the default
    # CPU for sun4v, Sun-UltraSparc-T1) result in a qemu crash or are stuck
    # in an endless loop at poweroff/reboot.
    execute automatic waitlist[@] \
      ${QEMU} -M ${mach} -cpu "TI UltraSparc IIi" \
	-m 512 \
	${extra_params} \
	-kernel arch/sparc/boot/image -no-reboot \
	-append "${initcli} console=ttyS0" \
	-nographic -monitor none

    return $?
}

echo "Build reference: $(git describe --match 'v*')"
echo

# Network test notes:
# - ne2k_pci gets an IP address, but fails to ping the host
# - i82557a/b/c do not get an IP address
#
runkernel sparc64_defconfig sun4u nodebug:smp:net,default rootfs.cpio.gz
retcode=$?
runkernel sparc64_defconfig sun4u nodebug:smp:ata:net,rtl8139 rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4u nodebug:smp:ata:net,e1000 rootfs.iso.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4u nodebug:smp:ata:net,e1000-82544gc rootfs.squashfs
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4u nodebug:smp:sdhci:mmc:net,rtl8139 rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4u nodebug:smp:nvme:net,tulip rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4u "nodebug:smp:scsi[DC395]:net,i82559c" rootfs.iso.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4u "nodebug:smp:scsi[MEGASAS]:net,i82559a" rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4u "nodebug:smp:scsi[AM53C974]:net,usb-net" rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4u nodebug:smp:usb-xhci:net,virtio-net-pci rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4u nodebug:smp:usb-xhci:net,virtio-net-pci-old rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4u nodebug:smp:usb-uas-xhci:net,i82801 rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4u nodebug:smp:virtio-pci:net,i82559er rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4u nodebug:smp:virtio-pci-old:net,i82559er rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4v nodebug:smp:ata:net,i82562 rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4v nodebug:smp:ata:net,e1000-82545em rootfs.iso.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4v nodebug:smp:nvme:net,default rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4u nodebug:nosmp:ata:net,e1000 rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel sparc64_defconfig sun4v nodebug:nosmp:ata:net,pcnet rootfs.ext2.gz
retcode=$((retcode + $?))

exit ${retcode}
