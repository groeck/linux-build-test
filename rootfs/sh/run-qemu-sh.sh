#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

_fixup="$1"

QEMU=${QEMU:-${QEMU_V212_BIN}/qemu-system-sh4}

PREFIX=sh4-linux-
ARCH=sh

PATH_SH=/opt/kernel/sh4/gcc-5.3.0/usr/bin

PATH=${PATH_SH}:${PATH}

patch_defconfig()
{
    local defconfig=$1

    # Drop command line overwrite
    sed -i -e '/CONFIG_CMDLINE/d' ${defconfig}

    # broken for this architecture
    echo "CONFIG_PROVE_LOCKING=n" >> ${defconfig}
    echo "CONFIG_TORTURE_TEST=n" >> ${defconfig}
    echo "CONFIG_RCU_TORTURE_TEST=n" >> ${defconfig}
    echo "CONFIG_LOCK_TORTURE_TEST=n" >> ${defconfig}
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

    if ! dosetup -c "${defconfig}" -F "${fixup}" "${rootfs}" "${defconfig}"; then
	return 1
    fi

    echo -n "running ..."

    [[ ${dodebug} -ne 0 ]] && set -x

    ${QEMU} -M r2d -kernel ./arch/sh/boot/zImage \
	${extra_params} \
	-append "${initcli} console=ttySC1,115200 noiotrap" \
	-serial null -serial stdio -net nic,model=rtl8139 -net user \
	-nographic -monitor null \
	> ${logfile} 2>&1 &
    pid=$!

    [[ ${dodebug} -ne 0 ]] && set +x

    dowait ${pid} ${logfile} automatic waitlist[@]
    return $?
}

echo "Build reference: $(git describe)"
echo

retcode=0
runkernel rts7751r2dplus_defconfig "" rootfs.cpio.gz
retcode=$((retcode + $?))
runkernel rts7751r2dplus_defconfig ata rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel rts7751r2dplus_defconfig mmc rootfs.ext2.gz
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
