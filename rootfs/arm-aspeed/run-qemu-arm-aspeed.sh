#!/bin/bash

progdir=$(cd $(dirname $0); pwd)
. ${progdir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

QEMU_V71=${QEMU:-${QEMU_V71_BIN}/qemu-system-arm}
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

skip_414="arm:ast2500-evb:aspeed_g5_defconfig:notests:sd:net,nic \
	arm:ast2500-evb:aspeed_g5_defconfig:notests:usb:net,nic \
	arm:ast2600-evb:aspeed_g5_defconfig:notests"
skip_419="arm:quanta-q71l-bmc:aspeed_g4_defconfig:mtd32:net,nic \
	arm:ast2500-evb:aspeed_g5_defconfig:notests:sd:net,nic \
	arm:ast2600-evb:aspeed_g5_defconfig:notests:usb:net,nic"
skip_54="arm:palmetto-bmc:aspeed_g4_defconfig:mtd32:net,nic \
	arm:quanta-q71l-bmc:aspeed_g4_defconfig:mtd32:net,nic \
	arm:ast2600-evb:aspeed_g5_defconfig:notests:usb:net,nic \
	arm:ast2600-evb:aspeed_g5_defconfig:notests:sd2:net,nic \
	arm:ast2600-evb:aspeed_g5_defconfig:notests:mtd64:net,nic \
	arm:ast2600-evb:aspeed_g5_defconfig:notests:mtd64,0,6,1:net,nic"
skip_510="arm:ast2600-evb:aspeed_g5_defconfig:notests:usb:net,nic \
	arm:ast2600-evb:aspeed_g5_defconfig:notests:mtd64:net,nic \
	arm:ast2600-evb:aspeed_g5_defconfig:notests:mtd64,0,6,1:net,nic"
skip_515="arm:ast2600-evb:aspeed_g5_defconfig:notests:mtd64:net,nic \
	arm:ast2600-evb:aspeed_g5_defconfig:notests:mtd64,0,6,1:net,nic \
	arm:g220a-bmc:aspeed_g5_defconfig:notests:mtd128,0,12,2:net,nic \
	arm:fuji-bmc:aspeed_g5_defconfig:notests:net,nic \
	arm:fuji-bmc:aspeed_g5_defconfig:notests:sd2:net,nic \
	arm:fuji-bmc:aspeed_g5_defconfig:notests:usb:net,nic "

patch_defconfig()
{
    local defconfig=$1
    local fixups=${2//:/ }
    local fixup

    # Disable Bluetooth and wireless. We won't ever use or test it.
    echo "CONFIG_BT=n" >> ${defconfig}
    echo "CONFIG_WLAN=n" >> ${defconfig}
    echo "CONFIG_WIRELESS=n" >> ${defconfig}

    # Options needed to be built into the kernel for device support
    # MMC
    sed -i -e 's/CONFIG_MMC_BLOCK=m/CONFIG_MMC_BLOCK=y/' ${defconfig}
    # PCMCIA
    sed -i -e 's/CONFIG_ATA=m/CONFIG_ATA=y/' ${defconfig}
    sed -i -e 's/CONFIG_BLK_DEV_SD=m/CONFIG_BLK_DEV_SD=y/' ${defconfig}
    # USB
    sed -i -e 's/CONFIG_USB=m/CONFIG_USB=y/' ${defconfig}
    sed -i -e 's/CONFIG_USB_STORAGE=m/CONFIG_USB_STORAGE=y/' ${defconfig}
    sed -i -e 's/CONFIG_USB_OHCI_HCD=m/CONFIG_USB_OHCI_HCD=y/' ${defconfig}
}

runkernel()
{
    local defconfig=$1
    local mach=$2
    local cpu=$3
    local rootfs=$4
    local mode=$5
    local fixup=$6
    local dtb=$7
    local ddtb="${dtb%.dtb}"
    local dtbfile="arch/arm/boot/dts/${dtb}"
    local nonet=0
    local logfile="$(__mktemp)"
    local waitlist=("Restarting" "Boot successful" "Rebooting")
    local build="${ARCH}:${mach}:${defconfig}${fixup:+:${fixup}}"
    local pbuild="${build}${dtb:+:${dtb%.dtb}}"
    local QEMUCMD="${QEMU}"

    local _boot
    if [[ "${rootfs%.gz}" == *cpio ]]; then
	pbuild+=":initrd"
	_boot="initrd"
    else
	pbuild+=":rootfs"
	_boot="rootfs"
    fi

    pbuild="${pbuild//+(:)/:}"
    build="${build//+(:)/:}"

    if ! match_params "${machine}@${mach}" "${config}@${defconfig}" "${options}@${fixup}" "${devtree}@${ddtb}" "${boot}@${_boot}"; then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    echo -n "Building ${pbuild} ... "

    if ! checkskip "${build}" ; then
	return 0
    fi

    case "${mach}" in
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
	fixup="$(echo ${fixup} | sed -e 's/:\+net,nic//')"
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
	if [[ ! -e "${dtbfile}" ]]; then
	    echo "skipped"
	    return 0
	fi
	dtbcmd="-dtb ${dtbfile}"
    fi

    rootfs="$(rootfsname ${rootfs})"

    kernel="arch/arm/boot/zImage"
    case ${mach} in
    "ast2500-evb" | "palmetto-bmc" | "romulus-bmc" | \
    "witherspoon-bmc" | "g220a-bmc" | "tacoma-bmc" | \
    "supermicro-x11spi-bmc" | "rainier-bmc" | "quanta-q71l-bmc" | "fp5280g2-bmc" | \
    "bletchley-bmc")
	initcli+=" console=ttyS4,115200"
	initcli+=" earlycon=uart8250,mmio32,0x1e784000,115200n8"
	extra_params+=" -nodefaults"
	;;
    "fuji-bmc")
	initcli+=" console=ttyS0,115200"
	initcli+=" earlycon=uart8250,mmio32,0x1e783000,115200n8"
	extra_params+=" -nodefaults"
	;;
    "qcom-dc-scm-v1-bmc" | "ast2600-evb")
	QEMUCMD="${QEMU_V71}"
	initcli+=" console=ttyS4,115200"
	initcli+=" earlycon=uart8250,mmio32,0x1e784000,115200n8"
	extra_params+=" -nodefaults"
	;;
    *)
	;;
    esac

    execute "${mode}" waitlist[@] \
        ${QEMUCMD} -M ${mach} \
	    ${cpu:+-cpu ${cpu}} \
	    -kernel ${kernel} \
	    -no-reboot \
	    ${extra_params} \
	    ${initcli:+--append "${initcli}"} \
	    ${dtbcmd} \
	    -nographic -monitor null -serial stdio

    return $?
}

echo "Build reference: $(git describe --match 'v*')"
echo

runkernel aspeed_g4_defconfig quanta-q71l-bmc "" \
	rootfs-armv5.cpio automatic "::net,nic" aspeed-bmc-quanta-q71l.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g4_defconfig quanta-q71l-bmc "" \
	rootfs-armv5.ext2 automatic "::mtd32:net,nic" aspeed-bmc-quanta-q71l.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g4_defconfig palmetto-bmc "" \
	rootfs-armv5.cpio automatic "::net,nic" aspeed-bmc-opp-palmetto.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g4_defconfig palmetto-bmc "" \
	rootfs-armv5.ext2 automatic "::mtd32:net,nic" aspeed-bmc-opp-palmetto.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g5_defconfig supermicro-x11spi-bmc "" \
	rootfs-armv5.cpio automatic "::net,nic" aspeed-bmc-supermicro-x11spi.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig supermicro-x11spi-bmc "" \
	rootfs-armv5.ext2 automatic "::mtd32:net,nic" aspeed-bmc-supermicro-x11spi.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig supermicro-x11spi-bmc "" \
	rootfs-armv5.ext2 automatic "::mtd32,0,6,1:net,nic" aspeed-bmc-supermicro-x11spi.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

# selftests sometimes hang with soft CPU lockup
runkernel aspeed_g5_defconfig witherspoon-bmc "" \
	rootfs-armv5.cpio automatic notests::net,nic aspeed-bmc-opp-witherspoon.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig witherspoon-bmc "" \
	rootfs-armv5.ext2 automatic notests::mtd32:net,nic aspeed-bmc-opp-witherspoon.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g5_defconfig fp5280g2-bmc "" \
	rootfs-armv5.cpio automatic notests::net,nic aspeed-bmc-inspur-fp5280g2.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig fp5280g2-bmc "" \
	rootfs-armv5.ext2 automatic notests::mtd64:net,nic aspeed-bmc-inspur-fp5280g2.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g5_defconfig ast2500-evb "" \
	rootfs-armv5.cpio automatic notests::net,nic aspeed-ast2500-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig ast2500-evb "" \
	rootfs-armv5.ext2 automatic notests::sd:net,nic aspeed-ast2500-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig ast2500-evb "" \
	rootfs-armv5.ext2 automatic notests::mtd32:net,nic aspeed-ast2500-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig ast2500-evb "" \
	rootfs-armv5.ext2 automatic notests::usb:net,nic aspeed-ast2500-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g5_defconfig ast2600-evb "" \
	rootfs-armv5.cpio automatic notests::net,nic aspeed-ast2600-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
# Run the next test with armv7a root file system.
# Both are expected to work.
runkernel aspeed_g5_defconfig ast2600-evb "" \
	rootfs-armv7a.ext2 automatic notests::sd2:net,nic aspeed-ast2600-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig ast2600-evb "" \
	rootfs-armv5.ext2 automatic notests::usb:net,nic aspeed-ast2600-evb.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
# The following tests require qemu 7.1+ and Linux v5.18+
# Boot from 1st SPI controller (fmc)
runkernel aspeed_g5_defconfig ast2600-evb "" \
	rootfs-armv7a.ext2 automatic notests::mtd64:net,nic aspeed-ast2600-evb.dtb
    retcode=$((${retcode} + $?))
    checkstate ${retcode}
# Boot from 2nd SPI controller
runkernel aspeed_g5_defconfig ast2600-evb "" \
	rootfs-armv7a.ext2 automatic notests::mtd64,0,6,1:net,nic aspeed-ast2600-evb.dtb
    retcode=$((${retcode} + $?))
    checkstate ${retcode}

runkernel aspeed_g5_defconfig fuji-bmc "" \
	rootfs-armv5.cpio automatic notests::net,nic aspeed-bmc-facebook-fuji.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig fuji-bmc "" \
	rootfs-armv5.ext2 automatic notests::sd2:net,nic aspeed-bmc-facebook-fuji.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig fuji-bmc "" \
	rootfs-armv5.ext2 automatic notests::usb:net,nic aspeed-bmc-facebook-fuji.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
if [ ${runall} -eq 1 ]; then
    # SPI interfaces fail to instantiate in Linux:
    # spi-aspeed-smc 1e620000.spi: ioremap failed for resource [mem 0x20000000-0x2fffffff]
    runkernel aspeed_g5_defconfig fuji-bmc "" \
	rootfs-armv5.ext2 automatic notests::mtd128:net,nic aspeed-bmc-facebook-fuji.dtb
    retcode=$((${retcode} + $?))
    checkstate ${retcode}
fi

runkernel aspeed_g5_defconfig romulus-bmc "" \
	rootfs-armv5.cpio automatic notests::net,nic aspeed-bmc-opp-romulus.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig romulus-bmc "" \
	rootfs-armv5.ext2 automatic notests::mtd32:net,nic aspeed-bmc-opp-romulus.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g5_defconfig g220a-bmc "" \
	rootfs-armv5.cpio automatic notests::net,nic aspeed-bmc-bytedance-g220a.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig g220a-bmc "" \
	rootfs-armv5.ext2 automatic notests::mtd128:net,nic aspeed-bmc-bytedance-g220a.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
# Test booting from second SPI controller
runkernel aspeed_g5_defconfig g220a-bmc "" \
	rootfs-armv5.ext2 automatic notests::mtd128,0,12,2:net,nic aspeed-bmc-bytedance-g220a.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g5_defconfig tacoma-bmc "" \
	rootfs-armv5.cpio automatic notests::net,nic aspeed-bmc-opp-tacoma.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig tacoma-bmc "" \
	rootfs-armv5.ext2 automatic notests::mmc:net,nic aspeed-bmc-opp-tacoma.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig tacoma-bmc "" \
	rootfs-armv5.ext2 automatic notests::usb:net,nic aspeed-bmc-opp-tacoma.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

runkernel aspeed_g5_defconfig rainier-bmc "" \
	rootfs-armv5.cpio automatic notests::net,nic aspeed-bmc-ibm-rainier.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig rainier-bmc "" \
	rootfs-armv5.ext2 automatic notests::mmc:net,nic aspeed-bmc-ibm-rainier.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig rainier-bmc "" \
	rootfs-armv5.ext2 automatic notests::usb:net,nic aspeed-bmc-ibm-rainier.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
if [ ${runall} -eq 1 ]; then
    # does not instantiate (SPI controller not supported by qemu)
    runkernel aspeed_g5_defconfig rainier-bmc "" \
	rootfs-armv5.ext2 automatic notests::mtd128:net,nic aspeed-bmc-ibm-rainier.dtb
    retcode=$((${retcode} + $?))
    checkstate ${retcode}
fi

runkernel aspeed_g5_defconfig bletchley-bmc "" \
	rootfs-armv5.cpio automatic notests::net,nic aspeed-bmc-facebook-bletchley.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig bletchley-bmc "" \
	rootfs-armv5.ext2 automatic notests::usb0:net,nic aspeed-bmc-facebook-bletchley.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
if [ ${runall} -eq 1 ]; then
    # requires qemu v7.1 and Linux v5.18+
    # Still fails with error:
    # spi-nor spi0.0: unrecognized JEDEC id bytes: ef 40 21 00 00 00
    # [The SPI chip used on this board is not supported by Linux as of Linux 6.1]
    runkernel aspeed_g5_defconfig bletchley-bmc "" \
	rootfs-armv5.ext2 automatic notests::mtd256:net,nic aspeed-bmc-facebook-bletchley.dtb
    retcode=$((${retcode} + $?))
    checkstate ${retcode}
fi

runkernel aspeed_g5_defconfig qcom-dc-scm-v1-bmc "" \
	rootfs-armv5.cpio automatic notests::net,nic aspeed-bmc-qcom-dc-scm-v1.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
runkernel aspeed_g5_defconfig qcom-dc-scm-v1-bmc "" \
	rootfs-armv5.ext2 automatic notests::mtd128:net,nic aspeed-bmc-qcom-dc-scm-v1.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}
# Also test booting from second SPI controller
runkernel aspeed_g5_defconfig qcom-dc-scm-v1-bmc "" \
	rootfs-armv5.ext2 automatic notests::mtd128,0,12,2:net,nic aspeed-bmc-qcom-dc-scm-v1.dtb
retcode=$((${retcode} + $?))
checkstate ${retcode}

exit ${retcode}
