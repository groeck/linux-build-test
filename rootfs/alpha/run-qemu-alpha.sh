#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-alpha}

PREFIX=alpha-linux-
ARCH=alpha

rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
PATH_ALPHA=/opt/kernel/gcc-6.4.0-nolibc/alpha-linux/bin

PATH=${PATH_ALPHA}:${PATH}

patch_defconfig()
{
    local defconfig=$1
    local fixup=$2

    # Enable BLK_DEV_INITRD
    echo "CONFIG_BLK_DEV_INITRD=y" >> ${defconfig}

    # Enable DEVTMPFS
    echo "CONFIG_DEVTMPFS=y" >> ${defconfig}
    echo "CONFIG_DEVTMPFS_MOUNT=y" >> ${defconfig}

    # Enable SCSI controllers
    # Note: CONFIG_SCSI_SYM53C8XX_2=y doesn't work
    echo "CONFIG_SCSI_DC395x=y" >> ${defconfig}
    echo "CONFIG_SCSI_AM53C974=y" >> ${defconfig}
    echo "CONFIG_MEGARAID_SAS=y" >> ${defconfig}
}

cached_config=""

runkernel()
{
    local defconfig=$1
    local fixup=$2
    local rootfs=$3
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Boot successful" "Rebooting" "Restarting system")
    local build="${ARCH}:${defconfig}"

    if [[ "${rootfs}" == *cpio ]]; then
	build+=":initrd"
    else
        if [[ "${fixup}" == scsi* ]]; then
	    build+=":${fixup}"
	fi
	build+=":rootfs"
    fi

    echo -n "Building ${build} ... "

    if [ "${cached_config}" != "${defconfig}" ]; then
	dosetup -f "${fixup:-fixup}" "${rootfs}" "${defconfig}"
	if [ $? -ne 0 ]; then
	    return 1
	fi
	cached_config="${defconfig}"
    else
	setup_rootfs "${rootfs}"
    fi

    echo -n "running ..."

    if [[ "${rootfs}" == *cpio ]]; then
	initcli="rdinit=/sbin/init"
	diskcmd="-initrd ${rootfs}"
    elif [[ "${fixup}" == scsi* ]]; then
	initcli="root=/dev/sda rw"
	case "${fixup}" in
	"scsi[DC395]")
	    device="dc390"
	    ;;
	"scsi[AM53C974]")
	    device="am53c974"
	    ;;
	"scsi[MEGASAS]")
	    device="megasas-gen2"
	    ;;
	esac
	diskcmd="-device "${device}" -device scsi-hd,drive=d0 \
		-drive file=${rootfs},if=none,format=raw,id=d0"
    else
	local hddev="sda"
	grep -q CONFIG_IDE=y .config >/dev/null 2>&1
	[ $? -eq 0 ] && hddev="hda"
	initcli="root=/dev/${hddev} rw"
	diskcmd="-drive file=${rootfs},if=ide,format=raw"
    fi

    [[ ${dodebug} -ne 0 ]] && set -x

    ${QEMU} -M clipper \
	-kernel arch/alpha/boot/vmlinux -no-reboot \
	${diskcmd} \
	-append "${initcli} console=ttyS0" \
	-m 128M -nographic -monitor null -serial stdio \
	> ${logfile} 2>&1 &
    pid=$!

    [[ ${dodebug} -ne 0 ]] && set +x

    dowait ${pid} ${logfile} auto waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel defconfig devtmpfs busybox-alpha.cpio
rv=$?
runkernel defconfig sata rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig "scsi[AM53C974]" rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig "scsi[DC390]" rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig "scsi[MEGASAS]" rootfs.ext2
retcode=$((${retcode} + $?))

exit ${rv}
