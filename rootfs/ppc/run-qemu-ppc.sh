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
_rootfs=$4

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-ppc}

# machine specific information

PREFIX=powerpc64-linux-

PATH_PPC="/opt/kernel/${DEFAULT_CC}/powerpc64-linux/bin"

ARCH=powerpc

PATH=${PATH_PPC}:${PATH}

skip_419="ppce500:corenet32_smp_defconfig:e500:net=eTSEC:sdhci-mmc:ext2"
skip_54="ppce500:corenet32_smp_defconfig:e500:net=eTSEC:sdhci-mmc:ext2"

patch_defconfig()
{
    local defconfig=$1
    local fixups=${2//:/ }
    local fixup

    # Thanks to enforced -Wmissing-prototypes in v6.8+
    disable_config ${defconfig} CONFIG_WERROR
    disable_config ${defconfig} CONFIG_PPC_WERROR
    enable_config ${defconfig} CONFIG_PPC_DISABLE_WERROR

    for fixup in ${fixups}; do
	case "${fixup}" in
	"fstest")
	    # minix fails to mount
	    # f2fs crashes
	    enable_config ${defconfig} CONFIG_EROFS_FS CONFIG_EROFS_FS_ZIP
	    enable_config ${defconfig} CONFIG_EXFAT_FS
	    enable_config ${defconfig} CONFIG_GFS2_FS
	    enable_config ${defconfig} CONFIG_HFS_FS
	    enable_config ${defconfig} CONFIG_HFSPLUS_FS
	    enable_config ${defconfig} CONFIG_JFS_FS
	    enable_config ${defconfig} CONFIG_NILFS2_FS
	    enable_config ${defconfig} CONFIG_XFS_FS
	    enable_config ${defconfig} CONFIG_BCACHEFS_FS
	    # enable for testing
	    enable_config ${defconfig} CONFIG_F2FS_FS
	    enable_config ${defconfig} CONFIG_MINIX_FS
	    ;;
	"e500")
	    enable_config ${defconfig} CONFIG_PPC_QEMU_E500
	    ;;
	"zilog")
	    enable_config "${defconfig}" CONFIG_SERIAL_PMACZILOG CONFIG_SERIAL_PMACZILOG_CONSOLE
	    enable_config "${defconfig}" CONFIG_SERIAL_PMACZILOG_TTYS
	    ;;
	*)
	    ;;
	esac
    done
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
    local build="${defconfig}:${fixup%::*}"

    if [[ "${rootfs}" == *cpio ]]; then
	rbuild+=":initrd"
    else
	rbuild+=":${rootfs##*.}"
    fi

    rbuild="${rbuild//+(:)/:}"

    local pbuild="ppc:${rbuild}"

    if ! match_params "${machine}@${mach}" "${variant}@${fixup}" "${config}@${defconfig}" "${_rootfs}@${rootfs}"; then
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
	earlycon="earlycon=uart8250,mmio,0x4ef600300,115200n8"
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

echo "Build reference: $(git describe --match 'v*')"
echo

# Multi-core boot for mpc8544ds has been broken at least since upstream
# commit 56f1ba280719 ("powerpc/mpc85xx: refactor the PM operations"),
# which mandates a 'compatible' device ID for 'guts' which is not provided
# by qemu. As result, the kernel crashes in mpc85xx_freeze_time_base()
# because the 'guts' pointer is not initialized. Even with that fixed,
# multi-core boots fail (stall) for mpc8544ds, but that maye be a qemu issue.
#
# Note: The guts problem was fixed with linux kernel upstream commit
# 3c2172c1c47b4 ("powerpc/85xx: Fix oops when mpc85xx_smp_guts_ids node
# cannot be found").
#
# net=e1000e and net,igb (qemu v8.0+) instantiate but do not work
# net=sungem does not instantiate
# net=usb-uhci does not instantiate
retcode=0
runkernel mpc85xx_defconfig "::net=e1000" mpc8544ds "" ttyS0 rootfs.cpio arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
runkernel mpc85xx_defconfig "::scsi[53C895A]:net=ne2k_pci" mpc8544ds "" ttyS0 rootfs.btrfs arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
runkernel mpc85xx_defconfig "::sata-sii3112:net=rtl8139" mpc8544ds "" ttyS0 rootfs.ext2 arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
runkernel mpc85xx_defconfig ::sdhci-mmc:net=usb-ohci mpc8544ds "" ttyS0 rootfs.ext2 arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))

if [[ ${runall} -ne 0 ]]; then
    # nvme nvme0: I/O 23 QID 0 timeout, completion polled
    # NVME interrupts (or more generally PCI interrupts) are not received by host OS
    runkernel mpc85xx_defconfig "::nvme" mpc8544ds "" ttyS0 rootfs.ext2 arch/powerpc/boot/uImage
    retcode=$((${retcode} + $?))
fi

if [[ ${runall} -ne 0 ]]; then
    # Run all file system tests, even those known to fail
    runkernel mpc85xx_smp_defconfig "fstest::sdhci-mmc:net=e1000" mpc8544ds "" ttyS0 rootfs.ext2 arch/powerpc/boot/uImage
    retcode=$((${retcode} + $?))
    runkernel mpc85xx_smp_defconfig "fstest::sdhci-mmc:net=e1000" mpc8544ds "" ttyS0 rootfs.btrfs arch/powerpc/boot/uImage
    retcode=$((${retcode} + $?))
    runkernel mpc85xx_smp_defconfig "fstest::sdhci-mmc:net=e1000" mpc8544ds "" ttyS0 rootfs.f2fs arch/powerpc/boot/uImage
    retcode=$((${retcode} + $?))
    runkernel mpc85xx_smp_defconfig "fstest::sdhci-mmc:net=e1000" mpc8544ds "" ttyS0 rootfs.erofs arch/powerpc/boot/uImage
    retcode=$((${retcode} + $?))
    runkernel mpc85xx_smp_defconfig "fstest::sdhci-mmc:net=e1000:fstest=exfat" mpc8544ds "" ttyS0 rootfs.ext2 arch/powerpc/boot/uImage
    retcode=$((${retcode} + $?))
    runkernel mpc85xx_smp_defconfig "fstest::sdhci-mmc:net=e1000:fstest=hfs" mpc8544ds "" ttyS0 rootfs.ext2 arch/powerpc/boot/uImage
    retcode=$((${retcode} + $?))
    runkernel mpc85xx_smp_defconfig "fstest::sdhci-mmc:net=e1000:fstest=hfs+" mpc8544ds "" ttyS0 rootfs.ext2 arch/powerpc/boot/uImage
    retcode=$((${retcode} + $?))
    runkernel mpc85xx_smp_defconfig "fstest::sdhci-mmc:net=e1000:fstest=gfs2" mpc8544ds "" ttyS0 rootfs.ext2 arch/powerpc/boot/uImage
    retcode=$((${retcode} + $?))
    runkernel mpc85xx_smp_defconfig "fstest::sdhci-mmc:net=e1000:fstest=jfs" mpc8544ds "" ttyS0 rootfs.ext2 arch/powerpc/boot/uImage
    retcode=$((${retcode} + $?))
    runkernel mpc85xx_smp_defconfig "fstest::sdhci-mmc:net=e1000:fstest=minix" mpc8544ds "" ttyS0 rootfs.ext2 arch/powerpc/boot/uImage
    retcode=$((${retcode} + $?))
    runkernel mpc85xx_smp_defconfig "fstest::sdhci-mmc:net=e1000:fstest=nilfs2" mpc8544ds "" ttyS0 rootfs.ext2 arch/powerpc/boot/uImage
    retcode=$((${retcode} + $?))
    runkernel mpc85xx_smp_defconfig "fstest::sdhci-mmc:net=e1000:fstest=xfs" mpc8544ds "" ttyS0 rootfs.ext2 arch/powerpc/boot/uImage
    retcode=$((${retcode} + $?))
fi

if [[ ${runall} -ne 0 ]]; then
    # timeout, no error message
    runkernel mpc85xx_smp_defconfig ::scsi[MEGASAS2] mpc8544ds "" ttyS0 rootfs.ext2 arch/powerpc/boot/uImage
    retcode=$((${retcode} + $?))
fi

runkernel mpc85xx_smp_defconfig "::net=e1000" mpc8544ds "" ttyS0 rootfs.cpio arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
runkernel mpc85xx_smp_defconfig "::scsi[DC395]:net=i82550" mpc8544ds "" ttyS0 rootfs.ext2 arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
runkernel mpc85xx_smp_defconfig "::scsi[53C895A]:net=usb-ohci" mpc8544ds "" ttyS0 rootfs.btrfs arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))
runkernel mpc85xx_smp_defconfig "::sata-sii3112:net=ne2k_pci" mpc8544ds "" ttyS0 rootfs.ext2 arch/powerpc/boot/uImage
retcode=$((${retcode} + $?))

runkernel 44x/bamboo_defconfig "::net=pcnet" bamboo "" ttyS0 rootfs.cpio vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/bamboo_defconfig "::scsi[AM53C974]:net=e1000" bamboo "" ttyS0 rootfs.ext2 vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/bamboo_defconfig "smp::net=tulip" bamboo "" ttyS0 rootfs.cpio vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/bamboo_defconfig "smp::scsi[DC395]:net=e1000" bamboo "" ttyS0 rootfs.ext2 vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/bamboo_defconfig "smp::scsi[AM53C974]:net=usb-ohci" bamboo "" ttyS0 rootfs.btrfs vmlinux
retcode=$((${retcode} + $?))
if [[ ${runall} -ne 0 ]]; then
    # megaraid_sas 0000:00:02.0: Command pool empty!
    # Unable to handle kernel paging request for data at address 0x00000000
    # Faulting instruction address: 0xc024a5c8
    # Oops: Kernel access of bad area, sig: 11 [#1]
    # NIP [c024a5c8] megasas_issue_init_mfi+0x20/0x138
    runkernel 44x/bamboo_defconfig "smp::scsi[MEGASAS]" bamboo "" ttyS0 rootfs.ext2 vmlinux
    retcode=$((${retcode} + $?))
fi
runkernel 44x/bamboo_defconfig "smp::scsi[FUSION]:net=e1000" bamboo "" ttyS0 rootfs.btrfs vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/bamboo_defconfig "smp::sdhci-mmc:net=ne2k_pci" bamboo "" ttyS0 rootfs.cramfs vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/bamboo_defconfig "smp::nvme:net=pcnet" bamboo "" ttyS0 rootfs.ext2 vmlinux
retcode=$((${retcode} + $?))

runkernel 44x/canyonlands_defconfig "::net=tulip" \
	sam460ex "" ttyS0 rootfs.cpio vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/canyonlands_defconfig "::usb:net=e1000" \
	sam460ex "" ttyS0 rootfs.ext2 vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/canyonlands_defconfig "::sdhci-mmc:net=e1000e" \
	sam460ex "" ttyS0 rootfs.cramfs vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/canyonlands_defconfig "::nvme:net=ne2k_pci" \
	sam460ex "" ttyS0 rootfs.ext2 vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/canyonlands_defconfig "::scsi[53C895A]:net=usb-ohci" \
	sam460ex "" ttyS0 rootfs.ext2 vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/canyonlands_defconfig "::scsi[AM53C974]:net=rtl8139" \
	sam460ex "" ttyS0 rootfs.btrfs vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/canyonlands_defconfig "::scsi[DC395]:net=i82559a" \
	sam460ex "" ttyS0 rootfs.ext2 vmlinux
retcode=$((${retcode} + $?))
runkernel 44x/canyonlands_defconfig "::scsi[FUSION]:net=pcnet" \
	sam460ex "" ttyS0 rootfs.ext2 vmlinux
retcode=$((${retcode} + $?))

if [[ ${runall} -ne 0 ]]; then
    # megaraid_sas 0002:00:02.0: Command pool empty!
    # Unable to handle kernel paging request for data at address 0x00000000
    runkernel 44x/canyonlands_defconfig ::scsi[MEGASAS] sam460ex "" ttyS0 rootfs.ext2 vmlinux
    retcode=$((${retcode} + $?))
    runkernel 44x/canyonlands_defconfig ::scsi[MEGASAS2] sam460ex "" ttyS0 rootfs.ext2 vmlinux
    retcode=$((${retcode} + $?))
fi

# Machine "mac99,via=pmu" works but does not auto-reboot
runkernel pmac32_defconfig zilog:smp::ide:net=e1000 mac99 G4 ttyS0 rootfs.ext2 vmlinux
retcode=$((${retcode} + $?))


runkernel pmac32_defconfig zilog::ide:net=virtio-net-pci g3beige G3 ttyS0 rootfs.ext2 vmlinux
retcode=$((${retcode} + $?))
runkernel pmac32_defconfig zilog::ide:net=default g3beige G3 ttyS0 rootfs.btrfs vmlinux
retcode=$((${retcode} + $?))

runkernel pmac32_defconfig zilog::ide:net=default mac99 G4 ttyS0 rootfs.ext2 vmlinux
retcode=$((${retcode} + $?))
runkernel pmac32_defconfig zilog::net=e1000 mac99 "" ttyS0 rootfs.cpio vmlinux
retcode=$((${retcode} + $?))
runkernel pmac32_defconfig zilog::ide:net=usb-ohci mac99 "" ttyS0 rootfs.ext2 vmlinux
retcode=$((${retcode} + $?))
runkernel pmac32_defconfig zilog::usb:net=i82562 mac99 "" ttyS0 rootfs.ext2 vmlinux
retcode=$((${retcode} + $?))
runkernel pmac32_defconfig zilog::sdhci-mmc:net=ne2k_pci mac99 "" ttyS0 rootfs.ext2 vmlinux
retcode=$((${retcode} + $?))
runkernel pmac32_defconfig zilog::nvme:net=pcnet mac99 "" ttyS0 rootfs.ext2 vmlinux
retcode=$((${retcode} + $?))
runkernel pmac32_defconfig zilog::scsi[DC395]:net=tulip mac99 "" ttyS0 rootfs.ext2 vmlinux
retcode=$((${retcode} + $?))

runkernel corenet32_smp_defconfig e500::net=rtl8139 ppce500 e500mc ttyS0 \
	rootfs.cpio arch/powerpc/boot/uImage
retcode=$((retcode + $?))
runkernel corenet32_smp_defconfig e500::net=virtio-net:nvme ppce500 e500mc ttyS0 \
	rootfs.btrfs arch/powerpc/boot/uImage
retcode=$((retcode + $?))
runkernel corenet32_smp_defconfig e500::net=eTSEC:sdhci-mmc ppce500 e500mc ttyS0 \
	rootfs.ext2 arch/powerpc/boot/uImage
retcode=$((retcode + $?))
# requires qemu v8.0+ (Freescale eSDHC controller enabled)
runkernel corenet32_smp_defconfig e500::net=e1000:mmc ppce500 e500mc ttyS0 \
	rootfs.cramfs arch/powerpc/boot/uImage
retcode=$((retcode + $?))
if [[ ${runall} -ne 0 ]]; then
    # Fails to mount flash (mtdblock0)
    runkernel corenet32_smp_defconfig e500::net=e1000:flash64 ppce500 e500mc ttyS0 \
	rootfs.ext2 arch/powerpc/boot/uImage
    retcode=$((retcode + $?))
fi
runkernel corenet32_smp_defconfig e500::net=tulip:scsi[53C895A] ppce500 e500mc ttyS0 \
	rootfs.ext2 arch/powerpc/boot/uImage
retcode=$((retcode + $?))
runkernel corenet32_smp_defconfig e500::net=i82562:sata-sii3112 ppce500 e500mc ttyS0 \
	rootfs.ext2 arch/powerpc/boot/uImage
retcode=$((retcode + $?))

exit ${retcode}
