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
PATH_OR32="/opt/kernel/${DEFAULT_CC}/or1k-linux/bin"

PATH=${PATH_OR32}:${PATH}

patch_defconfig()
{
    local defconfig=$1

    # Specify initramfs file name
    sed -i -e '/CONFIG_INITRAMFS_SOURCE/d' ${defconfig}
    echo "CONFIG_INITRAMFS_SOURCE=\"$(rootfsname ${rootfs})\"" >> ${defconfig}

    # We need to support initramfs gzip compression
    sed -i -e '/CONFIG_RD_GZIP/d' ${defconfig}
    echo "CONFIG_RD_GZIP=y" >> ${defconfig}

    # string kunit tests run slow on this architecture, causing random test
    # failures. Avoid unnecessary random failure reports and disable it.
    echo "CONFIG_STRING_KUNIT_TEST=n" >> ${defconfig}
}

runkernel()
{
    local defconfig=$1
    local waitlist=("Restarting system" "Boot successful" "Rebooting")
    local fixup

    echo -n "Building ${ARCH}:or1200:${defconfig} ... "

    fixup="nolockup"
    if [[ ${linux_version_code} -lt $(kernel_version 5 0) ]]; then
	# We don't run network tests, so don't enable them
	fixup+=":nonet"
    fi

    if ! dosetup -F "${fixup}" "${rootfs}" "${defconfig}"; then
	return 1
    fi

    initcli+=" console=ttyS0 earlycon"
    execute manual waitlist[@] \
	${QEMU} -cpu or1200 -M or1k-sim \
	    ${initcli:+--append "${initcli}"} \
	    -kernel vmlinux -nographic -serial stdio -monitor none

    return $?
}

build_reference "${PREFIX}gcc" "${QEMU}"

runkernel or1ksim_defconfig
retcode=$?

exit ${retcode}
