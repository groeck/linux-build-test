#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. "${dir}/../scripts/config.sh"
. "${dir}/../scripts/common.sh"

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-xtensa}

debug=0
if [ "$1" = "-d" ]
then
	debug=1
	shift
fi

skip_316="xtensa:de212:kc705-nommu:nommu_kc705_defconfig"
skip_318="xtensa:de212:kc705-nommu:nommu_kc705_defconfig"
skip_44="xtensa:de212:kc705-nommu:nommu_kc705_defconfig"

machine=$1
config=$2

PREFIX=xtensa-linux-
ARCH=xtensa
PATH_XTENSA=/opt/kernel/xtensa/gcc-6.3.0-dc233c/usr/bin
PATH_XTENSA_DE212=/opt/kernel/xtensa/gcc-6.4.0-de212/bin
PATH_XTENSA_TOOLS=/opt/buildbot/bin/xtensa

PATH=${PATH_XTENSA_TOOLS}:${PATH}

patch_defconfig()
{
    local defconfig=$1
    local fixup=$2
    local progdir=$(cd $(dirname $0); pwd)

    case "${fixup}" in
    dc232b)
	sed -i -e '/CONFIG_XTENSA_VARIANT/d' ${defconfig}
	echo "CONFIG_XTENSA_VARIANT_DC232B=y" >> ${defconfig}
	echo "# CONFIG_INITIALIZE_XTENSA_MMU_INSIDE_VMLINUX is not set" >> ${defconfig}
	echo "CONFIG_KERNEL_LOAD_ADDRESS=0xd0003000" >> ${defconfig}
	;;
    dc233c)
	sed -i -e '/CONFIG_XTENSA_VARIANT/d' ${defconfig}
	echo "CONFIG_XTENSA_VARIANT_DC233C=y" >> ${defconfig}
	;;
    *)
	;;
    esac

    # No built-in initrd
    sed -i -e '/CONFIG_INITRAMFS_SOURCE/d' ${defconfig}
}

runkernel()
{
    local defconfig=$1
    local dts="arch/xtensa/boot/dts/$2.dts"
    local dtb="arch/xtensa/boot/dts/$2.dtb"
    local cpu=$3
    local mach=$4
    local mem=$5
    local rootfs=$6
    local pid
    local retcode
    local logfile="$(mktemp)"
    local waitlist=("Restarting system" "Boot successful" "Rebooting")
    local fixup="${cpu}"
    local pbuild="${ARCH}:${cpu}:${mach}:${defconfig}"
    local cmdline

    if [ -n "${machine}" -a "${machine}" != "${mach}" ]
    then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    if [ -n "${config}" -a "${config}" != "${defconfig}" ]
    then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    case "${mach}" in
    "lx60"|"kc705"|"ml605")
	PATH=${PATH_XTENSA}:${PATH}
	cmdline="earlycon=uart8250,mmio32,0xfd050020,115200n8"
	;;
    "kc705-nommu")
	PATH=${PATH}:${PATH_XTENSA_DE212}
	cmdline="earlycon=uart8250,mmio32,0x9d050020,115200n8 \
		memmap=256M@0x60000000"
	;;
    esac

    echo -n "Building ${pbuild} ... "

    if ! checkskip "${pbuild}"; then
	return 0;
    fi

    if ! dosetup -c "${defconfig}:${cpu}" -f "${fixup}" "${rootfs}" "${defconfig}"; then
	return 1
    fi

    if [ -e "${dts}" ]; then
	dtbcmd="-dtb ${dtb}"
	if [ ! -e "${dtb}" ]; then
	    dtc -I dts -O dtb ${dts} -o ${dtb} >/dev/null 2>&1
	fi
    fi

    echo -n "running ..."

    ${QEMU} -cpu ${cpu} -M ${mach} \
	-kernel arch/xtensa/boot/uImage -no-reboot \
	${dtbcmd} \
	--append "rdinit=/sbin/init ${cmdline} console=ttyS0,115200n8" \
	-initrd ${rootfs} \
	-m ${mem} -nographic -monitor null -serial stdio \
	> ${logfile} 2>&1 &

    pid=$!
    dowait ${pid} ${logfile} manual waitlist[@]
    retcode=$?
    if [ ${debug} -ne 0 ]
    then
	cat ${logfile}
    fi
    rm -f ${logfile}
    return ${retcode}
}

echo "Build reference: $(git describe)"
echo

runkernel generic_kc705_defconfig lx60 dc232b lx60 128M rootfs.cpio
retcode=$?
runkernel generic_kc705_defconfig kc705 dc232b kc705 1G rootfs.cpio
retcode=$((${retcode} + $?))
runkernel generic_kc705_defconfig ml605 dc233c ml605 128M rootfs.cpio
retcode=$((${retcode} + $?))
runkernel generic_kc705_defconfig kc705 dc233c kc705 1G rootfs.cpio
retcode=$((${retcode} + $?))
runkernel nommu_kc705_defconfig kc705_nommu de212 kc705-nommu 256M rootfs-nommu.cpio
retcode=$((${retcode} + $?))

exit ${retcode}
