#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

QEMU=${QEMU:-${QEMU_V40_BIN}/qemu-system-s390x}
PREFIX=s390-linux-
ARCH=s390
# PATH_S390=/opt/kernel/s390/gcc-6.4.0/bin
PATH_S390=/opt/kernel/gcc-8.3.0-nolibc/s390-linux/bin

PATH=${PATH_S390}:${PATH}

patch_defconfig()
{
    local defconfig=$1
    local fixup=$2

    # qemu only supports MARCH_Z900. Older kernels select it as default,
    # but newer kernels may select MARCH_Z196.
    sed -i -e '/CONFIG_MARCH_Z/d' ${defconfig}
    sed -i -e '/HAVE_MARCH_Z/d' ${defconfig}
    echo "CONFIG_MARCH_Z900=y" >> ${defconfig}
    echo "CONFIG_PCI=y" >> ${defconfig}
}

runkernel()
{
    local defconfig=$1
    local fixup=$2
    local rootfs=$3
    local pid
    local logfile=$(__mktemp)
    local waitlist=("Requesting system reboot" "Boot successful" "Rebooting")
    local build="${ARCH}:${defconfig}${fixup:+:${fixup}}"

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":rootfs"
    fi

    echo -n "Building ${build} ... "

    if ! dosetup -c "${defconfig}" -F "${fixup}" "${rootfs}" "${defconfig}"; then
	return 1
    fi

    echo -n "running ..."

    [[ ${dodebug} -ne 0 ]] && set -x

    ${QEMU} -kernel arch/s390/boot/bzImage \
        ${extra_params} \
	-append "${initcli}" \
	-m 512 \
	-nographic -monitor null --no-reboot > ${logfile} 2>&1 &
    pid=$!

    [[ ${dodebug} -ne 0 ]] && set +x

    dowait ${pid} ${logfile} automatic waitlist[@]
    return $?
}

echo "Build reference: $(git describe)"
echo

runkernel defconfig "" rootfs.cpio.gz
retcode=$?
runkernel defconfig virtio-blk-ccw rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel defconfig scsi[virtio-ccw] rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel defconfig virtio-pci rootfs.ext2.gz
retcode=$((retcode + $?))
runkernel defconfig scsi[virtio-pci] rootfs.ext2.gz
retcode=$((retcode + $?))

exit ${retcode}
