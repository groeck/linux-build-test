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

# gcc 9.3.0 causes a crash for powernv targets
# gcc 11.2.0 fails to compile powernv_defconfig
# gcc 11.3.0 fails to compile corenet64_smp_defconfig
# PATH_PPC="/opt/kernel/powerpc64/gcc-7.4.0/bin"
# PATH_PPC="/opt/kernel/gcc-11.2.0-2.36.1-nolibc/powerpc64-linux/bin"
PATH_PPC="/opt/kernel/${DEFAULT_CC}/powerpc64-linux/bin"

PATH=${PATH_PPC}:${PATH}
dir=$(cd $(dirname $0); pwd)

skip_414="ppce500:corenet64_smp_defconfig:e5500:net,eTSEC:sdhci:mmc:rootfs"
skip_419="ppce500:corenet64_smp_defconfig:e5500:net,eTSEC:sdhci:mmc:rootfs"
skip_54="ppce500:corenet64_smp_defconfig:e5500:net,eTSEC:sdhci:mmc:rootfs"

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

	if [ "${fixup}" = "big" ]; then
	    echo "CONFIG_CPU_LITTLE_ENDIAN=n" >> ${defconfig}
	    echo "CONFIG_CPU_BIG_ENDIAN=y" >> ${defconfig}
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

    mem=1G

    case "${machine}" in
    "powernv")
	mem=2G
	pcibus_set_root "pcie" 0
	;;
    *)
	;;
    esac

    if ! dosetup -c "${defconfig}${fixup%::*}}" -F "${fixup:-fixup}" "${rootfs}" "${defconfig}"; then
	if [[ __dosetup_rc -eq 2 ]]; then
	    return 0
	fi
	return 1
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

echo "Build reference: $(git describe --match 'v*')"
echo

# Notes:
#   pseries:ne2k_pci on pseries (big endian) results in
#	NETDEV WATCHDOG: eth0 (ne2k-pci): transmit queue 0 timed out
#     ne2k_pci with pseries:little is ok.
#   e5500 network failures:
#     pcnet
#     ne2k_pci
#       Both don't instantiate as 1st PCI device, but do instantiate as 2nd
#       (even behind a PCI bridge)
#
runkernel qemu_ppc64_book3s_defconfig smp::net,ne2k_pci mac99 ppc64 ttyS0 vmlinux \
	rootfs.cpio.gz manual
retcode=$?
checkstate ${retcode}
runkernel qemu_ppc64_book3s_defconfig smp::net,pcnet:ide mac99 ppc64 ttyS0 vmlinux \
	rootfs.ext2.gz manual
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel qemu_ppc64_book3s_defconfig smp::net,e1000:sdhci:mmc mac99 ppc64 ttyS0 vmlinux \
	rootfs.ext2.gz manual
retcode=$((retcode + $?))
checkstate ${retcode}
# Upstream qemu generates a traceback during reboot.
# irq 30: nobody cared (try booting with the "irqpoll" option)
runkernel qemu_ppc64_book3s_defconfig smp::net,e1000e:nvme mac99 ppc64 ttyS0 vmlinux \
	rootfs.ext2.gz manual
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel qemu_ppc64_book3s_defconfig smp::net,virtio-net:scsi[DC395] mac99 ppc64 ttyS0 vmlinux \
	rootfs.ext2.gz manual
retcode=$((retcode + $?))
checkstate ${retcode}

runkernel pseries_defconfig big::smp2:net,pcnet pseries POWER8 hvc0 vmlinux \
	rootfs.cpio.gz auto
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel pseries_defconfig big::net,rtl8139:scsi pseries POWER9 hvc0 vmlinux \
	rootfs.ext2.gz auto
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel pseries_defconfig big::net,e1000e:usb pseries POWER9 hvc0 vmlinux \
	rootfs.ext2.gz auto
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel pseries_defconfig big::net,i82559a:sdhci:mmc pseries POWER9 hvc0 vmlinux \
	rootfs.ext2.gz auto
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel pseries_defconfig big::net,virtio-net-old:nvme pseries POWER9 hvc0 vmlinux \
	rootfs.ext2.gz auto
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel pseries_defconfig big::net,tulip:sata-sii3112 pseries POWER9 hvc0 vmlinux \
	rootfs.ext2.gz auto
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel pseries_defconfig big::net,e1000:virtio-pci pseries POWER9 hvc0 vmlinux \
	rootfs.ext2.gz auto
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel pseries_defconfig big::net,e1000:virtio-pci-old pseries POWER9 hvc0 vmlinux \
	rootfs.ext2.gz auto
retcode=$((retcode + $?))
checkstate ${retcode}

# Multi-core boot with little endian images is unstable and may either hang
# or take forever.
runkernel pseries_defconfig little::net,rtl8139 pseries POWER9 hvc0 vmlinux \
	rootfs-el.cpio.gz auto
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel pseries_defconfig little::net,e1000:scsi pseries POWER8 hvc0 vmlinux \
	rootfs-el.ext2.gz auto
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel pseries_defconfig little::net,pcnet:usb pseries POWER8 hvc0 vmlinux \
	rootfs-el.ext2.gz auto
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel pseries_defconfig little::net,e1000e:sata-sii3112 pseries POWER8 hvc0 vmlinux \
	rootfs-el.ext2.gz auto
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel pseries_defconfig little::net,virtio-net:scsi[MEGASAS] pseries POWER8 hvc0 vmlinux \
	rootfs-el.ext2.gz auto
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel pseries_defconfig little::net,virtio-net-old:scsi[MEGASAS] pseries POWER8 hvc0 vmlinux \
	rootfs-el.ext2.gz auto
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel pseries_defconfig little::net,i82562:scsi[FUSION] pseries POWER8 hvc0 vmlinux \
	rootfs-el.ext2.gz auto
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel pseries_defconfig little::net,ne2k_pci:sdhci:mmc pseries POWER8 hvc0 vmlinux \
	rootfs-el.ext2.gz auto
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel pseries_defconfig little::net,usb-ohci:nvme pseries POWER8 hvc0 vmlinux \
	rootfs-el.ext2.gz auto
retcode=$((retcode + $?))
checkstate ${retcode}

runkernel corenet64_smp_defconfig e5500::net,rtl8139 ppce500 e5500 ttyS0 \
	arch/powerpc/boot/uImage rootfs.cpio.gz auto
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel corenet64_smp_defconfig e5500::net,virtio-net:nvme ppce500 e5500 ttyS0 \
	arch/powerpc/boot/uImage rootfs.ext2.gz auto
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel corenet64_smp_defconfig e5500::net,eTSEC:sdhci:mmc ppce500 e5500 ttyS0 \
	arch/powerpc/boot/uImage rootfs.ext2.gz auto
retcode=$((retcode + $?))
checkstate ${retcode}
# requires qemu v8.0+ (Freescale eSDHC controller enabled)
runkernel corenet64_smp_defconfig e5500::net,e1000:mmc ppce500 e5500 ttyS0 \
	arch/powerpc/boot/uImage rootfs.ext2.gz auto
if [[ ${runall} -ne 0 ]]; then
    # Fails to mount flash (mtdblock0)
    retcode=$((retcode + $?))
    checkstate ${retcode}
    runkernel corenet64_smp_defconfig e5500::net,e1000:flash64 ppce500 e5500 ttyS0 \
	arch/powerpc/boot/uImage rootfs.ext2.gz auto
    retcode=$((retcode + $?))
fi
runkernel corenet64_smp_defconfig e5500::net,tulip:scsi[53C895A] ppce500 e5500 ttyS0 \
	arch/powerpc/boot/uImage rootfs.ext2.gz auto
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel corenet64_smp_defconfig e5500::net,i82562:sata-sii3112 ppce500 e5500 ttyS0 \
	arch/powerpc/boot/uImage rootfs.ext2.gz auto
retcode=$((retcode + $?))
checkstate ${retcode}

#   powernv network failures:
#       e1000: crashes
#       pcnet: No IO resources
#       tulip: Missing IO region
#       ne2k_pci: no IO resource
#       virtio-net: ?
#       i82551: ip: SIOCSIFFLAGS: No such file or directory
#
runkernel powernv_defconfig "::net,rtl8139" powernv POWER9 hvc0 \
	arch/powerpc/boot/zImage.epapr rootfs-el.cpio.gz manual
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel powernv_defconfig "::smp2:nvme:net,i82559a" powernv POWER9 hvc0 \
	arch/powerpc/boot/zImage.epapr rootfs-el.ext2.gz manual
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel powernv_defconfig "::usb-xhci:net,i82562" powernv POWER9 hvc0 \
	arch/powerpc/boot/zImage.epapr rootfs-el.ext2.gz manual
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel powernv_defconfig "::scsi[MEGASAS]:net,i82557a" powernv POWER9 hvc0 \
	arch/powerpc/boot/zImage.epapr rootfs-el.ext2.gz manual
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel powernv_defconfig "::smp2:sdhci:mmc:net,i82801" powernv POWER9 hvc0 \
	arch/powerpc/boot/zImage.epapr rootfs-el.ext2.gz manual
retcode=$((retcode + $?))
checkstate ${retcode}

runkernel powernv_defconfig "::mtd32:net,rtl8139" powernv POWER9 hvc0 \
	arch/powerpc/boot/zImage.epapr rootfs-el.ext2.gz manual
retcode=$((retcode + $?))
checkstate ${retcode}

exit ${retcode}
