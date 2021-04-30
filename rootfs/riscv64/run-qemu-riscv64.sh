#!/bin/bash

progdir=$(cd $(dirname "$0"); pwd)
. "${progdir}/../scripts/config.sh"
. "${progdir}/../scripts/common.sh"

parse_args "$@"
shift $((OPTIND - 1))

_mach="$1"
_fixup="$2"

QEMU_V40=${QEMU:-${QEMU_V40_BIN}/qemu-system-riscv64}
QEMU=${QEMU:-${QEMU_BIN}/qemu-system-riscv64}
PREFIX=riscv64-linux-
ARCH=riscv
PATH_RISCV=/opt/kernel/gcc-10.3.0-nolibc/riscv64-linux/bin

PATH=${PATH}:${PATH_RISCV}

skip_419="riscv:virt:defconfig:net,virtio-net-device:usb-ohci:rootfs \
	riscv:sifive_u:defconfig:net,default:initrd \
	riscv:sifive_u:defconfig:sd:net,default:rootfs"

skip_54="riscv:virt:defconfig:net,virtio-net-device:usb-ohci:rootfs"

patch_defconfig()
{
    local defconfig=$1
    local fixups=${2//:/ }
    local fixup

    echo "CONFIG_PCI_HOST_GENERIC=y" >> ${defconfig}

    # needed for net,tulip tests
    echo "CONFIG_TULIP_MMIO=y" >> ${defconfig}

    # CONFIG_PREEMPT=y and some of the selftests are like cat and dog,
    # only worse.
    if grep -q "CONFIG_PREEMPT=y" "${defconfig}"; then
	echo "CONFIG_LOCK_TORTURE_TEST=n" >> ${defconfig}
	echo "CONFIG_RCU_TORTURE_TEST=n" >> ${defconfig}
	echo "CONFIG_WW_MUTEX_SELFTEST=n" >> ${defconfig}
    fi
}

cached_config=""

if [[ ${linux_version_code} -ge $(kernel_version 5 4) ]]; then
    # tulip doesn't instantiate prior to v5.4
    tulip_netdev="tulip"
else
    tulip_netdev="e1000"
fi

runkernel()
{
    local mach=$1
    local defconfig=$2
    local fixup=$3
    local rootfs=$4
    local waitlist=("Power down" "Boot successful" "Requesting system poweroff")
    local build="${ARCH}:${mach}:${defconfig}${fixup:+:${fixup}}"

    if [[ "${rootfs}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":rootfs"
    fi

    if ! match_params "${_mach}@${mach}" "${_fixup}@${fixup}"; then
	echo "Skipping ${build} ... "
	return 0
    fi

    echo -n "Building ${build} ... "

    if ! checkskip "${build}" ; then
	return 0
    fi

    if ! dosetup -c "${defconfig}" -F "${fixup}" "${rootfs}" "${defconfig}"; then
	if [[ __dosetup_rc -eq 2 ]]; then
	    return 0
	fi
	return 1
    fi

    if [[ ${linux_version_code} -ge $(kernel_version 5 4) ]]; then
	BIOS="default"
	KERNEL="arch/riscv/boot/Image"
    else
	# In v4.19, we need to use bbl to boot the image, and we need
	# to use qemu v4.0 (later versions will report a region overlap).
	QEMU="${QEMU_V40}"
	BIOS="${progdir}/bbl"
	KERNEL="vmlinux"
    fi

    case "${mach}" in
    virt)
	con="console=ttyS0,115200 earlycon=uart8250,mmio,0x10000000,115200"
	wait="automatic"
	;;
    sifive_u)
	# requires qemu v6.0+
	con="console=ttySIF0,115200 earlycon"
	wait="manual"
	;;
    esac

    execute "${wait}" waitlist[@] \
      ${QEMU} -M "${mach}" -m 512M -no-reboot \
	-bios "${BIOS}" \
	-kernel "${KERNEL}" \
	${extra_params} \
	-append "${initcli} ${con}" \
	-nographic -monitor none

    return $?
}

echo "Build reference: $(git describe)"
echo

# Failed network tests:
#   ne2k_pci: No io resource
#	Driver problem: The io resource starts with 0,
#	and the drivers assume that this means 'no resource'
#	After fixing that, ne2k_pci crashes in outsl (probably
#	a bug in the riscv architecture code).

retcode=0
runkernel virt defconfig "net,e1000" rootfs.cpio
retcode=$((retcode + $?))
runkernel virt defconfig net,e1000e:virtio-blk rootfs.ext2
retcode=$((retcode + $?))
runkernel virt defconfig net,i82801:virtio rootfs.ext2
retcode=$((retcode + $?))
runkernel virt defconfig net,i82550:virtio-pci rootfs.ext2
retcode=$((retcode + $?))
runkernel virt defconfig net,e1000-82544gc:sdhci:mmc rootfs.ext2
retcode=$((retcode + $?))
runkernel virt defconfig net,usb-ohci:nvme rootfs.ext2
retcode=$((retcode + $?))

runkernel virt defconfig net,virtio-net-device:usb-ohci rootfs.ext2
retcode=$((${retcode} + $?))

runkernel virt defconfig net,i82557b:usb-ehci rootfs.ext2
retcode=$((${retcode} + $?))
runkernel virt defconfig pci-bridge:net,virtio-net-pci:usb-xhci rootfs.ext2
retcode=$((${retcode} + $?))
runkernel virt defconfig net,i82557a:usb-uas-ehci rootfs.ext2
retcode=$((${retcode} + $?))
runkernel virt defconfig net,i82558a:usb-uas-xhci rootfs.ext2
retcode=$((${retcode} + $?))
runkernel virt defconfig "net,i82559a:scsi[53C810]" rootfs.ext2
retcode=$((${retcode} + $?))
runkernel virt defconfig "net,i82559er:scsi[53C895A]" rootfs.ext2
retcode=$((${retcode} + $?))

if [[ ${runall} -ne 0 ]]; then
    # Does not instantiate (am53c974 0000:01:01.0: pci I/O map failed)
    runkernel virt defconfig "scsi[AM53C974]" rootfs.ext2
    retcode=$((${retcode} + $?))
    runkernel virt defconfig "scsi[DC395]" rootfs.ext2
    retcode=$((${retcode} + $?))
fi

runkernel virt defconfig "net,rtl8139:scsi[MEGASAS]" rootfs.ext2
retcode=$((${retcode} + $?))
runkernel virt defconfig "net,i82562:scsi[MEGASAS2]" rootfs.ext2
retcode=$((${retcode} + $?))
runkernel virt defconfig "pci-bridge:net,pcnet:scsi[FUSION]" rootfs.ext2
retcode=$((${retcode} + $?))
runkernel virt defconfig "net,${tulip_netdev}:scsi[virtio]" rootfs.ext2
retcode=$((${retcode} + $?))
runkernel virt defconfig "net,i82558b:scsi[virtio-pci]" rootfs.ext2
retcode=$((${retcode} + $?))

runkernel sifive_u defconfig "net,default" rootfs.cpio
retcode=$((${retcode} + $?))
runkernel sifive_u defconfig "sd:net,default" rootfs.ext2
retcode=$((${retcode} + $?))
# does not work; mtd device not created
# runkernel sifive_u defconfig mtd32 rootfs.ext2
# retcode=$((${retcode} + $?))

exit ${retcode}
