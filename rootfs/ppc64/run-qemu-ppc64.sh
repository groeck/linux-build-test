#!/bin/bash

shopt -s extglob

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

mach=$1
variant=$2

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-ppc64}

# machine specific information
ARCH=powerpc

PREFIX=powerpc64-linux-

PATH_PPC=/opt/kernel/powerpc64/gcc-7.4.0/bin

PATH=${PATH_PPC}:${PATH}
dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

skip_44="powernv:powernv_defconfig:net,rtl8139:initrd \
	powernv:powernv_defconfig:nvme:rootfs \
	powernv:powernv_defconfig:usb-xhci:rootfs \
	powernv:powernv_defconfig:scsi[MEGASAS]:rootfs \
	powernv:powernv_defconfig:sdhci:mmc:rootfs \
	pseries:pseries_defconfig:net,tulip:sata-sii3112:rootfs \
	pseries:pseries_defconfig:little:net,rtl8139:initrd \
	pseries:pseries_defconfig:little:net,e1000:scsi:rootfs \
	pseries:pseries_defconfig:little:net,e1000e:sata-sii3112:rootfs \
	pseries:pseries_defconfig:little:net,virtio-net:scsi[MEGASAS]:rootfs \
	pseries:pseries_defconfig:little:net,i82562:scsi[FUSION]:rootfs \
	pseries:pseries_defconfig:little:net,ne2k_pci:sdhci:mmc:rootfs \
	pseries:pseries_defconfig:little:net,tulip:nvme:rootfs \
	pseries:pseries_defconfig:little:net,pcnet:usb:rootfs"
skip_49="powernv:powernv_defconfig:net,rtl8139:initrd \
	powernv:powernv_defconfig:sdhci:mmc:rootfs \
	pseries:pseries_defconfig:net,tulip:sata-sii3112:rootfs \
	pseries:pseries_defconfig:little:net,e1000e:sata-sii3112:rootfs"

patch_defconfig()
{
    local defconfig=$1
    local fixups=${2//:/ }
    local fixup

    for fixup in ${fixups}; do
	if [ "${fixup}" = "e5500" ]; then
	    echo "CONFIG_E5500_CPU=y" >> ${defconfig}
	    echo "CONFIG_PPC_QEMU_E500=y" >> ${defconfig}
	fi

	if [ "${fixup}" = "little" ]; then
	    echo "CONFIG_CPU_BIG_ENDIAN=n" >> ${defconfig}
	    echo "CONFIG_CPU_LITTLE_ENDIAN=y" >> ${defconfig}
	fi
    done

    # extra SATA config
    echo "CONFIG_SATA_SIL=y" >> ${defconfig}
}

runkernel()
{
    local defconfig=$1
    local fixup=$2
    local machine=$3
    local cpu=$4
    local console=$5
    local kernel=$6
    local rootfs=$7
    local reboot=$8
    local dt_cmd="${9:+-machine ${9}}"
    local waitlist=("Restarting system" "Restarting" "Boot successful" "Rebooting")
    local build="${machine}:${defconfig}${fixup:+:${fixup}}"

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":rootfs"
    fi
    build="${build//+(:)/:}"

    local msg="ppc64:${build}"

    if ! match_params "${mach}@${machine}" "${variant}@${fixup}"; then
	echo "Skipping ${msg} ... "
	return 0
    fi

    echo -n "Building ${msg} ... "

    if ! checkskip "${build}"; then
	return 0
    fi

    if ! dosetup -c "${defconfig}${fixup%::*}}" -F "${fixup:-fixup}" "${rootfs}" "${defconfig}"; then
	if [[ __dosetup_rc -eq 2 ]]; then
	    return 0
	fi
	return 1
    fi

    mem=1G
    if [[ "${machine}" = "powernv" ]]; then
	mem=2G
    fi

    execute ${reboot} waitlist[@] \
      ${QEMU} -M ${machine} -cpu ${cpu} -m ${mem} \
	-kernel ${kernel} \
	${extra_params} \
	-nographic -vga none -monitor null -no-reboot \
	--append "${initcli} console=tty console=${console}" \
	${dt_cmd}

    return $?
}

echo "Build reference: $(git describe)"
echo

# Notes:
#   pseries:ne2k_pci on pseries (big endian) results in
#	NETDEV WATCHDOG: eth0 (ne2k-pci): transmit queue 0 timed out
#     ne2k_pci with pseries:little is ok.
#   e5500 network failures:
#     rtl8139
#     pcnet
#     ne2k_pci
#   powernv crashes with all non-initrd network tests
#     This is possibly because the network device is connected to the wrong
#     pcie bus.
#
runkernel qemu_ppc64_book3s_defconfig smp::net,ne2k_pci mac99 ppc64 ttyS0 vmlinux \
	rootfs.cpio.gz manual
retcode=$?
runkernel qemu_ppc64_book3s_defconfig smp::net,pcnet:ide mac99 ppc64 ttyS0 vmlinux \
	rootfs.ext2.gz manual
retcode=$((${retcode} + $?))
runkernel qemu_ppc64_book3s_defconfig smp::net,e1000:sdhci:mmc mac99 ppc64 ttyS0 vmlinux \
	rootfs.ext2.gz manual
retcode=$((${retcode} + $?))
# Upstream qemu generates a traceback during reboot.
# irq 30: nobody cared (try booting with the "irqpoll" option)
runkernel qemu_ppc64_book3s_defconfig smp::net,e1000e:nvme mac99 ppc64 ttyS0 vmlinux \
	rootfs.ext2.gz manual
retcode=$((${retcode} + $?))
runkernel qemu_ppc64_book3s_defconfig smp::net,virtio-net:scsi[DC395] mac99 ppc64 ttyS0 vmlinux \
	rootfs.ext2.gz manual
retcode=$((${retcode} + $?))
runkernel pseries_defconfig ::net,pcnet pseries POWER8 hvc0 vmlinux \
	rootfs.cpio.gz auto
retcode=$((${retcode} + $?))
runkernel pseries_defconfig ::net,rtl8139:scsi pseries POWER9 hvc0 vmlinux \
	rootfs.ext2.gz auto
retcode=$((${retcode} + $?))
runkernel pseries_defconfig ::net,e1000e:usb pseries POWER9 hvc0 vmlinux \
	rootfs.ext2.gz auto
retcode=$((${retcode} + $?))
runkernel pseries_defconfig ::net,i82559a:sdhci:mmc pseries POWER9 hvc0 vmlinux \
	rootfs.ext2.gz auto
retcode=$((${retcode} + $?))
runkernel pseries_defconfig ::net,virtio-net:nvme pseries POWER9 hvc0 vmlinux \
	rootfs.ext2.gz auto
retcode=$((${retcode} + $?))
runkernel pseries_defconfig ::net,tulip:sata-sii3112 pseries POWER9 hvc0 vmlinux \
	rootfs.ext2.gz auto
retcode=$((${retcode} + $?))
runkernel pseries_defconfig little::net,rtl8139 pseries POWER9 hvc0 vmlinux \
	rootfs-el.cpio.gz auto
retcode=$((${retcode} + $?))
runkernel pseries_defconfig little::net,e1000:scsi pseries POWER8 hvc0 vmlinux \
	rootfs-el.ext2.gz auto
retcode=$((${retcode} + $?))
runkernel pseries_defconfig little::net,pcnet:usb pseries POWER8 hvc0 vmlinux \
	rootfs-el.ext2.gz auto
retcode=$((${retcode} + $?))
runkernel pseries_defconfig little::net,e1000e:sata-sii3112 pseries POWER8 hvc0 vmlinux \
	rootfs-el.ext2.gz auto
retcode=$((${retcode} + $?))
runkernel pseries_defconfig little::net,virtio-net:scsi[MEGASAS] pseries POWER8 hvc0 vmlinux \
	rootfs-el.ext2.gz auto
retcode=$((${retcode} + $?))
runkernel pseries_defconfig little::net,i82562:scsi[FUSION] pseries POWER8 hvc0 vmlinux \
	rootfs-el.ext2.gz auto
retcode=$((${retcode} + $?))
runkernel pseries_defconfig little::net,ne2k_pci:sdhci:mmc pseries POWER8 hvc0 vmlinux \
	rootfs-el.ext2.gz auto
retcode=$((${retcode} + $?))
runkernel pseries_defconfig little::net,usb-ohci:nvme pseries POWER8 hvc0 vmlinux \
	rootfs-el.ext2.gz auto
retcode=$((${retcode} + $?))

runkernel corenet64_smp_defconfig e5500::net,e1000e ppce500 e5500 ttyS0 \
	arch/powerpc/boot/uImage rootfs.cpio.gz auto
retcode=$((${retcode} + $?))
runkernel corenet64_smp_defconfig e5500::net,virtio-net:nvme ppce500 e5500 ttyS0 \
	arch/powerpc/boot/uImage rootfs.ext2.gz auto
retcode=$((${retcode} + $?))
runkernel corenet64_smp_defconfig e5500::net,e1000:sdhci:mmc ppce500 e5500 ttyS0 \
	arch/powerpc/boot/uImage rootfs.ext2.gz auto
retcode=$((${retcode} + $?))
runkernel corenet64_smp_defconfig e5500::net,tulip:scsi[53C895A] ppce500 e5500 ttyS0 \
	arch/powerpc/boot/uImage rootfs.ext2.gz auto
retcode=$((${retcode} + $?))
runkernel corenet64_smp_defconfig e5500::net,i82562:sata-sii3112 ppce500 e5500 ttyS0 \
	arch/powerpc/boot/uImage rootfs.ext2.gz auto
retcode=$((${retcode} + $?))

runkernel powernv_defconfig "::net,rtl8139" powernv POWER9 hvc0 \
	arch/powerpc/boot/zImage.epapr rootfs-el.cpio.gz manual
retcode=$((${retcode} + $?))
runkernel powernv_defconfig "::nvme" powernv POWER9 hvc0 \
	arch/powerpc/boot/zImage.epapr rootfs-el.ext2.gz manual
retcode=$((${retcode} + $?))
runkernel powernv_defconfig "::usb-xhci" powernv POWER9 hvc0 \
	arch/powerpc/boot/zImage.epapr rootfs-el.ext2.gz manual
retcode=$((${retcode} + $?))
runkernel powernv_defconfig "::scsi[MEGASAS]" powernv POWER9 hvc0 \
	arch/powerpc/boot/zImage.epapr rootfs-el.ext2.gz manual
retcode=$((${retcode} + $?))
runkernel powernv_defconfig "::sdhci:mmc" powernv POWER9 hvc0 \
	arch/powerpc/boot/zImage.epapr rootfs-el.ext2.gz manual
retcode=$((${retcode} + $?))

if [[ ${runall} -ne 0 ]]; then
    # (null): opal_flash_async_op(op=0) failed (rc -1)
    # blk_update_request: I/O error, dev mtdblock0, sector 2 op 0x1:(WRITE) flags 0x800 phys_seg 1 prio class 0
    # blk_update_request: I/O error, dev mtdblock0, sector 2 op 0x1:(WRITE) flags 0x800 phys_seg 1 prio class 0
    # Buffer I/O error on dev mtdblock0, logical block 1, lost sync page write
    # EXT4-fs (mtdblock0): I/O error while writing superblock
    # mount: mounting /dev/root on / failed: I/O error
    runkernel powernv_defconfig "::mtd32" powernv POWER9 hvc0 \
	arch/powerpc/boot/zImage.epapr rootfs-el.ext2.gz manual
    retcode=$((${retcode} + $?))
fi

exit ${retcode}
