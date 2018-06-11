#!/bin/bash

_cpu=$1
_mach=$2
_defconfig=$3

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-i386}
ARCH=i386

# Older releases don't like gcc 6+
rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
case ${rel} in
v3.16|v3.18)
	PATH_X86=/opt/poky/1.3/sysroots/x86_64-pokysdk-linux/usr/bin/x86_64-poky-linux
	PREFIX="x86_64-poky-linux-"
	;;
*)
	PATH_X86=/opt/kernel/x86_64/gcc-6.3.0/usr/bin/
	PREFIX="x86_64-linux-"
	;;
esac

PATH=${PATH_X86}:${PATH}

cached_config=""

patch_defconfig()
{
    local defconfig=$1
    local fixup=$2

    if [[ "${fixup}" = "nosmp" ]]; then
	sed -i -e '/CONFIG_SMP/d' ${defconfig}
    fi
}

runkernel()
{
    local defconfig=$1
    local fixup=$2
    local cpu=$3
    local mach=$4
    local rootfs=$5
    local drive
    local pid
    local retcode
    local logfile=/tmp/runkernel-$$.log
    local waitlist=("machine restart" "Restarting" "Boot successful" "Rebooting")
    local build="${ARCH}:${cpu}:${mach}:${defconfig}:${fixup}"
    local config="${defconfig}:${fixup}"

    if [[ "${rootfs}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":rootfs"
    fi

    if [ -n "${_cpu}" -a "${_cpu}" != "${cpu}" ]
        then
	echo "Skipping ${build} ... "
	return 0
    fi

    if [ -n "${_mach}" -a "${_mach}" != "${mach}" ]
    then
	echo "Skipping ${build} ... "
	return 0
    fi

    if [ -n "${_defconfig}" -a "${_defconfig}" != "${defconfig}" ]
    then
	echo "Skipping ${build} ... "
	return 0
    fi

    echo -n "Building ${build} ... "

    if [ "${cached_config}" != "${config}" ]
    then
	dosetup "${ARCH}" "${PREFIX}" "" "${rootfs}" "${defconfig}" "" "${fixup}"
	if [ $? -ne 0 ]
	then
	    return 1
	fi
	cached_config=${config}
    else
	setup_rootfs "${rootfs}" ""
    fi

    echo -n "running ..."

    if [[ "${rootfs}" == *cpio ]]; then
	initcli="rdinit=/sbin/init"
	diskcmd="-initrd ${rootfs}"
    else
	initcli="root=/dev/sda rw"
	diskcmd="-drive file=${rootfs},if=ide,format=raw"
    fi

    ${QEMU} -kernel arch/x86/boot/bzImage \
	-M ${mach} -cpu ${cpu} -usb -no-reboot -m 256 \
	${diskcmd} \
	--append "${initcli} mem=256M vga=0 uvesafb.mode_option=640x480-32 oprofile.timer=1 console=ttyS0 console=tty doreboot" \
	-nographic > ${logfile} 2>&1 &

    pid=$!
    dowait ${pid} ${logfile} manual waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel defconfig smp Broadwell q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp Skylake-Client q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp SandyBridge q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp Haswell pc rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp Nehalem q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp phenom pc rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp Opteron_G5 q35 rootfs.cpio
retcode=$((${retcode} + $?))
runkernel defconfig smp Westmere q35 rootfs.cpio
retcode=$((${retcode} + $?))
runkernel defconfig nosmp core2duo q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig nosmp Conroe pc rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig nosmp Opteron_G1 pc rootfs.cpio
retcode=$((${retcode} + $?))
runkernel defconfig nosmp n270 q35 rootfs.ext2
retcode=$((${retcode} + $?))

exit ${retcode}
