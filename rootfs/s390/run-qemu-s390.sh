#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

_fixup=$1

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-s390x}
PREFIX=s390-linux-
ARCH=s390
# PATH_S390=/opt/kernel/s390/gcc-6.4.0/bin
PATH_S390=/opt/kernel/gcc-8.3.0-nolibc/s390-linux/bin

PATH=${PATH_S390}:${PATH}

rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)

patch_defconfig()
{
    local defconfig=$1
    local fixup=$2

    case "${rel}" in
    v4.4)
	# qemu only fully supports MARCH_Z900.
	# Newer versions of qemu work for more recent CPUS with CPU model
	# "qemu", but that does not work for v4.4.y (it crashes silently
	# when trying to boot with the default configuration).
	sed -i -e '/CONFIG_MARCH_Z/d' ${defconfig}
	sed -i -e '/HAVE_MARCH_Z/d' ${defconfig}
	echo "CONFIG_MARCH_Z900=y" >> ${defconfig}
	;;
    *)
	;;
    esac

    echo "CONFIG_PCI=y" >> ${defconfig}
}

runkernel()
{
    local defconfig=$1
    local fixup=$2
    local rootfs=$3
    local waitlist=("Requesting system reboot" "Boot successful" "Rebooting")
    local build="${ARCH}:${defconfig}${fixup:+:${fixup}}"

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":rootfs"
    fi

    if ! match_params "${_fixup}@${fixup}"; then
	echo "Skipping ${build} ... "
	return 0
    fi

    echo -n "Building ${build} ... "

    if ! dosetup -c "${defconfig}" -F "${fixup}" "${rootfs}" "${defconfig}"; then
	return 1
    fi

    execute automatic waitlist[@] \
      ${QEMU} \
	-cpu qemu \
	-kernel arch/s390/boot/bzImage \
        ${extra_params} \
	-append "${initcli}" \
	-m 512 \
	-nographic -monitor null --no-reboot

    return $?
}

echo "Build reference: $(git describe)"
echo

runkernel defconfig "" rootfs.cpio.gz
retcode=$?
checkstate ${retcode}
runkernel defconfig virtio-blk-ccw rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig scsi[virtio-ccw] rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig virtio-pci rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig scsi[virtio-pci] rootfs.ext2.gz
retcode=$((retcode + $?))

exit ${retcode}
