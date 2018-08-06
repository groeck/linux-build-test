#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-s390x}
PREFIX=s390-linux-
ARCH=s390
PATH_SH=/opt/kernel/s390/gcc-6.4.0/bin

PATH=${PATH_SH}:${PATH}

patch_defconfig()
{
    local defconfig=$1
    local fixup=$2

    # make sure DEVTMPFS is enabled and auto-mounts
    sed -i -e '/CONFIG_DEVTMPFS/d' ${defconfig}
    echo "CONFIG_DEVTMPFS=y" >> ${defconfig}
    echo "CONFIG_DEVTMPFS_MOUNT=y" >> ${defconfig}

    # qemu only supports MARCH_Z900. Older kernels select it as default,
    # but newer kernels may select MARCH_Z196.
    sed -i -e '/CONFIG_MARCH_Z/d' ${defconfig}
    sed -i -e '/HAVE_MARCH_Z/d' ${defconfig}
    echo "CONFIG_MARCH_Z900=y" >> ${defconfig}
}

runkernel()
{
    local defconfig=$1
    local rootfs=$2
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Requesting system reboot" "Boot successful" "Rebooting")
    local build="${ARCH}:${defconfig}"

    if [[ "${rootfs}" == *cpio ]]; then
	initcli="rdinit=/sbin/init"
	diskcmd="-initrd ${rootfs}"
	build+=":initrd"
    else
	initcli="root=/dev/vda rw"
	diskcmd="-drive file=${rootfs},format=raw,if=none,id=d0 \
		-device virtio-blk-ccw,devno=fe.0.0001,drive=d0"
	build+=":rootfs"
    fi

    echo -n "Building ${build} ... "

    if ! dosetup -c "${defconfig}" -f fixup "${rootfs}" "${defconfig}"; then
	return 1
    fi

    echo -n "running ..."

    [[ ${dodebug} -ne 0 ]] && set -x

    ${QEMU} -kernel arch/s390/boot/bzImage \
        ${diskcmd} \
	-append "${initcli} doreboot" \
	-m 512 \
	-nographic -monitor null --no-reboot > ${logfile} 2>&1 &
    pid=$!

    [[ ${dodebug} -ne 0 ]] && set +x

    dowait ${pid} ${logfile} manual waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel defconfig busybox-s390.cpio
retcode=$?
runkernel defconfig rootfs.s390.ext2
retcode=$((${retcode} + $?))

exit ${retcode}
