#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

_fixup=$1

# Kernels older than v5.4 do not support prno-trng
if [[ ${linux_version_code} -lt $(kernel_version 5 4) ]]; then
    cpu="qemu,prno-trng=off"
else
    cpu="qemu"
fi

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-s390x}

PREFIX=s390-linux-
ARCH=s390
# Kernels prior to v5.0 need gcc 8.x or older. See kernel commit
# 146448524bdd ("s390/jump_label: Use "jdd" constraint on gcc9").
if [[ ${linux_version_code} -lt $(kernel_version 5 0) ]]; then
    PATH_S390="/opt/kernel/gcc-8.5.0-nolibc/s390-linux/bin"
else
    PATH_S390="/opt/kernel/${DEFAULT_CC}/s390-linux/bin"
fi

PATH=${PATH_S390}:${PATH}

patch_defconfig()
{
    local defconfig=$1
    local fixup=$2

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
	-cpu "${cpu}" \
	-kernel arch/s390/boot/bzImage \
        ${extra_params} \
	-append "${initcli}" \
	-m 512 \
	-nographic -monitor null --no-reboot

    return $?
}

echo "Build reference: $(git describe)"
echo

# locktests takes way too long for this architecture.

runkernel defconfig "nolocktests:smp2:net,default" rootfs.cpio.gz
retcode=$?
checkstate ${retcode}
runkernel defconfig nolocktests:smp2:virtio-blk-ccw:net,virtio-net-pci rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig nolocktests:smp2:scsi[virtio-ccw]:net,default rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig nolocktests:virtio-pci:net,virtio-net-pci rootfs.ext2.gz
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig nolocktests:scsi[virtio-pci]:net,default rootfs.ext2.gz
retcode=$((retcode + $?))

exit ${retcode}
