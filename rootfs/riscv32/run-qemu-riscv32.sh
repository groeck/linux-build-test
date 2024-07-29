#!/bin/bash

progdir=$(cd $(dirname "$0"); pwd)
. "${progdir}/../scripts/config.sh"
. "${progdir}/../scripts/common.sh"

parse_args "$@"
shift $((OPTIND - 1))

_mach="$1"
_fixup="$2"

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-riscv32}
PREFIX=riscv32-linux-
ARCH=riscv
PATH_RISCV="/opt/kernel/${DEFAULT_CC}/riscv32-linux/bin"

PATH=${PATH}:${PATH_RISCV}

patch_defconfig()
{
    local defconfig=$1
    local fixups=${2//:/ }
    local fixup

    echo "CONFIG_PCI_HOST_GENERIC=y" >> ${defconfig}
    echo "CONFIG_CGROUP_FREEZER=n" >> ${defconfig}

    # Needed for TPM tests
    enable_config "${defconfig}" CONFIG_TCG_TPM CONFIG_TCG_TIS

    # CONFIG_PREEMPT=y and some of the selftests are like cat and dog,
    # only worse.
    if grep -q "CONFIG_PREEMPT=y" "${defconfig}"; then
	echo "CONFIG_LOCK_TORTURE_TEST=n" >> ${defconfig}
	echo "CONFIG_RCU_TORTURE_TEST=n" >> ${defconfig}
    fi
}

cached_config=""

runkernel()
{
    local mach=$1
    local cpu=$2
    local defconfig=$3
    local fixup="notests:nofs::$4"
    local rootfs=$5
    local waitlist=("Power down" "Boot successful" "Requesting system poweroff")
    local build="riscv32:${mach}${cpu:+:${cpu}}:${defconfig}${fixup:+:${fixup}}"

    if [[ "${rootfs}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":${rootfs##*.}"
    fi

    if ! match_params "${_mach}@${mach}" "${_fixup}@${fixup}"; then
	echo "Skipping ${build} ... "
	return 0
    fi

    build="${build//+(:)/:}"

    echo -n "Building ${build} ... "

    if ! checkskip "${build}" ; then
	return 0
    fi

    if ! dosetup -c "${defconfig}${fixup%::*}" -F "${fixup}" "${rootfs}" "${defconfig}"; then
	if [[ __dosetup_rc -eq 2 ]]; then
	    return 0
	fi
	return 1
    fi

    case "${mach}" in
    virt)
	con="console=ttyS0,115200 earlycon=uart8250,mmio,0x10000000,115200"
	wait="automatic"
	;;
    sifive_u)
	con="console=ttySIF0,115200 earlycon"
	wait="manual"
	;;
    esac

    execute "${wait}" waitlist[@] \
      ${QEMU} -M "${mach}" ${cpu:+-cpu ${cpu}} -m 512M -no-reboot \
	-bios default \
	-kernel arch/riscv/boot/Image \
	${extra_params} \
	-append "${initcli} ${con}" \
	-nographic -monitor none

    return $?
}

build_reference "${PREFIX}gcc" "${QEMU}"

retcode=0
runkernel virt "" rv32_defconfig "net=e1000" rootfs.cpio
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel virt "rv32,zbb=no" rv32_defconfig net=e1000e:virtio-blk rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel virt "" rv32_defconfig net=i82801:virtio rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel virt "rv32,zbb=no" rv32_defconfig net=i82550:virtio-pci rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel virt "" rv32_defconfig tpm-tis-device:net=e1000-82544gc:sdhci-mmc rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel virt "rv32,zbb=no" rv32_defconfig net=usb-ohci:nvme rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}

runkernel virt "" rv32_defconfig net=virtio-net-device:usb-ohci rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}

runkernel virt "rv32,zbb=no" rv32_defconfig "net=pcnet:usb-ehci" rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel virt "" rv32_defconfig net=virtio-net-pci:usb-xhci rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel virt "rv32,zbb=no" rv32_defconfig net=i82557a:usb-uas-ehci rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel virt "" rv32_defconfig net=i82558a:usb-uas-xhci rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel virt "rv32,zbb=no" rv32_defconfig "pci-bridge:net=i82559a:scsi[53C810]" rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel virt "" rv32_defconfig "net=i82559er:pci-bridge:scsi[53C895A]" rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}

if [[ ${runall} -ne 0 ]]; then
    # Does not instantiate
    runkernel virt "rv32,zbb=no" rv32_defconfig "scsi[AM53C974]" rootfs.ext2
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel virt "" rv32_defconfig "scsi[DC395]" rootfs.ext2
    retcode=$((retcode + $?))
    checkstate ${retcode}
fi

runkernel virt "rv32,zbb=no" rv32_defconfig "net=rtl8139:scsi[MEGASAS]" rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel virt "" rv32_defconfig "pci-bridge:net=i82562:scsi[MEGASAS2]" rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel virt "rv32,zbb=no" rv32_defconfig "pci-bridge:net=e1000:scsi[FUSION]" rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel virt "" rv32_defconfig "net=i82557b:scsi[virtio]" rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel virt "rv32,zbb=no" rv32_defconfig "net=i82557c:scsi[virtio-pci]" rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}

if [[ ${runall} -ne 0 ]]; then
    # Unable to handle kernel paging request at virtual address c0c00000
    # in __memset(), called from free_initmem()
    runkernel sifive_u "" rv32_defconfig "net=default" rootfs.cpio
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel sifive_u "" rv32_defconfig "sd:net=default" rootfs.ext2
    retcode=$((retcode + $?))
    checkstate ${retcode}
fi

exit ${retcode}
