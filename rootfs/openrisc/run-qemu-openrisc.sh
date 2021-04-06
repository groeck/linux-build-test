#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-or1k}
PREFIX=or1k-linux-
ARCH=openrisc
rootfs=rootfs.cpio
PATH_OR32=/opt/kernel/gcc-9.3.0-nolibc/or1k-linux/bin

PATH=${PATH_OR32}:${PATH}

rel="$(git describe | cut -f1 -d- | cut -f1,2 -d.)"

patch_defconfig()
{
    local defconfig=$1

    # Specify initramfs file name
    sed -i -e '/CONFIG_INITRAMFS_SOURCE/d' ${defconfig}
    echo "CONFIG_INITRAMFS_SOURCE=\"$(rootfsname ${rootfs})\"" >> ${defconfig}

    # We need to support initramfs gzip compression
    sed -i -e '/CONFIG_RD_GZIP/d' ${defconfig}
    echo "CONFIG_RD_GZIP=y" >> ${defconfig}
}

runkernel()
{
    local defconfig=$1
    local waitlist=("Restarting system" "Boot successful" "Rebooting")
    local fixup

    echo -n "Building ${ARCH}:${defconfig} ... "

    case "${rel}" in
    "v4.14"|"v4.19")
	# We don't run network tests, so don't enable them
	fixup="nonet"
	;;
    *)
	fixup="net:default"
	;;
    esac

    if ! dosetup -F "${fixup}" "${rootfs}" "${defconfig}"; then
	return 1
    fi

    execute manual waitlist[@] \
	${QEMU} -cpu or1200 -M or1k-sim \
	    -kernel vmlinux -nographic -serial stdio -monitor none

    return $?
}

echo "Build reference: $(git describe)"
echo

runkernel or1ksim_defconfig
retcode=$?

exit ${retcode}
