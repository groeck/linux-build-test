#!/bin/bash

dir=$(cd $(dirname $0); pwd)
. "${dir}/../scripts/common.sh"

QEMU=${QEMU:-${QEMU_BIN}/qemu-system-xtensa}

parse_args "$@"
shift $((OPTIND - 1))

machine=$1
_cpu=$2
config=$3

PREFIX=xtensa-linux-
ARCH=xtensa
if [[ ${linux_version_code} -ge $(kernel_version 6 1) ]]; then
    PATH_XTENSA=/opt/kernel/xtensa/gcc-13.3.0-dc233c/usr/bin
else
    PATH_XTENSA=/opt/kernel/xtensa/gcc-6.3.0-dc233c/usr/bin
fi

PATH=${PATH_XTENSA}:${PATH}

patch_defconfig()
{
    local defconfig=$1
    local fixups=${2//:/ }
    local fixup

    # We need to have the following configuration options enabled
    # to be able to boot from flash.
    echo "CONFIG_MTD_BLOCK=y" >> ${defconfig}
    echo "CONFIG_MTD_PHYSMAP=y" >> ${defconfig}
    echo "CONFIG_MTD_PHYSMAP_OF=y" >> ${defconfig}

    for fixup in ${fixups}; do
        case "${fixup}" in
        dc232b)
	    sed -i -e '/CONFIG_XTENSA_VARIANT/d' ${defconfig}
	    echo "CONFIG_XTENSA_VARIANT_DC232B=y" >> ${defconfig}
	    echo "CONFIG_INITIALIZE_XTENSA_MMU_INSIDE_VMLINUX=n" >> ${defconfig}
	    echo "CONFIG_KERNEL_LOAD_ADDRESS=0xd0003000" >> ${defconfig}
	    ;;
        dc233c)
	    sed -i -e '/CONFIG_XTENSA_VARIANT/d' ${defconfig}
	    echo "CONFIG_XTENSA_VARIANT_DC233C=y" >> ${defconfig}
	    ;;
        *)
	    ;;
        esac
    done

    # No built-in initrd
    sed -i -e '/CONFIG_INITRAMFS_SOURCE/d' ${defconfig}
}

runkernel()
{
    local defconfig=$1
    local dts="arch/xtensa/boot/dts/$2.dts"
    local cpu=$3
    local mach=$4
    local fixup="${cpu}:${5}"
    local rootfs=$6
    local waitlist=("Restarting system" "Boot successful" "Rebooting")
    local pbuild="${ARCH}:${cpu}:${mach}:${defconfig}"
    local earlycon
    local image
    local dtb
    local dtbcmd

    if ! match_params "${machine}@${mach}" "${_cpu}@${cpu}" "${config}@${defconfig}"; then
	echo "Skipping ${pbuild} ... "
	return 0
    fi

    echo -n "Building ${pbuild} ... "

    if ! checkskip "${pbuild}"; then
	return 0;
    fi

    if ! dosetup -c "${defconfig}:${cpu}" -F "${fixup}" "${rootfs}" "${defconfig}"; then
	return 1
    fi

    dtb="$(gendtb "${dts}")"
    if [[ -n "${dtb}" ]]; then
	dtbcmd="-dtb ${dtb}"
    fi

    case "${mach}" in
    "virt")
	image="arch/xtensa/boot/Image.elf"
	extra_params+=" -semihosting"
	extra_params+=" -device virtio-rng-pci"
	extra_params+=" -device virtio-keyboard-pci"
	;;
    "lx200"|"lx60"|"kc705"|"ml605")
	image="arch/xtensa/boot/uImage"
	earlycon="earlycon=uart8250,mmio32,0xfd050020,115200n8"
	;;
    "kc705-nommu")
	image="arch/xtensa/boot/uImage"
	earlycon="earlycon=uart8250,mmio32,0x9d050020,115200n8 \
		memmap=256M@0x60000000"
	;;
    esac

    execute manual waitlist[@] \
      ${QEMU} -cpu ${cpu} -M ${mach} \
	-kernel "${image}" -no-reboot \
	${dtbcmd} \
	${extra_params} \
	--append "${initcli} ${earlycon} console=ttyS0,115200n8" \
	-nographic -monitor null -serial stdio

    return $?
}

build_reference "" "${QEMU}"

retcode=0
runkernel generic_kc705_defconfig lx60 dc232b lx60 nolocktests:mem128:net=default rootfs-dc232b.cpio
retcode=$((retcode + $?))
runkernel generic_kc705_defconfig lx60 dc232b lx200 nolocktests:mem128:flash16:net=default rootfs-dc232b.squashfs
retcode=$((retcode + $?))
runkernel generic_kc705_defconfig kc705 dc232b kc705 nolocktests:mem1G:net=default rootfs-dc232b.cpio
retcode=$((retcode + $?))
runkernel generic_kc705_defconfig kc705 dc232b kc705 nolocktests:mem1G:flash128:net=default rootfs-dc232b.ext2
retcode=$((retcode + $?))
runkernel generic_kc705_defconfig ml605 dc233c ml605 nolocktests:mem128:net=default rootfs-dc233c.cpio
retcode=$((retcode + $?))
runkernel generic_kc705_defconfig kc705 dc233c kc705 nolocktests:mem1G:net=default rootfs-dc233c.cpio
retcode=$((retcode + $?))

if [[ ${runall} -eq 1 ]]; then
    # Works but takes forever to run, and idle doesn't work well
    # (system runs at 100% CPU)
    runkernel virt_defconfig "" dc233c virt nolocktests:virtio-pci:mem2G rootfs-dc233c.ext2
    retcode=$((retcode + $?))
fi

runkernel generic_kc705_defconfig kc705 dc233c kc705 nolocktests:mem1G:flash128:net=default rootfs-dc233c.ext2
retcode=$((retcode + $?))

exit ${retcode}
