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

    echo "CONFIG_VIRTIO_BLK_SCSI=y" >> ${defconfig}
}

runkernel()
{
    local defconfig=$1
    local fixup=$2
    local rootfs=$3
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Requesting system reboot" "Boot successful" "Rebooting")
    local build="${ARCH}:${defconfig}"

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	build+=":initrd"
    else
	build+="${fixup:+:${fixup}}:rootfs"
    fi

    echo -n "Building ${build} ... "

    if ! dosetup -c "${defconfig}" -f "${fixup:-fixup}" "${rootfs}" "${defconfig}"; then
	return 1
    fi

    echo -n "running ..."

    if ! common_diskcmd "${fixup##*:}" "${rootfs}"; then
	return 1
    fi

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

runkernel defconfig "" rootfs.cpio.gz
retcode=$?
runkernel defconfig virtio-blk-ccw rootfs.ext2.gz
retcode=$((${retcode} + $?))
runkernel defconfig scsi[virtio-ccw] rootfs.ext2.gz
retcode=$((${retcode} + $?))

exit ${retcode}
