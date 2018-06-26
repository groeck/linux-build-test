#!/bin/bash

progdir=$(cd $(dirname "$0"); pwd)
. "${progdir}/../scripts/config.sh"
. "${progdir}/../scripts/common.sh"

QEMU=${QEMU:-${QEMU_RISCV_BIN}/qemu-system-riscv64}
PREFIX=riscv64-linux-
ARCH=riscv
PATH_RISCV=/opt/kernel/riscv64/gcc-7.3.0/bin

PATH=${PATH}:${PATH_RISCV}

patch_defconfig()
{
	local defconfig=$1

	echo "CONFIG_DEVTMPFS_MOUNT=y" >>"${defconfig}"
}

cached_config=""

runkernel()
{
    local mach=$1
    local defconfig=$2
    local fixup=$3
    local rootfs=$4
    local pid
    local retcode
    local waitlist=("Restarting system" "Boot successful" "Requesting system reboot")
    local logfile="$(mktemp)"
    local build="${mach}:${defconfig}"
    local initcli
    local diskcmd

    if [[ "${rootfs}" == *cpio ]]; then
	build+=":initrd"
	initcli="rdinit=/sbin/init"
	diskcmd="-initrd ${rootfs}"
    else
	build+=":rootfs"
	initcli="root=/dev/vda rw"
	diskcmd="-drive file=${rootfs},format=raw,id=hd0 -device virtio-blk-device,drive=hd0"
    fi

    echo -n "Building ${build} ... "

    if [ "${cached_config}" != "${defconfig}:${fixup}" ]; then
	dosetup -d -f "${fixup}" "${rootfs}" "${defconfig}"
	if [ $? -ne 0 ]; then
	    return 1
	fi
	cached_config="${defconfig}:${fixup}"
    else
	setup_rootfs "${rootfs}"
    fi

    if [[ "${rootfs}" == *.gz ]]; then
	gunzip "${rootfs}"
	rootfs="${rootfs%.gz}"
    fi

    echo -n "running ..."

    ${QEMU} -M virt -m 512M -no-reboot \
	-bios "${progdir}/bbl" \
	-kernel vmlinux \
	-netdev user,id=net0 -device virtio-net-device,netdev=net0 \
	${diskcmd} \
	-append "${initcli} earlycon console=ttyS0,115200" \
	-nographic -monitor none \
	> ${logfile} 2>&1 &

    pid=$!

    dowait ${pid} ${logfile} manual waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

retcode=0
runkernel virt defconfig devtmpfs rootfs.cpio
retcode=$((retcode + $?))
runkernel virt defconfig devtmpfs rootfs.ext2.gz
retcode=$((retcode + $?))

exit ${retcode}
