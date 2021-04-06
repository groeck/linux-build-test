#!/bin/bash

shopt -s extglob

progdir=$(cd $(dirname $0); pwd)
. ${progdir}/../scripts/config.sh
. ${progdir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

machine=$1
variant=$2
config=$3

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-ppc}

# machine specific information

PREFIX=powerpc64-linux-

rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
PATH_PPC=/opt/kernel/gcc-10.2.0-nolibc/powerpc64-linux/bin

ARCH=powerpc

PATH=${PATH_PPC}:${PATH}

patch_defconfig()
{
    local defconfig=$1
    local fixups=${2//:/ }
    local fixup

    for fixup in ${fixups}; do
	if [ "${fixup}" = "zilog" ]; then
	    echo "CONFIG_SERIAL_PMACZILOG=y" >> ${defconfig}
	    echo "CONFIG_SERIAL_PMACZILOG_TTYS=n" >> ${defconfig}
	    echo "CONFIG_SERIAL_PMACZILOG_CONSOLE=y" >> ${defconfig}
	fi
    done

    # IDE has trouble with atomic sleep.
    if grep -q "CONFIG_IDE=y" "${defconfig}"; then
	echo "CONFIG_DEBUG_ATOMIC_SLEEP=n" >> "${defconfig}"
    fi
}

cached_defconfig=""

runkernel()
{
    local defconfig=$1
    local fixup=$2
    local mach=$3
    local cpu=$4
    local tty=$5
    local rootfs=$6
    local kernel=$7
    local dts=$8
    local dtbcmd=""
    local earlycon=""
    local waitlist=("Restarting" "Boot successful" "Rebooting")
    local rbuild="${mach}:${defconfig}${fixup:+:${fixup}}"
    local build="${defconfig}:${fixup//?(?(:)@(ata*|sata*|scsi*|usb*|sdhci|mmc|nvme|net,*))/}"

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	rbuild+=":initrd"
    else
	rbuild+=":rootfs"
    fi

    local pbuild="ppc:${rbuild}"

    if ! match_params "${machine}@${mach}" "${variant}@${fixup}" "${config}@${defconfig}"; then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    echo -n "Building ${pbuild} ... "

    if ! checkskip "${rbuild}"; then
	return 0
    fi

    if ! dosetup -c "${build}" -F "${fixup}" "${rootfs}" "${defconfig}"; then
	if [[ __dosetup_rc -eq 2 ]]; then
	    return 0
	fi
	return 1
    fi

    if [[ -n "${cpu}" ]]; then
	cpu="-cpu ${cpu}"
    fi

    if [ -n "${dts}" -a -e "${dts}" ]; then
	local dtb="${dts/.dts/.dtb}"
	dtbcmd="-dtb ${dtb}"
	dtc -I dts -O dtb ${dts} -o ${dtb} >/dev/null 2>&1
    fi

    # Needed for "FUSION" boot tests
    initcli+=" coherent_pool=512k"

    case "${mach}" in
    sam460ex)
	# Fails with v4.4.y
	if [[ "${rel}" != "v4.4" ]]; then
	    earlycon="earlycon=uart8250,mmio,0x4ef600300,115200n8"
	fi
	;;
    virtex-ml507)
	# fails with v4.4.y
	if [[ "${rel}" != "v4.4" ]]; then
	    earlycon="earlycon"
	fi
	;;
    *)
	;;
    esac

    execute automatic waitlist[@] \
      ${QEMU} -kernel ${kernel} -M ${mach} -m 256 ${cpu} -no-reboot \
	${extra_params} \
	${dtbcmd} \
	--append "${initcli} ${earlycon} mem=256M console=${tty}" \
	-monitor none -nographic

    return $?
}

echo "Build reference: $(git describe)"
echo

VIRTEX440_DTS=arch/powerpc/boot/dts/virtex440-ml507.dts

runkernel qemu_ppc_book3s_defconfig nosmp:ide:net,default mac99 G4 ttyS0 rootfs.ext2.gz \
	vmlinux
retcode=$?
runkernel qemu_ppc_book3s_defconfig nosmp:ide:net,default g3beige G3 ttyS0 rootfs.ext2.gz \
	vmlinux
retcode=$((${retcode} + $?))
runkernel qemu_ppc_book3s_defconfig smp:ide:net,default mac99 G4 ttyS0 rootfs.ext2.gz \
	vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/virtex5_defconfig "" virtex-ml507 "" ttyS0 rootfs.cpio.gz \
	vmlinux ${VIRTEX440_DTS}
retcode=$((${retcode} + $?))

# net,e1000e instantiates but does not work
# net,sungem does not instantiate
# net,usb-uhci does not instantiate
runkernel mpc85xx_defconfig "net,e1000" mpc8544ds "" ttyS0 rootfs.cpio.gz arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
runkernel mpc85xx_defconfig "scsi[53C895A]:net,ne2k_pci" mpc8544ds "" ttyS0 rootfs.ext2.gz arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
runkernel mpc85xx_defconfig "sata-sii3112:net,rtl8139" mpc8544ds "" ttyS0 rootfs.ext2.gz arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
runkernel mpc85xx_defconfig sdhci:mmc:net,usb-ohci mpc8544ds "" ttyS0 rootfs.ext2.gz arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
if [[ ${runall} -ne 0 ]]; then
    # nvme nvme0: I/O 23 QID 0 timeout, completion polled
    runkernel mpc85xx_defconfig nvme mpc8544ds "" ttyS0 rootfs.ext2.gz arch/powerpc/boot/uImage
    retcode=$((${retcode} + $?))
    # timeout, no error message
    runkernel mpc85xx_smp_defconfig scsi[MEGASAS2] mpc8544ds "" ttyS0 rootfs.ext2.gz arch/powerpc/boot/uImage
    retcode=$((${retcode} + $?))
fi
runkernel mpc85xx_smp_defconfig "net,e1000" mpc8544ds "" ttyS0 rootfs.cpio.gz arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
runkernel mpc85xx_smp_defconfig scsi[DC395]:net,i82550 mpc8544ds "" ttyS0 rootfs.ext2.gz arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
runkernel mpc85xx_smp_defconfig scsi[53C895A]:net,usb-ohci mpc8544ds "" ttyS0 rootfs.ext2.gz arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
runkernel mpc85xx_smp_defconfig sata-sii3112:net,ne2k_pci mpc8544ds "" ttyS0 rootfs.ext2.gz arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))

runkernel 44x/bamboo_defconfig "net,pcnet" bamboo "" ttyS0 rootfs.cpio.gz vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/bamboo_defconfig "scsi[AM53C974]:net,e1000" bamboo "" ttyS0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/bamboo_defconfig "smp:net,tulip" bamboo "" ttyS0 rootfs.cpio.gz vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/bamboo_defconfig "smp:scsi[DC395]:net,e1000" bamboo "" ttyS0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/bamboo_defconfig "smp:scsi[AM53C974]:net,usb-ohci" bamboo "" ttyS0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))
if [[ ${runall} -ne 0 ]]; then
    # megaraid_sas 0000:00:02.0: Command pool empty!
    # Unable to handle kernel paging request for data at address 0x00000000
    # Faulting instruction address: 0xc024a5c8
    # Oops: Kernel access of bad area, sig: 11 [#1]
    # NIP [c024a5c8] megasas_issue_init_mfi+0x20/0x138
    runkernel 44x/bamboo_defconfig "smp:scsi[MEGASAS]" bamboo "" ttyS0 rootfs.ext2.gz vmlinux
    retcode=$((${retcode} + $?))
fi
runkernel 44x/bamboo_defconfig "smp:scsi[FUSION]:net,e1000" bamboo "" ttyS0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/bamboo_defconfig "smp:sdhci:mmc:net,ne2k_pci" bamboo "" ttyS0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/bamboo_defconfig "smp:nvme:net,pcnet" bamboo "" ttyS0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))

# net,tulip passes. Everything else fails with
# "ip: SIOCSIFFLAGS: Cannot assign requested address"

runkernel 44x/canyonlands_defconfig "net,tulip" sam460ex "" ttyS0 rootfs.cpio.gz vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/canyonlands_defconfig usb:net,tulip sam460ex "" ttyS0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/canyonlands_defconfig sdhci:mmc:net,tulip sam460ex "" ttyS0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/canyonlands_defconfig nvme:net,tulip sam460ex "" ttyS0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/canyonlands_defconfig "scsi[53C895A]:net,tulip" sam460ex "" ttyS0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/canyonlands_defconfig scsi[AM53C974]:net,tulip sam460ex "" ttyS0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/canyonlands_defconfig scsi[DC395]:net,tulip sam460ex "" ttyS0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/canyonlands_defconfig scsi[FUSION]:net,tulip sam460ex "" ttyS0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))
if [[ ${runall} -ne 0 ]]; then
    # megaraid_sas 0002:00:02.0: Command pool empty!
    # Unable to handle kernel paging request for data at address 0x00000000
    runkernel 44x/canyonlands_defconfig scsi[MEGASAS] sam460ex "" ttyS0 rootfs.ext2.gz vmlinux
    retcode=$((${retcode} + $?))
    runkernel 44x/canyonlands_defconfig scsi[MEGASAS2] sam460ex "" ttyS0 rootfs.ext2.gz vmlinux
    retcode=$((${retcode} + $?))
fi
runkernel pmac32_defconfig zilog:net,e1000 mac99 "" ttyPZ0 rootfs.cpio.gz vmlinux
retcode=$((${retcode} + $?))
runkernel pmac32_defconfig zilog:ide:net,usb-ohci mac99 "" ttyPZ0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))
runkernel pmac32_defconfig zilog:usb:net,i82562 mac99 "" ttyPZ0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))
runkernel pmac32_defconfig zilog:sdhci:mmc:net,ne2k_pci mac99 "" ttyPZ0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))
runkernel pmac32_defconfig zilog:nvme:net,pcnet mac99 "" ttyPZ0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))
runkernel pmac32_defconfig zilog:scsi[DC395]:net,tulip mac99 "" ttyPZ0 rootfs.ext2.gz vmlinux
retcode=$((${retcode} + $?))

exit ${retcode}
