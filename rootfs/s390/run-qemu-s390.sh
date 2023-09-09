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

QEMU=${QEMU:-${QEMU_V81_BIN}/qemu-system-s390x}

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

# net=igb only works starting with 5.10
skip_414="s390:defconfig:nolocktests:smp2:scsi[virtio-ccw]:net=igb:rootfs"
skip_419="s390:defconfig:nolocktests:smp2:scsi[virtio-ccw]:net=igb:rootfs"
skip_54="s390:defconfig:nolocktests:smp2:scsi[virtio-ccw]:net=igb:rootfs"

patch_defconfig()
{
    local defconfig=$1
    local fixup=$2

    enable_config ${defconfig} CONFIG_EROFS_FS CONFIG_EROFS_FS_ZIP
    enable_config ${defconfig} CONFIG_F2FS_FS
    enable_config ${defconfig} CONFIG_EXFAT_FS
    enable_config ${defconfig} CONFIG_HFS_FS
    enable_config ${defconfig} CONFIG_HFSPLUS_FS
    enable_config ${defconfig} CONFIG_MINIX_FS
    enable_config ${defconfig} CONFIG_NILFS2_FS
    enable_config ${defconfig} CONFIG_XFS_FS

    enable_config ${defconfig} CONFIG_PCI

    enable_config ${defconfig} CONFIG_IGB CONFIG_USB_SUPPORT CONFIG_USB
}

runkernel()
{
    local defconfig=$1
    local fixup=$2
    local rootfs=$3
    local waitlist=("Requesting system reboot" "Boot successful" "Rebooting")
    local build="${ARCH}:${defconfig}${fixup:+:${fixup}}"

    if [[ "${rootfs}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":${rootfs##*.}"
    fi

    if ! match_params "${_fixup}@${fixup}"; then
	echo "Skipping ${build} ... "
	return 0
    fi

    echo -n "Building ${build} ... "

    if ! checkskip "${build}" ; then
	return 0
    fi

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

echo "Build reference: $(git describe --match 'v*')"
echo

# erofs is not supported in older kernels
if [[ ${linux_version_code} -ge $(kernel_version 5 4) ]]; then
    erofs="erofs"
else
    erofs="ext2"
fi

# locktests takes way too long for this architecture.

runkernel defconfig "nolocktests:smp2:net=default" rootfs.cpio
retcode=$?
checkstate ${retcode}
runkernel defconfig nolocktests:smp2:virtio-blk-ccw:net=virtio-net-pci rootfs.f2fs
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig nolocktests:smp2:scsi[virtio-ccw]:net=default:fstest=hfs+ rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig nolocktests:smp2:scsi[virtio-ccw]:net=igb:fstest=exfat rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig nolocktests:virtio-pci:net=virtio-net-pci:fstest=nilfs2 rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig nolocktests:scsi[virtio-pci]:net=usb-xhci:fstest=hfs rootfs.ext2
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig nolocktests:usb-xhci:net=e1000e "rootfs.${erofs}"
retcode=$((retcode + $?))
checkstate ${retcode}
runkernel defconfig nolocktests:usb-uas-xhci:net=usb-xhci:fstest=xfs rootfs.ext2
retcode=$((retcode + $?))

exit ${retcode}
