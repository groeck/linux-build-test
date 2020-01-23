#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

_fixup="$1"

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-sh4}
PATH_SH=/opt/kernel/gcc-9.2.0-nolibc/sh4-linux/bin

PREFIX=sh4-linux-
ARCH=sh
CONFIG=""
EARLYCON=""

errlog="/tmp/err-sh.log"

rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
case "${rel}" in
v3.16|v4.4|v4.9|v4.14|v4.19)
	;;
*)
	# earlycon only works with v4.20+ and otherwise results in a crash.
	CONFIG="CONFIG_SERIAL_SH_SCI_EARLYCON=y"
	EARLYCON="earlycon=scif,mmio16,0xffe80000"
	;;
esac

PATH=${PATH_SH}:${PATH}

patch_defconfig()
{
    local defconfig=$1

    # Drop command line overwrite
    sed -i -e '/CONFIG_CMDLINE/d' ${defconfig}

    # Conditionally enable earlyprintk
    echo "${CONFIG}" >> ${defconfig}
}

runkernel()
{
    local defconfig=$1
    local fixup=$2
    local rootfs=$3
    local pid
    local logfile=$(__mktemp)
    local waitlist=("Power down" "Boot successful" "Poweroff")
    local build="${ARCH}:${defconfig}"

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":${fixup}:rootfs"
    fi

    if ! match_params "${_fixup}@${fixup}"; then
	echo "Skipping ${build} ... "
	return 0
    fi

    echo -n "Building ${build} ... "

    # 'nofs' is needed to avoid enabling btrfs, which in turn enables raid6,
    # which sometimes hangs in emulation, depending on code alignment.
    if ! dosetup -c "${defconfig}" -F "${fixup}:nofs:notests:nodebug" "${rootfs}" "${defconfig}"; then
	return 1
    fi

    echo -n "running ..."

    initcli+=" console=ttySC1,115200 ${EARLYCON} noiotrap"

    if [[ ${dodebug} -eq 2 ]]; then
	extra_params+=" -d int,mmu,in_asm,guest_errors,unimp,pcall -D ${errlog}"
    fi

    [[ ${dodebug} -eq 1 ]] && set -x

    ${QEMU} -M r2d -kernel ./arch/sh/boot/zImage \
	${extra_params} \
	-append "${initcli}" \
	-serial null -serial stdio -net nic,model=rtl8139 -net user \
	-nographic -monitor null \
	> ${logfile} 2>&1 &
    pid=$!

    [[ ${dodebug} -eq 1 ]] && set +x

    dowait ${pid} ${logfile} automatic waitlist[@]
    local rv=$?
    if [[ ${dodebug} -eq 2 && ${rv} -ne 0 ]]; then
	logfile="$(mktemp sh)"
	mv "${errlog}" "${logfile}"
    fi
    return ${rv}
}

echo "Build reference: $(git describe)"
echo

retcode=0
runkernel rts7751r2dplus_defconfig "" rootfs.cpio.gz
retcode=$((retcode + $?))
runkernel rts7751r2dplus_defconfig ata rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel rts7751r2dplus_defconfig sdhci:mmc rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel rts7751r2dplus_defconfig nvme rootfs.ext2.gz
retcode=$((retcode + $?))

runkernel rts7751r2dplus_defconfig usb rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel rts7751r2dplus_defconfig usb-hub rootfs.ext2.gz
retcode=$((retcode + $?))

runkernel rts7751r2dplus_defconfig usb-ohci rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel rts7751r2dplus_defconfig usb-ehci rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel rts7751r2dplus_defconfig usb-xhci rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel rts7751r2dplus_defconfig usb-uas-ehci rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel rts7751r2dplus_defconfig usb-uas-xhci rootfs.ext2.gz
retcode=$((retcode + $?))

runkernel rts7751r2dplus_defconfig "scsi[53C810]" rootfs.ext2.gz
retcode=$((${retcode} + $?))
runkernel rts7751r2dplus_defconfig "scsi[53C895A]" rootfs.ext2.gz
retcode=$((retcode + $?))

if [[ ${runall} -ne 0 ]]; then
    # hang (scsi command aborts/timeouts)
    runkernel rts7751r2dplus_defconfig "scsi[DC395]" rootfs.ext2.gz
    retcode=$((retcode + $?))
    runkernel rts7751r2dplus_defconfig "scsi[AM53C974]" rootfs.ext2.gz
    retcode=$((retcode + $?))
    # Hang after "megaraid_sas 0000:00:01.0: Waiting for FW to come to ready state"
    runkernel rts7751r2dplus_defconfig "scsi[MEGASAS]" rootfs.ext2.gz
    retcode=$((retcode + $?))
    runkernel rts7751r2dplus_defconfig "scsi[MEGASAS2]" rootfs.ext2.gz
    retcode=$((retcode + $?))
fi

runkernel rts7751r2dplus_defconfig "scsi[FUSION]" rootfs.ext2.gz
retcode=$((retcode + $?))

exit ${retcode}
