#!/bin/bash

config=$1
variant=$2

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
case "${rel}" in
v3.2|v3.16)
	PATH_MIPS=/opt/poky/1.3/sysroots/x86_64-pokysdk-linux/usr/bin/mips32-poky-linux
	PREFIX=mips-poky-linux-
	QEMU=${QEMU:-${QEMU_V29_BIN}/qemu-system-mips64el}
	;;
*)
	# Using Poky 2.0 appears to result in random crashes due to stack
	# corruption (?). No idea if this is a qemu or a compiler problem.
	# PATH_MIPS=/opt/poky/2.0/sysroots/x86_64-pokysdk-linux/usr/bin/mips-poky-linux
	PATH_MIPS=/opt/kernel/gcc-7.3.0-nolibc/mips64-linux/bin
	PREFIX=mips64-linux-
	QEMU=${QEMU:-${QEMU_V211_BIN}/qemu-system-mips64el}
	;;
esac

# machine specific information
ARCH=mips
PATH=${PATH_MIPS}:${PATH}

# Called from dosetup() to patch the configuration file.
patch_defconfig()
{
    local defconfig=$1

    # INITRD may be disabled. Enable for testing.
    sed -i -e '/CONFIG_BLK_DEV_INITRD/d' ${defconfig}
    echo "CONFIG_BLK_DEV_INITRD=y" >> ${defconfig}

    sed -i -e '/CONFIG_DEVTMPFS/d' ${defconfig}
    echo "CONFIG_DEVTMPFS=y" >> ${defconfig}
    echo "CONFIG_DEVTMPFS_MOUNT=y" >> ${defconfig}

    # Leave fulong2e and boston configuration alone
    if [ "${fixup}" = "fulong2e" -o "${fixup}" = "boston" ]
    then
	return 0
    fi

    sed -i -e '/CONFIG_CPU_MIPS/d' ${defconfig}
    sed -i -e '/CONFIG_32BIT/d' ${defconfig}
    sed -i -e '/CONFIG_64BIT/d' ${defconfig}
    echo "CONFIG_CPU_MIPS64_R1=y" >> ${defconfig}
    echo "CONFIG_64BIT=y" >> ${defconfig}

    # Only build an SMP image if asked for.
    sed -i -e '/CONFIG_MIPS_MT_SMP/d' ${defconfig}
    if [ "${fixup}" = "smp" ]
    then
        echo "CONFIG_MIPS_MT_SMP=y" >> ${defconfig}
    fi
}

cached_config=""

runkernel()
{
    local defconfig=$1
    local mach=$2
    local rootfs=$3
    local fixup=$4
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Boot successful" "Rebooting")
    local build="mipsel64:${defconfig}:${fixup}"
    local buildconfig="${defconfig}:${fixup}"

    if [[ "${rootfs}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":rootfs"
    fi

    if [ -n "${config}" -a "${config}" != "${defconfig}" ]
    then
	echo "Skipping ${build} ... "
	return 0
    fi

    if [ -n "${variant}" -a "${variant}" != "${fixup}" ]
    then
	echo "Skipping ${build} ... "
	return 0
    fi

    echo -n "Building ${build} ... "

    if [ "${cached_build}" != "${buildconfig}" ]; then
	dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig} "" ${fixup}
	retcode=$?
	if [ ${retcode} -ne 0 ]; then
	    if [ ${retcode} -eq 2 ]; then
		return 0
	    fi
	    return 1
	fi
	cached_build="${buildconfig}"
    else
	setup_rootfs "${rootfs}" ""
    fi

    echo -n "running ..."

    if [[ "${rootfs}" == *cpio ]]; then
	initcli="rdinit=/sbin/init"
	diskcmd="-initrd ${rootfs}"
    else
	local hddev="sda"
	# Configurations with CONFIG_IDE=y mount hda instead of sda
	grep -q CONFIG_IDE=y .config >/dev/null 2>&1
	[ $? -eq 0 ] && hddev="hda"
	initcli="root=/dev/${hddev} rw"
	diskcmd="-drive file=${rootfs},format=raw,if=ide"
	# or something like:
	# -device ide-hd,drive=d0,bus=ide.0 \
	# -drive file=${rootfs},id=d0,format=raw,if=none
    fi

    case ${mach} in
    "malta")
        ${QEMU} -M ${mach} \
	    -kernel vmlinux -no-reboot -m 128 \
	    --append "${initcli} mem=128M console=ttyS0" \
	    ${diskcmd} \
	    -nographic -monitor none \
	    > ${logfile} 2>&1 &
    	pid=$!
	;;
    "boston")
	${QEMU} -M ${mach} -m 1G -kernel arch/mips/boot/vmlinux.gz.itb \
		-drive file=${rootfs},format=raw,if=ide \
		--append "root=/dev/${hddev} rw console=ttyS0" \
		-serial stdio -monitor none -no-reboot -nographic \
		-dtb arch/mips/boot/dts/img/boston.dtb \
		> ${logfile} 2>&1 &
	pid=$!
	;;
    "fulong2e")
        ${QEMU} -M ${mach} \
	    -kernel vmlinux -no-reboot -m 128 \
	    --append "root=/dev/${hddev} rw console=ttyS0 doreboot" \
	    -drive file=${rootfs},format=raw,if=ide \
	    -nographic -serial stdio -monitor null > ${logfile} 2>&1 &
    	pid=$!
	;;
    esac

    dowait ${pid} ${logfile} automatic waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel malta_defconfig malta rootfs.mipsel64r1.ext2 nosmp
retcode=$?
runkernel malta_defconfig malta busybox-mips64el.cpio smp
retcode=$((${retcode} + $?))
runkernel malta_defconfig malta rootfs.mipsel64r1.ext2 smp
retcode=$((${retcode} + $?))
runkernel fuloong2e_defconfig fulong2e rootfs.mipsel.ext3 fulong2e
retcode=$((${retcode} + $?))
runkernel 64r6el_defconfig boston rootfs.mipsel64r6.ext2 boston
retcode=$((${retcode} + $?))

exit ${retcode}
