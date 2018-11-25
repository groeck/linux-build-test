#!/bin/bash

shopt -s extglob

dir=$(cd $(dirname $0); pwd)
. ${dir}/../scripts/config.sh
. ${dir}/../scripts/common.sh

parse_args "$@"
shift $((OPTIND - 1))

mach=$1
variant=$2

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-ppc64}

# machine specific information
ARCH=powerpc

rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
case "${rel}" in
v3.16|v3.18)
	PATH_PPC=/opt/poky/1.5.1/sysroots/x86_64-pokysdk-linux/usr/bin/powerpc64-poky-linux
	PREFIX=powerpc64-poky-linux-
	;;
*)
	# PATH_PPC=/opt/kernel/gcc-7.3.0-nolibc/powerpc64-linux/bin
	PATH_PPC=/opt/kernel/powerpc64/gcc-6.5.0/bin
	PREFIX=powerpc64-linux-
	;;
esac

PATH=${PATH_PPC}:${PATH}
dir=$(cd $(dirname $0); pwd)

. ${dir}/../scripts/common.sh

skip_316="mac99:qemu_ppc64_book3s_defconfig:smp:scsi[DC395]:rootfs \
	powernv:powernv_defconfig:initrd \
	ppce500:corenet64_smp_defconfig:e5500:sata:rootfs \
	ppce500:corenet64_smp_defconfig:e5500:scsi:rootfs \
	pseries:pseries_defconfig:sata-sii3112:rootfs \
	pseries:pseries_defconfig:little:initrd \
	pseries:pseries_defconfig:little:scsi:rootfs \
	pseries:pseries_defconfig:little:sata-sii3112:rootfs \
	pseries:pseries_defconfig:little:scsi[MEGASAS]:rootfs \
	pseries:pseries_defconfig:little:scsi[FUSION]:rootfs \
	pseries:pseries_defconfig:little:mmc:rootfs \
	pseries:pseries_defconfig:little:nvme:rootfs"
skip_318="mac99:qemu_ppc64_book3s_defconfig:smp:scsi[DC395]:rootfs \
	powernv:powernv_defconfig:initrd \
	ppce500:corenet64_smp_defconfig:e5500:sata:rootfs \
	ppce500:corenet64_smp_defconfig:e5500:scsi:rootfs \
	pseries:pseries_defconfig:sata-sii3112:rootfs \
	pseries:pseries_defconfig:little:initrd \
	pseries:pseries_defconfig:little:scsi:rootfs \
	pseries:pseries_defconfig:little:sata-sii3112:rootfs \
	pseries:pseries_defconfig:little:scsi[MEGASAS]:rootfs \
	pseries:pseries_defconfig:little:scsi[FUSION]:rootfs \
	pseries:pseries_defconfig:little:mmc:rootfs \
	pseries:pseries_defconfig:little:nvme:rootfs"
skip_44="powernv:powernv_defconfig:initrd \
	pseries:pseries_defconfig:sata-sii3112:rootfs \
	pseries:pseries_defconfig:little:initrd \
	pseries:pseries_defconfig:little:scsi:rootfs \
	pseries:pseries_defconfig:little:sata-sii3112:rootfs \
	pseries:pseries_defconfig:little:scsi[MEGASAS]:rootfs \
	pseries:pseries_defconfig:little:scsi[FUSION]:rootfs \
	pseries:pseries_defconfig:little:mmc:rootfs \
	pseries:pseries_defconfig:little:nvme:rootfs"
skip_49="pseries:pseries_defconfig:sata-sii3112:rootfs \
	pseries:pseries_defconfig:little:sata-sii3112:rootfs"

patch_defconfig()
{
    local defconfig=$1
    local fixups=${2//:/ }
    local fixup

    for fixup in ${fixups}; do
	if [ "${fixup}" = "e5500" ]; then
	    echo "CONFIG_E5500_CPU=y" >> ${defconfig}
	    echo "CONFIG_PPC_QEMU_E500=y" >> ${defconfig}
	fi

	if [ "${fixup}" = "little" ]; then
	    echo "CONFIG_CPU_BIG_ENDIAN=n" >> ${defconfig}
	    echo "CONFIG_CPU_LITTLE_ENDIAN=y" >> ${defconfig}
	fi
    done

    # extra SATA config
    echo "CONFIG_SATA_SIL=y" >> ${defconfig}
}

runkernel()
{
    local defconfig=$1
    local fixup=$2
    local machine=$3
    local cpu=$4
    local console=$5
    local kernel=$6
    local rootfs=$7
    local reboot=$8
    local dt_cmd="${9:+-machine ${9}}"
    local pid
    local logfile="$(__mktemp)"
    local waitlist=("Restarting system" "Restarting" "Boot successful" "Rebooting")
    local buildconfig="${machine}:${defconfig}"
    local build="${machine}:${defconfig}"

    if [ -n "${fixup}" ]; then
	build+=":${fixup}"
	buildconfig+="${fixup//smp*/smp}"
    fi

    if [[ "${rootfs%.gz}" == *cpio ]]; then
	build+=":initrd"
    else
	build+=":rootfs"
    fi

    local msg="ppc64:${build}"

    if ! match_params "${mach}@${machine}" "${variant}@${fixup}"; then
	echo "Skipping ${msg} ... "
	return 0
    fi

    echo -n "Building ${msg} ... "

    if ! checkskip "${build}"; then
	return 0
    fi

    if ! dosetup -c "${buildconfig}" -F "${fixup:-fixup}" "${rootfs}" "${defconfig}"; then
	if [[ __dosetup_rc -eq 2 ]]; then
	    return 0
	fi
	return 1
    fi

    echo -n "running ..."

    mem=1G
    if [[ "${machine}" = "powernv" ]]; then
	mem=2G
    fi

    if [[ "${machine}" == "ppce500" ]]; then
	extra_params+=" -device e1000e"
    fi

    [[ ${dodebug} -ne 0 ]] && set -x

    ${QEMU} -M ${machine} -cpu ${cpu} -m ${mem} \
	-kernel ${kernel} \
	${extra_params} \
	-nographic -vga none -monitor null -no-reboot \
	--append "${initcli} console=tty console=${console}" \
	${dt_cmd} > ${logfile} 2>&1 &
    pid=$!

    [[ ${dodebug} -ne 0 ]] && set +x

    dowait ${pid} ${logfile} ${reboot} waitlist[@]
    return $?
}

echo "Build reference: $(git describe)"
echo

runkernel qemu_ppc64_book3s_defconfig nosmp mac99 ppc64 ttyS0 vmlinux \
	rootfs.cpio.gz manual
retcode=$?
runkernel qemu_ppc64_book3s_defconfig smp mac99 ppc64 ttyS0 vmlinux \
	rootfs.cpio.gz manual
retcode=$((${retcode} + $?))
runkernel qemu_ppc64_book3s_defconfig smp:ide mac99 ppc64 ttyS0 vmlinux \
	rootfs.ext2.gz manual
retcode=$((${retcode} + $?))
runkernel qemu_ppc64_book3s_defconfig smp:mmc mac99 ppc64 ttyS0 vmlinux \
	rootfs.ext2.gz manual
retcode=$((${retcode} + $?))
# Upstream qemu generates a traceback during reboot.
# irq 30: nobody cared (try booting with the "irqpoll" option)
runkernel qemu_ppc64_book3s_defconfig smp:nvme mac99 ppc64 ttyS0 vmlinux \
	rootfs.ext2.gz manual
retcode=$((${retcode} + $?))
runkernel qemu_ppc64_book3s_defconfig smp:scsi[DC395] mac99 ppc64 ttyS0 vmlinux \
	rootfs.ext2.gz manual
retcode=$((${retcode} + $?))
runkernel pseries_defconfig "" pseries POWER8 hvc0 vmlinux \
	rootfs.cpio.gz auto
retcode=$((${retcode} + $?))
runkernel pseries_defconfig scsi pseries POWER9 hvc0 vmlinux \
	rootfs.ext2.gz auto
retcode=$((${retcode} + $?))
runkernel pseries_defconfig mmc pseries POWER9 hvc0 vmlinux \
	rootfs.ext2.gz auto
retcode=$((${retcode} + $?))
runkernel pseries_defconfig nvme pseries POWER9 hvc0 vmlinux \
	rootfs.ext2.gz auto
retcode=$((${retcode} + $?))
runkernel pseries_defconfig sata-sii3112 pseries POWER9 hvc0 vmlinux \
	rootfs.ext2.gz auto
retcode=$((${retcode} + $?))
runkernel pseries_defconfig little pseries POWER9 hvc0 vmlinux \
	rootfs-el.cpio.gz auto
retcode=$((${retcode} + $?))
runkernel pseries_defconfig little:scsi pseries POWER8 hvc0 vmlinux \
	rootfs-el.ext2.gz auto
retcode=$((${retcode} + $?))
runkernel pseries_defconfig little:sata-sii3112 pseries POWER8 hvc0 vmlinux \
	rootfs-el.ext2.gz auto
retcode=$((${retcode} + $?))
runkernel pseries_defconfig little:scsi[MEGASAS] pseries POWER8 hvc0 vmlinux \
	rootfs-el.ext2.gz auto
retcode=$((${retcode} + $?))
runkernel pseries_defconfig little:scsi[FUSION] pseries POWER8 hvc0 vmlinux \
	rootfs-el.ext2.gz auto
retcode=$((${retcode} + $?))
runkernel pseries_defconfig little:mmc pseries POWER8 hvc0 vmlinux \
	rootfs-el.ext2.gz auto
retcode=$((${retcode} + $?))
runkernel pseries_defconfig little:nvme pseries POWER8 hvc0 vmlinux \
	rootfs-el.ext2.gz auto
retcode=$((${retcode} + $?))
runkernel qemu_ppc64_e5500_defconfig nosmp mpc8544ds e5500 ttyS0 \
	arch/powerpc/boot/uImage \
	../ppc/rootfs.cpio.gz auto "dt_compatible=fsl,,P5020DS"
retcode=$((${retcode} + $?))
runkernel qemu_ppc64_e5500_defconfig smp mpc8544ds e5500 ttyS0 \
	arch/powerpc/boot/uImage \
	../ppc/rootfs.cpio.gz auto "dt_compatible=fsl,,P5020DS"
retcode=$((${retcode} + $?))
runkernel corenet64_smp_defconfig e5500 ppce500 e5500 ttyS0 \
	arch/powerpc/boot/uImage rootfs.cpio.gz auto
retcode=$((${retcode} + $?))
runkernel corenet64_smp_defconfig e5500:nvme ppce500 e5500 ttyS0 \
	arch/powerpc/boot/uImage rootfs.ext2.gz auto
retcode=$((${retcode} + $?))
runkernel corenet64_smp_defconfig e5500:mmc ppce500 e5500 ttyS0 \
	arch/powerpc/boot/uImage rootfs.ext2.gz auto
retcode=$((${retcode} + $?))
runkernel corenet64_smp_defconfig e5500:scsi[53C895A] ppce500 e5500 ttyS0 \
	arch/powerpc/boot/uImage rootfs.ext2.gz auto
retcode=$((${retcode} + $?))
runkernel corenet64_smp_defconfig e5500:sata-sii3112 ppce500 e5500 ttyS0 \
	arch/powerpc/boot/uImage rootfs.ext2.gz auto
retcode=$((${retcode} + $?))
runkernel powernv_defconfig "" powernv POWER8 hvc0 \
	arch/powerpc/boot/zImage.epapr rootfs-el.cpio.gz manual
retcode=$((${retcode} + $?))

exit ${retcode}
