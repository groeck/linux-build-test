#!/bin/bash

progdir=$(cd $(dirname $0); pwd)
. ${progdir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-arm}

machine=$1
config=$2
options=$3
devtree=$4
boot=$5

ARCH=arm

PREFIX="arm-linux-gnueabi-"

PATH_ARM="/opt/kernel/${DEFAULT_CC}/arm-linux-gnueabi/bin"

PATH=${PATH_ARM}:${PATH_ARM_M3}:${PATH}

# selftests sometimes hang (or used to hang) with soft CPU lockup.
# notests="notests"
notests=""

skip_419="arm:quanta-q71l-bmc:aspeed_g4_defconfig:mtd32:net=nic \
	arm:ast2500-evb:aspeed_g5_defconfig:${notests:+notests:}sd:net=nic \
	arm:ast2600-evb:aspeed_g5_defconfig:${notests:+notests:}usb1:net=nic \
	arm:ast2600-evb:aspeed_g5_defconfig:${notests:+notests:}usb-hub1:net=nic \
	arm:ast2600-evb:aspeed_g5_defconfig:${notests:+notests:}usb-hub1,2:net=nic"
skip_54="arm:palmetto-bmc:aspeed_g4_defconfig:mtd32:net=nic \
	arm:quanta-q71l-bmc:aspeed_g4_defconfig:mtd32:net=nic \
	arm:ast2600-evb:aspeed_g5_defconfig:${notests:+notests:}usb1:net=nic \
	arm:ast2600-evb:aspeed_g5_defconfig:${notests:+notests:}usb-hub1:net=nic \
	arm:ast2600-evb:aspeed_g5_defconfig:${notests:+notests:}usb-hub1,2:net=nic \
	arm:ast2600-evb:aspeed_g5_defconfig:${notests:+notests:}sd0,b300:net=nic \
	arm:ast2600-evb:aspeed_g5_defconfig:${notests:+notests:}sd1,b300:net=nic \
	arm:ast2600-evb:aspeed_g5_defconfig:${notests:+notests:}sd2,b300:net=nic \
	arm:ast2600-evb:aspeed_g5_defconfig:${notests:+notests:}mtd64:net=nic \
	arm:ast2600-evb:aspeed_g5_defconfig:${notests:+notests:}mtd64,0,6,1:net=nic"
skip_510="arm:ast2600-evb:aspeed_g5_defconfig:${notests:+notests:}usb1:net=nic \
	arm:ast2600-evb:aspeed_g5_defconfig:${notests:+notests:}usb-hub1:net=nic \
	arm:ast2600-evb:aspeed_g5_defconfig:${notests:+notests:}usb-hub1,2:net=nic \
	arm:ast2600-evb:aspeed_g5_defconfig:${notests:+notests:}sd0,b300:net=nic \
	arm:ast2600-evb:aspeed_g5_defconfig:${notests:+notests:}sd1,b300:net=nic \
	arm:ast2600-evb:aspeed_g5_defconfig:${notests:+notests:}sd2,b300:net=nic \
	arm:ast2600-evb:aspeed_g5_defconfig:${notests:+notests:}mtd64:net=nic \
	arm:ast2600-evb:aspeed_g5_defconfig:${notests:+notests:}mtd64,0,6,1:net=nic \
	arm:rainier-bmc:aspeed_g5_defconfig:${notests:+notests:}usb-hub1:net=nic"
skip_515="arm:ast2600-evb:aspeed_g5_defconfig:${notests:+notests:}mtd64:net=nic \
	arm:ast2600-evb:aspeed_g5_defconfig:${notests:+notests:}mtd64,0,6,1:net=nic \
	arm:ast2600-evb:aspeed_g5_defconfig:${notests:+notests:}sd2,b300:net=nic \
	arm:g220a-bmc:aspeed_g5_defconfig:${notests:+notests:}mtd32,0,12,2:net=nic \
	arm:fuji-bmc:aspeed_g5_defconfig:${notests:+notests:}net=nic \
	arm:fuji-bmc:aspeed_g5_defconfig:${notests:+notests:}sd2:net=nic \
	arm:fuji-bmc:aspeed_g5_defconfig:${notests:+notests:}mem1G:mtd128:net=nic \
	arm:fuji-bmc:aspeed_g5_defconfig:${notests:+notests:}mem1G:mtd128,0,8,1:net=nic \
	arm:fuji-bmc:aspeed_g5_defconfig:${notests:+notests:}usb1:net=nic \
	arm:rainier-bmc:aspeed_g5_defconfig:${notests:+notests:}usb-hub1:net=nic"
skip_61="arm:bletchley-bmc:aspeed_g5_defconfig:${notests:+notests:}mmc:net=nic \
	arm:bletchley-bmc:aspeed_g5_defconfig:${notests:+notests:}usb1:net=nic"

patch_defconfig()
{
    local defconfig=$1
    local fixups=${2//:/ }
    local fixup

    # F2FS filesystem support
    enable_config ${defconfig} CONFIG_F2FS_FS

    # Disable Bluetooth and wireless. We won't ever use or test it.
    disable_config ${defconfig} CONFIG_BT CONFIG_WLAN CONFIG_WIRELESS

    # Options needed to be built into the kernel for device support
    # MMC
    enable_config ${defconfig} CONFIG_MMC_BLOCK
    # PCMCIA
    enable_config ${defconfig} CONFIG_ATA CONFIG_BLK_DEV_SD
    # USB
    enable_config ${defconfig} CONFIG_USB CONFIG_USB_STORAGE CONFIG_USB_OHCI_HCD
    enable_config ${defconfig} CONFIG_USB_UHCI_HCD

    for fixup in ${fixups}; do
	case "${fixup}" in
	fstest)
	    enable_config ${defconfig} CONFIG_EROFS_FS
	    enable_config ${defconfig} CONFIG_EXFAT_FS
	    enable_config ${defconfig} CONFIG_F2FS_FS
	    enable_config ${defconfig} CONFIG_GFS2_FS
	    enable_config ${defconfig} CONFIG_HFS_FS
	    enable_config ${defconfig} CONFIG_HFSPLUS_FS
	    enable_config ${defconfig} CONFIG_JFS_FS
	    enable_config ${defconfig} CONFIG_MINIX_FS
	    enable_config ${defconfig} CONFIG_NILFS2_FS
	    enable_config ${defconfig} CONFIG_XFS_FS
	    enable_config ${defconfig} CONFIG_BCACHEFS_FS
	    ;;
	*)
	    ;;
	esac
    done
}

runkernel()
{
    local defconfig=$1
    local mach=$2
    local bmach="${mach%%,*}"	# basic machine, without machine options
    local cpu=$3
    local rootfs=$4
    local mode=$5
    local fixup=$6
    local dtb=$7
    local ddtb="${dtb%.dtb}"
    local dtbfile=""
    local nonet=0
    local waitlist=("Restarting" "Boot successful" "Rebooting")
    local build="${ARCH}:${bmach}:${defconfig}${fixup:+:${fixup}}"
    local pbuild="${build}${dtb:+:${dtb%.dtb}}"

    local _boot
    if [[ "${rootfs}" == *cpio ]]; then
	pbuild+=":initrd"
	_boot="initrd"
    else
	pbuild+=":${rootfs##*.}"
	_boot="rootfs"
    fi

    pbuild="${pbuild//+(:)/:}"
    build="${build//+(:)/:}"

    if ! match_params "${machine}@${bmach}" "${config}@${defconfig}" "${options}@${fixup}" "${devtree}@${ddtb}" "${boot}@${_boot}"; then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    echo -n "Building ${pbuild} ... "

    if ! checkskip "${build}" ; then
	return 0
    fi

    case "${bmach}" in
    "ast2600-evb")
	# Network tests need v5.11 or later
	# Older kernels only instantiate the second Ethernet interface.
	if [[ ${linux_version_code} -lt $(kernel_version 5 11) ]]; then
	    nonet=1
	fi
	;;
    *)
	;;
    esac
    if [[ "${nonet}" -ne 0 ]]; then
	fixup="$(echo ${fixup} | sed -e 's/:\+net=nic//')"
    fi

    if ! dosetup -F "${fixup}" -c "${defconfig}${fixup%::*}" "${rootfs}" "${defconfig}"; then
	if [[ __dosetup_rc -eq 2 ]]; then
	    return 0
	fi
	return 1
    fi

    # If a dtb file was specified but does not exist, skip the build.
    local dtbcmd=""
    if [[ -n "${dtb}" ]]; then
	dtbfile="$(__findfile "arch/arm/boot/dts" "${dtb}")"
	if [[ -z "${dtbfile}" ]]; then
	    echo "skipped (dtb)"
	    return 0
	fi
	dtbcmd="-dtb ${dtbfile}"
    fi

    rootfs="$(rootfsname ${rootfs})"

    kernel="arch/arm/boot/zImage"
    case "${bmach}" in
    "ast2500-evb" | "palmetto-bmc" | "romulus-bmc" | \
    "witherspoon-bmc" | "g220a-bmc" | \
    "supermicro-x11spi-bmc" | "rainier-bmc" | \
    "quanta-q71l-bmc" | "fp5280g2-bmc" | \
    "qcom-dc-scm-v1-bmc" | "ast2600-evb" | \
    "bletchley-bmc")
	initcli+=" console=ttyS4,115200"
	initcli+=" earlycon=uart8250,mmio32,0x1e784000,115200n8"
	;;
    "fuji-bmc")
	initcli+=" console=ttyS0,115200"
	initcli+=" earlycon=uart8250,mmio32,0x1e783000,115200n8"
	;;
    *)
	;;
    esac

    execute "${mode}" waitlist[@] \
        ${QEMU} -M ${mach} \
	    ${cpu:+-cpu ${cpu}} \
	    -kernel ${kernel} \
	    -no-reboot \
	    ${extra_params} \
	    ${initcli:+--append "${initcli}"} \
	    ${dtbcmd} \
	    -nographic -monitor null -serial stdio

    return $?
}

build_reference "${PREFIX}gcc" "${QEMU}"

flash_model_256=""
flash_model_512=""
if [[ ${linux_version_code} -ge $(kernel_version 6 16) ]]; then
    # Qemu support for Macronix mx25l25635e and similar chips is broken
    # after v6.15 due to changes in upstream chip identification code.
    # See upstream commit 947c86e481a027e ("mtd: spi-nor: macronix:
    # Drop the redundant flash info fields") for details.
    # Select Micron flash chips instead.
    flash_model_256=",fmc-model=n25q256a13,spi-model=n25q256a13"
    flash_model_512=",fmc-model=n25q512a13,spi-model=n25q512a13"
fi

if [ ${runall} -eq 1 ]; then
    # run all file system tests
    # As of v6.4/v6.5/v6.6-rc1, the Ethernet interface driver on ast2500
    # triggers a lockdep warning. This is due to commit 1baf2e50e48f
    # ("drivers/net/ftgmac100: fix DHCP potential failure with systemd")
    # which enables the rtnl lock in a worker which may be canceled from
    # code which holds the rtnl lock, potentially causing a deadlock.
    # Activate not-my-problem field and disable lockdep debugging to avoid
    # warning noise.
    runkernel aspeed_g5_defconfig ast2600-evb "" \
	rootfs-armv7a.btrfs automatic nolockdep:fstest::sd2,b300:net=nic aspeed-ast2600-evb.dtb
    retcode=$((${retcode} + $?))
    runkernel aspeed_g5_defconfig ast2600-evb "" \
	rootfs-armv7a.f2fs automatic nolockdep:fstest::sd2,b300:net=nic aspeed-ast2600-evb.dtb
    retcode=$((${retcode} + $?))
    runkernel aspeed_g5_defconfig ast2600-evb "" \
	rootfs-armv7a.erofs automatic nolockdep:fstest::sd2,b300:net=nic aspeed-ast2600-evb.dtb
    retcode=$((${retcode} + $?))
    runkernel aspeed_g5_defconfig ast2600-evb "" \
	rootfs-armv7a.ext2 automatic nolockdep:fstest::sd2,b300:net=nic:fstest=exfat aspeed-ast2600-evb.dtb
    retcode=$((${retcode} + $?))
    runkernel aspeed_g5_defconfig ast2600-evb "" \
	rootfs-armv7a.ext2 automatic nolockdep:fstest::sd2,b300:net=nic:fstest=gfs2 aspeed-ast2600-evb.dtb
    retcode=$((${retcode} + $?))
    runkernel aspeed_g5_defconfig ast2600-evb "" \
	rootfs-armv7a.ext2 automatic nolockdep:fstest::sd2,b300:net=nic:fstest=hfs aspeed-ast2600-evb.dtb
    retcode=$((${retcode} + $?))
    runkernel aspeed_g5_defconfig ast2600-evb "" \
	rootfs-armv7a.ext2 automatic nolockdep:fstest::sd2,b300:net=nic:fstest=hfs+ aspeed-ast2600-evb.dtb
    retcode=$((${retcode} + $?))
    runkernel aspeed_g5_defconfig ast2600-evb "" \
	rootfs-armv7a.ext2 automatic nolockdep:fstest::sd2,b300:net=nic:fstest=jfs aspeed-ast2600-evb.dtb
    retcode=$((${retcode} + $?))
    runkernel aspeed_g5_defconfig ast2600-evb "" \
	rootfs-armv7a.ext2 automatic nolockdep:fstest::sd2,b300:net=nic:fstest=minix aspeed-ast2600-evb.dtb
    retcode=$((${retcode} + $?))
    runkernel aspeed_g5_defconfig ast2600-evb "" \
	rootfs-armv7a.ext2 automatic nolockdep:fstest::sd2,b300:net=nic:fstest=nilfs2 aspeed-ast2600-evb.dtb
    retcode=$((${retcode} + $?))
    runkernel aspeed_g5_defconfig ast2600-evb "" \
	rootfs-armv7a.ext2 automatic nolockdep:fstest::sd2,b300:net=nic:fstest=xfs aspeed-ast2600-evb.dtb
    retcode=$((${retcode} + $?))
fi

runkernel aspeed_g4_defconfig quanta-q71l-bmc "" \
	rootfs-armv5.cpio automatic "::net=nic" aspeed-bmc-quanta-q71l.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g4_defconfig quanta-q71l-bmc "" \
	rootfs-armv5.ext2 automatic "::mtd32:net=nic" aspeed-bmc-quanta-q71l.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g4_defconfig palmetto-bmc "" \
	rootfs-armv5.cpio automatic "::net=nic" aspeed-bmc-opp-palmetto.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g4_defconfig palmetto-bmc "" \
	rootfs-armv5.ext2 automatic "::mtd32:net=nic" aspeed-bmc-opp-palmetto.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g5_defconfig supermicro-x11spi-bmc "" \
	rootfs-armv5.cpio automatic "::net=nic" aspeed-bmc-supermicro-x11spi.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
# Qemu support for Macronix mx25l25635e is broken after v6.15 due to changes in
# upstream chip identification code. See upstream commit 947c86e481a027e ("mtd:
# spi-nor: macronix: Drop the redundant flash info fields") for details.
runkernel aspeed_g5_defconfig "supermicro-x11spi-bmc${flash_model_256}" "" \
	rootfs-armv5.ext2 automatic "::mtd32:net=nic" aspeed-bmc-supermicro-x11spi.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig "supermicro-x11spi-bmc${flash_model_256}" "" \
	rootfs-armv5.sqf automatic "::mtd32,0,6,1:net=nic" aspeed-bmc-supermicro-x11spi.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g5_defconfig witherspoon-bmc "" \
	rootfs-armv5.cpio automatic ${notests}::net=nic aspeed-bmc-opp-witherspoon.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig witherspoon-bmc "" \
	rootfs-armv5.ext2 automatic ${notests}::mtd32:net=nic aspeed-bmc-opp-witherspoon.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g5_defconfig fp5280g2-bmc "" \
	rootfs-armv5.cpio automatic ${notests}::net=nic aspeed-bmc-inspur-fp5280g2.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig fp5280g2-bmc "" \
	rootfs-armv5.ext2 automatic ${notests}::mtd64:net=nic aspeed-bmc-inspur-fp5280g2.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g5_defconfig ast2500-evb "" \
	rootfs-armv5.cpio automatic ${notests}::net=nic aspeed-ast2500-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig ast2500-evb "" \
	rootfs-armv5.ext2 automatic ${notests}::sd:net=nic aspeed-ast2500-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig ast2500-evb "" \
	rootfs-armv5.ext2 automatic ${notests}::mtd32:net=nic aspeed-ast2500-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
# EHCI
runkernel aspeed_g5_defconfig ast2500-evb "" \
	rootfs-armv5.ext2 automatic ${notests}::usb1:net=nic aspeed-ast2500-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
# UHCI
runkernel aspeed_g5_defconfig ast2500-evb "" \
	rootfs-armv5.ext2 automatic ${notests}::usb2:net=nic aspeed-ast2500-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g5_defconfig ast2600-evb "" \
	rootfs-armv5.cpio automatic ${notests}::net=nic aspeed-ast2600-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
# Run the next test with armv7a root file system.
# Both are expected to work.
# ast2600-evb supports an EMMC interface as well as two SDHCI interfaces.
# Run tests on all of them. Explicitly specify the root file system using
# its major/minor device number because the association to mmcblkX
# is not fixed.
runkernel aspeed_g5_defconfig ast2600-evb "" \
	rootfs-armv7a.ext2 automatic ${notests}::sd0,b300:net=nic aspeed-ast2600-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig ast2600-evb "" \
	rootfs-armv7a.ext2 automatic ${notests}::sd1,b300:net=nic aspeed-ast2600-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig ast2600-evb "" \
	rootfs-armv7a.ext2 automatic ${notests}::sd2,b300:net=nic aspeed-ast2600-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
# EHCI
runkernel aspeed_g5_defconfig ast2600-evb "" \
	rootfs-armv5.ext2 automatic ${notests}::usb1:net=nic aspeed-ast2600-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
# UHCI, through USB hub
runkernel aspeed_g5_defconfig ast2600-evb "" \
	rootfs-armv5.ext2 automatic ${notests}::usb-hub1:net=nic aspeed-ast2600-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
# EHCI, through USB v2 hub
runkernel aspeed_g5_defconfig ast2600-evb "" \
	rootfs-armv5.ext2 automatic ${notests}::usb-hub1,2:net=nic aspeed-ast2600-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
# The following tests require qemu 7.1+ and Linux v5.18+
# Boot from 1st SPI controller (fmc)
runkernel aspeed_g5_defconfig "ast2600-evb${flash_model_512}" "" \
	rootfs-armv7a.ext2 automatic ${notests}::mtd64:net=nic aspeed-ast2600-evb.dtb
    retcode=$((${retcode} + $?))
    checkstate ${retcode}
# Boot from 2nd SPI controller
runkernel aspeed_g5_defconfig "ast2600-evb${flash_model_512}" "" \
	rootfs-armv7a.ext2 automatic ${notests}::mtd64,0,6,1:net=nic aspeed-ast2600-evb.dtb
    retcode=$((${retcode} + $?))
    checkstate ${retcode}

runkernel aspeed_g5_defconfig fuji-bmc "" \
	rootfs-armv5.cpio automatic ${notests}::net=nic aspeed-bmc-facebook-fuji.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig fuji-bmc "" \
	rootfs-armv5.ext2 automatic ${notests}::sd2:net=nic aspeed-bmc-facebook-fuji.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig fuji-bmc "" \
	rootfs-armv5.ext2 automatic ${notests}::usb1:net=nic aspeed-bmc-facebook-fuji.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
# Default memory size (2G) prevents SPI device instantiation,
# so limit memory size to 1G
runkernel aspeed_g5_defconfig fuji-bmc "" \
	rootfs-armv5.ext2 automatic ${notests}::mem1G:mtd128:net=nic aspeed-bmc-facebook-fuji.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g5_defconfig fuji-bmc "" \
	rootfs-armv5.f2fs automatic ${notests}::mem1G:mtd128,0,8,1:net=nic aspeed-bmc-facebook-fuji.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g5_defconfig romulus-bmc "" \
	rootfs-armv5.cpio automatic ${notests}::net=nic aspeed-bmc-opp-romulus.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig romulus-bmc "" \
	rootfs-armv5.ext2 automatic ${notests}::mtd32:net=nic aspeed-bmc-opp-romulus.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g5_defconfig g220a-bmc "" \
	rootfs-armv5.cpio automatic ${notests}::net=nic aspeed-bmc-bytedance-g220a.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig g220a-bmc "" \
	rootfs-armv5.ext2 automatic ${notests}::mtd64:net=nic aspeed-bmc-bytedance-g220a.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
# Test booting from second SPI controller
runkernel aspeed_g5_defconfig g220a-bmc "" \
	rootfs-armv5.sqf automatic ${notests}::mtd32,0,12,2:net=nic aspeed-bmc-bytedance-g220a.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g5_defconfig rainier-bmc "" \
	rootfs-armv5.ext2 automatic ${notests}::mmc:net=nic aspeed-bmc-ibm-rainier.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
# EHCI
runkernel aspeed_g5_defconfig rainier-bmc "" \
	rootfs-armv5.ext2 automatic ${notests}::usb1:net=nic aspeed-bmc-ibm-rainier.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
# UHCI, through USB hub
runkernel aspeed_g5_defconfig rainier-bmc "" \
	rootfs-armv5.ext2 automatic ${notests}::usb-hub1:net=nic aspeed-bmc-ibm-rainier.dtb
retcode=$((${retcode} + $?))
# EHCI, through USB v2 hub
runkernel aspeed_g5_defconfig rainier-bmc "" \
	rootfs-armv5.ext2 automatic ${notests}::usb-hub1,2:net=nic aspeed-bmc-ibm-rainier.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
if [ ${runall} -eq 1 ]; then
    # does not instantiate (SPI controller not supported by qemu)
    runkernel aspeed_g5_defconfig rainier-bmc "" \
	rootfs-armv5.ext2 automatic ${notests}::mtd128:net=nic aspeed-bmc-ibm-rainier.dtb
    retcode=$((${retcode} + $?))
    checkstate ${retcode}
fi

# The Bonnell machine is not supported by upstream qemu, and adding it was
# rejected. Boot the rainier-bmc machine with Bonnell devicetree file for
# TPM testing.
if [[ ${linux_version_code} -ge $(kernel_version 6 9) ]]; then
    # The necessary compatible "tcg,tpm-tis-i2c" is only available in v6.9+.
    runkernel aspeed_g5_defconfig rainier-bmc "" \
	rootfs-armv5.cpio automatic \
	${notests}::tpm-tis-i2c,bus=aspeed.i2c.bus.12,address=0x2e:net=nic \
	aspeed-bmc-ibm-bonnell.dtb
    retcode=$((${retcode} + $?))
    checkstate ${retcode}
fi

runkernel aspeed_g5_defconfig bletchley-bmc "" \
	rootfs-armv5.cpio automatic ${notests}::net=nic aspeed-bmc-facebook-bletchley.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
# EHCI0
runkernel aspeed_g5_defconfig bletchley-bmc "" \
	rootfs-armv5.ext2 automatic ${notests}::usb0:net=nic aspeed-bmc-facebook-bletchley.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
# EHCI1
runkernel aspeed_g5_defconfig bletchley-bmc "" \
	rootfs-armv5.ext2 automatic ${notests}::usb1:net=nic aspeed-bmc-facebook-bletchley.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig bletchley-bmc "" \
	rootfs-armv5.ext2 automatic ${notests}::mmc:net=nic aspeed-bmc-facebook-bletchley.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
# The default SPI chips used on this board are not supported by Linux as of
# Linux 6.1/6.2, so select supported chips. Also, the default RAM size of
# 2G prevents SPI interface instantiation, so limit RAM size for SPI tests
# to 1G.
runkernel aspeed_g5_defconfig bletchley-bmc,fmc-model=mt25qu02g,spi-model=mt25qu02g "" \
	rootfs-armv5.f2fs automatic ${notests}::mem1G:mtd256:net=nic aspeed-bmc-facebook-bletchley.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g5_defconfig qcom-dc-scm-v1-bmc "" \
	rootfs-armv5.cpio automatic ${notests}::net=nic aspeed-bmc-qcom-dc-scm-v1.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig qcom-dc-scm-v1-bmc "" \
	rootfs-armv5.ext2 automatic ${notests}::mtd64:net=nic aspeed-bmc-qcom-dc-scm-v1.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
# Also test booting from second SPI controller
runkernel aspeed_g5_defconfig qcom-dc-scm-v1-bmc "" \
	rootfs-armv5.ext2 automatic ${notests}::mtd64,0,12,2:net=nic aspeed-bmc-qcom-dc-scm-v1.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

exit ${retcode}
