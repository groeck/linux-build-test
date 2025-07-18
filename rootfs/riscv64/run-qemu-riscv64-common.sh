#!/bin/bash

progdir=$(cd $(dirname "$0"); pwd)
. "${progdir}/../scripts/config.sh"
. "${progdir}/../scripts/common.sh"

parse_args "$@"
shift $((OPTIND - 1))

_mach="$1"
_fixup="$2"

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-riscv64}
PREFIX=riscv64-linux-
ARCH=riscv
PATH_RISCV="/opt/kernel/${DEFAULT_CC}/riscv64-linux/bin"

PATH=${PATH}:${PATH_RISCV}

skip_515="riscv:virt:defconfig:efi:net=e1000:initrd"
skip_61="riscv:virt:defconfig:efi:net=e1000:initrd"
skip_66="riscv:virt:defconfig:efi:net=e1000:initrd"

patch_defconfig()
{
    local defconfig=$1
    local fixups=${2//:/ }
    local fixup

    # The latest kernel assumes SBI version 0.3, but that doesn't match qemu
    # at least up to version 6.2 and results in hangup/crashes during reboot
    # with sifive_u emulations.
    enable_config "${defconfig}" CONFIG_RISCV_SBI_V01

    # Needed for TPM tests
    enable_config "${defconfig}" CONFIG_TCG_TPM CONFIG_TCG_TIS

    enable_config "${defconfig}" CONFIG_PCI_HOST_GENERIC

    # needed for net=tulip tests
    enable_config "${defconfig}" CONFIG_TULIP_MMIO

    enable_config "${defconfig}" CONFIG_MTD CONFIG_MTD_BLOCK CONFIG_MTD_SPI_NOR CONFIG_MTD_CMDLINE_PARTS

    # avoid backtrace warnings
    disable_config "${defconfig}" CONFIG_CGROUP_FREEZER

    # CONFIG_PREEMPT=y and some of the selftests are like cat and dog,
    # only worse.
    if grep -q "CONFIG_PREEMPT=y" "${defconfig}"; then
	disable_config "${defconfig}" CONFIG_LOCK_TORTURE_TEST CONFIG_RCU_TORTURE_TEST
    fi
}

cached_config=""

runkernel()
{
    local mach=$1
    local cpu=$2
    local defconfig=$3
    local fixup=$4
    local rootfs=$5
    local waitlist=("Poweroff" "Boot successful" "Requesting system poweroff")
    local build="${ARCH}:${mach}${cpu:+:${cpu}}:${defconfig}${fixup:+:${fixup}}"

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

    KERNEL="arch/riscv/boot/Image"

    memsize="512M"
    case "${mach}" in
    virt)
	con="console=ttyS0,115200 earlycon=uart8250,mmio,0x10000000,115200"
	wait="automatic"
	extra_params+=" -bios default"
	;;
    sifive_u)
	con="console=ttySIF0,115200 earlycon"
	wait="manual"
	# extra parameter to create mtd partition on first flash.
	if [[ "${fixup}" == *mtd* ]]; then
	    initcli+=" mtdparts=spi0.0:-"
	fi
	extra_params+=" -bios default"
	;;
    microchip-icicle-kit)
	con="console=ttyS1,115200 earlycon"
	wait="manual"
	extra_params+=" -dtb arch/riscv/boot/dts/microchip/mpfs-icicle-kit.dtb"
	extra_params+=" -display none -serial null -serial stdio -smp 5"
	memsize="4G"
	;;
    esac

    if [[ "${wait}" == "manual" ]]; then
	waitlist=("Power down" "Boot successful" "Requesting system poweroff")
    fi

    execute "${wait}" waitlist[@] \
      ${QEMU} -M "${mach}" ${cpu:+-cpu ${cpu}} -m "${memsize}" -no-reboot \
	-kernel "${KERNEL}" \
	${extra_params} \
	-append "${initcli} ${con}" \
	-nographic -monitor none

    return $?
}

build_reference "${PREFIX}gcc" "${QEMU}"

# Failed network tests:
#   ne2k_pci: No io resource
#	Driver problem: The io resource starts with 0,
#	and the drivers assume that this means 'no resource'
#	After fixing that, ne2k_pci crashes in outsl (probably
#	a bug in the riscv architecture code).

__runkernel_common()
{
    local prefix="$1"
    local retcode=0

    runkernel virt "" defconfig "${prefix}net=e1000" rootfs.cpio
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel virt "" defconfig "${prefix}efi:net=e1000" rootfs.cpio
    retcode=$((retcode + $?))
    checkstate ${retcode}
    if [[ "${runall}" -ne 0 ]]; then
	runkernel virt "rv64,zbb=no" defconfig "${prefix}net=ne2k_pci" rootfs.cpio
	retcode=$((retcode + $?))
	checkstate ${retcode}
    fi
    runkernel virt "" defconfig ${prefix}net=e1000e:virtio-blk rootfs.ext2
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel virt "rv64,zbb=no" defconfig ${prefix}net=i82801:virtio rootfs.ext2
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel virt "" defconfig ${prefix}tpm-tis-device:net=i82550:virtio-pci rootfs.ext2
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel virt "rv64,zbb=no" defconfig ${prefix}net=e1000-82544gc:sdhci-mmc rootfs.ext2
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel virt "" defconfig ${prefix}net=usb-ohci:nvme rootfs.ext2
    retcode=$((retcode + $?))
    checkstate ${retcode}
    
    runkernel virt "rv64,zbb=no" defconfig ${prefix}net=virtio-net-device:usb-ohci rootfs.ext2
    retcode=$((retcode + $?))
    checkstate ${retcode}
    
    runkernel virt "" defconfig ${prefix}net=i82557b:usb-ehci rootfs.ext2
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel virt "rv64,zbb=no" defconfig ${prefix}pci-bridge:net=virtio-net-pci:usb-xhci rootfs.ext2
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel virt "" defconfig ${prefix}net=i82557a:usb-uas-ehci rootfs.ext2
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel virt "rv64,zbb=no" defconfig ${prefix}net=i82558a:usb-uas-xhci rootfs.ext2
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel virt "" defconfig "${prefix}net=i82559a:scsi[53C810]" rootfs.ext2
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel virt "rv64,zbb=no" defconfig "${prefix}net=i82559er:scsi[53C895A]" rootfs.ext2
    retcode=$((retcode + $?))
    checkstate ${retcode}
    
    if [[ ${runall} -ne 0 ]]; then
	# Does not instantiate (am53c974 0000:01:01.0: pci I/O map failed)
	runkernel virt "rv64,zbb=no" defconfig "${prefix}scsi[AM53C974]" rootfs.ext2
	retcode=$((retcode + $?))
	runkernel virt "" defconfig "${prefix}scsi[DC395]" rootfs.ext2
	retcode=$((retcode + $?))
    fi
    
    runkernel virt "" defconfig "${prefix}net=rtl8139:scsi[MEGASAS]" rootfs.ext2
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel virt "rv64,zbb=no" defconfig "${prefix}net=i82562:scsi[MEGASAS2]" rootfs.ext2
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel virt "" defconfig "${prefix}pci-bridge:net=pcnet:scsi[FUSION]" rootfs.ext2
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel virt "rv64,zbb=no" defconfig "${prefix}net=tulip:scsi[virtio]" rootfs.ext2
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel virt "" defconfig "${prefix}net=i82558b:scsi[virtio-pci]" rootfs.ext2
    retcode=$((retcode + $?))
    checkstate ${retcode}
    
    runkernel sifive_u "" defconfig "${prefix}net=default" rootfs.cpio
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel sifive_u "" defconfig "${prefix}sd:net=default" rootfs.ext2
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel sifive_u "" defconfig "${prefix}mtd32:net=default" rootfs.ext2
    retcode=$((retcode + $?))
    checkstate ${retcode}
    
    if [[ ${runall} -ne 0 ]]; then
	# Needs qemu v7.0+, generates warning backtraces
	# clk_ahb: Zero divisor and CLK_DIVIDER_ALLOW_ZERO not set
	# clk_rtcref: Zero divisor and CLK_DIVIDER_ALLOW_ZERO not set
	# Ethernet interface fails to instantiate
	# macb 20112000.ethernet eth0: Could not attach PHY (-22)
	runkernel microchip-icicle-kit "" defconfig "${prefix}net=default" rootfs.cpio
	retcode=$((retcode + $?))
	runkernel microchip-icicle-kit "" defconfig "${prefix}sd:net=default" rootfs.ext2
	retcode=$((retcode + $?))
    fi

    return ${retcode}
}
