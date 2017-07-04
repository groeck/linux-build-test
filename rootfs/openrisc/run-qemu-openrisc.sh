#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-or1k}
PREFIX=or1k-linux-uclibc-
ARCH=openrisc
rootfs=busybox-openrisc.cpio
PATH_OR32=/opt/kernel/or1k/gcc-4.9.0/bin

PATH=${PATH_OR32}:${PATH}

patch_defconfig()
{
    local defconfig=$1

    # Specify initramfs file name
    sed -i -e '/CONFIG_INITRAMFS_SOURCE/d' ${defconfig}
    echo "CONFIG_INITRAMFS_SOURCE=\"${rootfs}\"" >> ${defconfig}

    # We need to support initramfs gzip compression
    sed -i -e '/CONFIG_RD_GZIP/d' ${defconfig}
    echo "CONFIG_RD_GZIP=y" >> ${defconfig}
}

runkernel()
{
    local defconfig=$1
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("MACHINE RESTART" "Boot successful" "Rebooting")
    local fixup=0

    echo -n "Building ${ARCH}:${defconfig} ... "

    # Kernel may expect elf32-or32, but toolchain produces elf32-or1k.
    # Kludgy fix until we find a better solution.
    grep "elf32-or1k" arch/openrisc/kernel/vmlinux.lds.S >/dev/null 2>&1
    fixup=$?
    if [ ${fixup} -ne 0 ]
    then
        sed -i -e 's/elf32-or32/elf32-or1k/g' arch/openrisc/kernel/vmlinux.lds.S
    fi
    dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig} "" fixup
    retcode=$?
    if [ ${fixup} -ne 0 ]
    then
        sed -i -e 's/elf32-or1k/elf32-or32/g' arch/openrisc/kernel/vmlinux.lds.S
    fi
    if [ ${retcode} -ne 0 ]
    then
	return ${retcode}
    fi

    echo -n "running ..."

    ${QEMU} -cpu or1200 -M or1k-sim \
    	-kernel vmlinux -nographic -serial stdio -monitor none \
	> ${logfile} 2>&1 &

    pid=$!
    dowait ${pid} ${logfile} manual waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel or1ksim_defconfig
retcode=$?

exit ${retcode}
