#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-hppa}

PREFIX=hppa-linux-
ARCH=parisc

rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
PATH_PARISC=/opt/kernel/hppa/gcc-7.3.0/bin
PATH=${PATH}:${PATH_PARISC}

cached_config=""

runkernel()
{
    local defconfig=$1
    local rootfs=$2
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("reboot: Restarting system" "Boot successful" "Requesting system reboot")
    local build="${ARCH}:${defconfig}"
    local initcli
    local diskcmd

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	build+=":initrd"
	initcli="rdinit=/sbin/init"
	diskcmd="-initrd ${rootfs%.gz}"
    else
	build+=":rootfs"
	initcli="root=/dev/sda"
	diskcmd="-drive file=${rootfs%.gz},format=raw,if=scsi"
    fi

    echo -n "Building ${build} ... "

    if [ "${cached_config}" != "${defconfig}" ]; then
	# dosetup -f fixup "${rootfs}" "${defconfig}"
	dosetup "${rootfs}" "${defconfig}"
	if [ $? -ne 0 ]; then
	    return 1
	fi
	cached_config="${defconfig}"
    else
	setup_rootfs "${rootfs}"
    fi

    if [[ "${rootfs}" == *.gz ]]; then
	gunzip -f "${rootfs}"
	rootfs="${rootfs%.gz}"
    fi

    echo -n "running ..."

    ${QEMU} -kernel vmlinux -no-reboot \
	${diskcmd} \
	-append "${initcli} console=ttyS0,115200" \
	-nographic -monitor null > ${logfile} 2>&1 &

    pid=$!
    dowait ${pid} ${logfile} automatic waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

retcode=0
runkernel defconfig rootfs.cpio.gz
retcode=$((retcode + $?))
runkernel defconfig rootfs.ext2.gz
retcode=$((retcode + $?))

exit ${retcode}
