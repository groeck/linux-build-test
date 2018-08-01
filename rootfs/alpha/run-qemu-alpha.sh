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

skip_316="alpha:defconfig:scsi[AM53C974]:rootfs \
	alpha:defconfig:scsi[DC395]:rootfs"

skip_318="alpha:defconfig:scsi[AM53C974]:rootfs \
	alpha:defconfig:scsi[DC395]:rootfs"

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
    echo "CONFIG_SCSI_DC395x=y" >> ${defconfig}
    echo "CONFIG_SCSI_AM53C974=y" >> ${defconfig}
    echo "CONFIG_MEGARAID_SAS=y" >> ${defconfig}
    echo "CONFIG_FUSION=y" >> ${defconfig}
    echo "CONFIG_FUSION_SAS=y" >> ${defconfig}
    # broken
    echo "CONFIG_SCSI_SYM53C8XX_2=y" >> ${defconfig}

    # Enable NVME support
    echo "CONFIG_BLK_DEV_NVME=y" >> ${defconfig}
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
        if [[ "${fixup}" == scsi* || "${fixup}" == "nvme" ]]; then
	    build+=":${fixup}"
	fi
	build+=":rootfs"
    fi

    echo -n "Building ${build} ... "

    if ! checkskip "${build}" ; then
	return 0
    fi

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
	local wwn
	case "${fixup}" in
	"scsi[53C810]")
	    device="lsi53c810"
	    ;;
	"scsi[53C895A]")
	    device="lsi53c895a"
	    ;;
	"scsi[DC395]")
	    device="dc390"
	    ;;
	"scsi[AM53C974]")
	    device="am53c974"
	    ;;
	"scsi[MEGASAS]")
	    device="megasas"
	    ;;
	"scsi[MEGASAS2]")
	    device="megasas-gen2"
	    ;;
	"scsi[FUSION]")
	    device="mptsas1068"
	    # wwn (World Wide Name) is mandatory for this device
	    wwn="0x5000c50015ea71ac"
	    ;;
	esac
	diskcmd="-device ${device}"
	diskcmd+=" -device scsi-hd,drive=d0${wwn:+,wwn=${wwn}}"
	diskcmd+=" -drive file=${rootfs},if=none,format=raw,id=d0"
    elif [[ "${fixup}" == "nvme" ]]; then
	initcli="root=/dev/nvme0n1 rw"
	diskcmd="-device nvme,serial=foo,drive=d0 \
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
runkernel defconfig "scsi[DC395]" rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig "scsi[MEGASAS]" rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig "scsi[MEGASAS2]" rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig "scsi[FUSION]" rootfs.ext2
retcode=$((${retcode} + $?))

if [[ ${runall} -ne 0 ]]; then
    # broken
    # CACHE TEST FAILED: host wrote 1, chip read 0.
    # CACHE TEST FAILED: chip wrote 2, host read 0.
    # sym0: CACHE INCORRECTLY CONFIGURED.
    # sym0: giving up ...
    # WARNING: CPU: 0 PID: 1 at ./include/linux/dma-mapping.h:541 ___free_dma_mem_cluster+0x184/0x1a0
    runkernel defconfig "scsi[53C810]" rootfs.ext2
    retcode=$((${retcode} + $?))
    # sym0: SCSI BUS has been reset.
    # sym0: unexpected disconnect
    runkernel defconfig "scsi[53C895A]" rootfs.ext2
    retcode=$((${retcode} + $?))
fi

runkernel defconfig "nvme" rootfs.ext2
retcode=$((${retcode} + $?))

exit ${rv}
