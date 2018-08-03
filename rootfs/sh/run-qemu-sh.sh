#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-sh4}

PREFIX=sh4-linux-
ARCH=sh

PATH_SH=/opt/kernel/sh4/gcc-5.3.0/usr/bin

PATH=${PATH_SH}:${PATH}

patch_defconfig()
{
    local defconfig=$1

    # Drop command line overwrite
    sed -i -e '/CONFIG_CMDLINE/d' ${defconfig}

    # Enable DEVTMPFS
    echo "CONFIG_DEVTMPFS=y" >> ${defconfig}
    echo "CONFIG_DEVTMPFS_MOUNT=y" >> ${defconfig}

    # Enable BLK_DEV_INITRD
    echo "CONFIG_BLK_DEV_INITRD=y" >> ${defconfig}
}

cached_config=""

runkernel()
{
    local defconfig=$1
    local rootfs=$2
    local pid
    local retcode
    local logfile=$(mktemp)
    local waitlist=("Power down" "Boot successful" "Poweroff")
    local build="${ARCH}:${defconfig}"

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	build+=":initrd"
	initcli="rdinit=/sbin/init"
	diskcmd="-initrd ${rootfs%.gz}"
    else
	build+=":rootfs"
	initcli="root=/dev/sda"
	diskcmd="-drive file=${rootfs%.gz},if=ide,format=raw"
    fi

    echo -n "Building ${build} ... "

    if [ "${cached_config}" != "${defconfig}" ]; then
	if ! dosetup -f fixup "${rootfs}" "${defconfig}"; then
	    return 1
	fi
	cached_config="${defconfig}"
    else
	setup_rootfs "${rootfs}"
    fi

    rootfs="${rootfs%.gz}"

    echo -n "running ..."

    [[ ${dodebug} -ne 0 ]] && set -x

    ${QEMU} -M r2d -kernel ./arch/sh/boot/zImage \
	${diskcmd} \
	-append "${initcli} console=ttySC1,115200 noiotrap doreboot" \
	-serial null -serial stdio -net nic,model=rtl8139 -net user \
	-nographic -monitor null \
	> ${logfile} 2>&1 &
    pid=$!

    [[ ${dodebug} -ne 0 ]] && set +x

    dowait ${pid} ${logfile} automatic waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

retcode=0
runkernel rts7751r2dplus_defconfig rootfs.cpio.gz
retcode=$((retcode + $?))
runkernel rts7751r2dplus_defconfig rootfs.ext2.gz
retcode=$((retcode + $?))

exit ${retcode}
