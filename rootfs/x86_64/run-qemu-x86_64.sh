#!/bin/bash

machine=$1
cputype=$2


dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-x86_64}
ARCH=x86_64

# Older releases don't like gcc 6+
rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
case "${rel}" in
"v3.16"|"v3.18")
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
    local pbuild="${ARCH}:${mach}:${cpu}:${defconfig}:${fixup}"
    local config="${defconfig}:${fixup}"

    if [[ "${rootfs}" == *cpio ]]; then
	pbuild+=":initrd"
    else
	pbuild+=":rootfs"
    fi

    if [ -n "${machine}" -a "${machine}" != "${mach}" ]
    then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    if [ -n "${cputype}" -a "${cputype}" != "${cpu}" ]
    then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    echo -n "Building ${pbuild} ... "

    if [ "${cached_config}" != "${config}" ]
    then
	dosetup "${ARCH}" "${PREFIX}" "" "${rootfs}" "${defconfig}" "" "${fixup}"
	if [ $? -ne 0 ]; then
	    return 1
	fi
	cached_config="${config}"
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

    kvm=""
    mem="-m 256"
    if [ "${cpu}" = "kvm64" ]
    then
	kvm="-enable-kvm -smp 4"
	mem="-m 1024"
    fi

    ${QEMU} -kernel arch/x86/boot/bzImage \
	-M ${mach} -cpu ${cpu} ${kvm} -usb -no-reboot ${mem} \
	${diskcmd} \
	--append "${initcli} console=ttyS0 console=tty doreboot" \
	-nographic > ${logfile} 2>&1 &

    pid=$!
    dowait ${pid} ${logfile} manual waitlist[@]
    retcode=$?
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

retcode=0

# runkernel defconfig kvm64 q35
# retcode=$((${retcode} + $?))
runkernel defconfig smp Broadwell-noTSX q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp IvyBridge q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp SandyBridge q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp Haswell q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp core2duo pc rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp Nehalem q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp phenom pc rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp Opteron_G1 q35 rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig smp Opteron_G5 q35 rootfs.cpio
retcode=$((${retcode} + $?))
runkernel defconfig smp EPYC-IBPB q35 rootfs.cpio
retcode=$((${retcode} + $?))
runkernel defconfig smp Skylake-Client q35 rootfs.cpio
retcode=$((${retcode} + $?))
runkernel defconfig smp Opteron_G3 q35 rootfs.cpio
retcode=$((${retcode} + $?))
runkernel defconfig nosmp Opteron_G4 pc rootfs.ext2
retcode=$((${retcode} + $?))
runkernel defconfig nosmp IvyBridge q35 rootfs.ext2
retcode=$((${retcode} + $?))

exit ${retcode}
