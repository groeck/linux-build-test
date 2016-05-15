#!/bin/bash

config=$1
variant=$2

rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
case "${rel}" in
v3.2|v3.4|v3.10|v3.12|v3.16)
	PATH_MIPS=/opt/poky/1.3/sysroots/x86_64-pokysdk-linux/usr/bin/mips32-poky-linux
	;;
*)
	PATH_MIPS=/opt/poky/2.0/sysroots/x86_64-pokysdk-linux/usr/bin/mips-poky-linux
	;;
esac

# machine specific information
PREFIX=mips-poky-linux-
ARCH=mips

PATH=${PATH_MIPS}:${PATH}
dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

# Called from dosetup() to patch the configuration file.
patch_defconfig()
{
    local defconfig=$1

    sed -i -e '/CONFIG_DEVTMPFS/d' ${defconfig}
    echo "CONFIG_DEVTMPFS=y" >> ${defconfig}

    # Build a 64 bit kernel with INITRD enabled.
    # Don't touch the fulong2 configuration.
    if [ "${fixup}" != "fulong2e" ]
    then
	sed -i -e '/CONFIG_BLK_DEV_INITRD/d' ${defconfig}
	echo "CONFIG_BLK_DEV_INITRD=y" >> ${defconfig}

	sed -i -e '/CONFIG_CPU_MIPS/d' ${defconfig}
	sed -i -e '/CONFIG_32BIT/d' ${defconfig}
	sed -i -e '/CONFIG_64BIT/d' ${defconfig}
	echo "CONFIG_CPU_MIPS64_R1=y" >> ${defconfig}
	echo "CONFIG_64BIT=y" >> ${defconfig}
    fi

    # Only build an SMP image if asked for. Fulong2e is always SMP.
    sed -i -e '/CONFIG_MIPS_MT_SMP/d' ${defconfig}
    if [ "${fixup}" = "smp" -o "${fixup}" = "fulong2e" ]
    then
        echo "CONFIG_MIPS_MT_SMP=y" >> ${defconfig}
    fi
}

runkernel()
{
    local defconfig=$1
    local mach=$2
    local rootfs=$3
    local fixup=$4
    local drive="hda"
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("Boot successful" "Rebooting")
    local build="${ARCH}:${defconfig}:${fixup}"

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

    dosetup ${ARCH} ${PREFIX} "" ${rootfs} ${defconfig} "" ${fixup}
    retcode=$?
    if [ ${retcode} -ne 0 ]
    then
	if [ ${retcode} -eq 2 ]
	then
	    return 0
	fi
	return 1
    fi

    echo -n "running ..."

    if [ "${rootfs}" = "busybox-mips64el.cpio" ]
    then
        /opt/buildbot/bin/qemu-system-mips64el -M ${mach} \
	    -kernel vmlinux -vga cirrus -no-reboot -m 128 \
	    --append "rdinit=/sbin/init mem=128M console=ttyS0 console=tty doreboot" \
	    -nographic -monitor none \
	    -initrd ${rootfs} > ${logfile} 2>&1 &
    	pid=$!
    else
	# New configurations mount sda instead of hda
        grep sda arch/mips/configs/${defconfig} >/dev/null 2>&1
	[ $? -eq 0 ] && drive="sda"

        /opt/buildbot/bin/qemu-system-mips64el -M ${mach} \
	    -kernel vmlinux -no-reboot -m 128 \
	    --append "root=/dev/${drive} rw console=ttyS0 doreboot" \
	    -hda ${rootfs} \
	    -nographic -serial stdio -monitor null > ${logfile} 2>&1 &
    	pid=$!
    fi

    dowait ${pid} ${logfile} automatic waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel malta_defconfig malta busybox-mips64el.cpio nosmp
retcode=$?
runkernel malta_defconfig malta busybox-mips64el.cpio smp
retcode=$((${retcode} + $?))
runkernel fuloong2e_defconfig fulong2e rootfs.mipsel.ext3 fulong2e
retcode=$((${retcode} + $?))

exit ${retcode}
