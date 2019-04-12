#!/bin/bash

# Set the following variable to true to skip DC395/AM53C97 build tests
__skip_dc395=0

shopt -s extglob

__logfiles=$(mktemp "/tmp/logfiles.XXXXXX")
__progdir="$(cd $(dirname $0); pwd)"
__basedir="${__progdir}/.."
. "${__basedir}/scripts/config.sh"

if [[ -w /var/cache/buildbot ]]; then
    __cachedir="/var/cache/buildbot/$(basename ${__progdir})"
else
    __cachedir="/tmp/buildbot-cache/$(basename ${__progdir})"
fi

__addtmpfile()
{
    echo "$1" >> "${__logfiles}"
}

__cleanup()
{
    rv=$?

    if [[ -s "${__logfiles}" ]]; then
	rm -f $(cat "${__logfiles}")
    fi
    rm -f "${__logfiles}"

    exit ${rv}
}

# run mktemp with provided parameters and queue generated file
# for auto-removal
__mktemp()
{
    local tmpfile="$(mktemp $*)"

    __addtmpfile "${tmpfile}"
    echo "${tmpfile}"
}

trap __cleanup EXIT SIGHUP SIGINT SIGQUIT SIGILL SIGTRAP SIGABRT

# Common variables used for waiting

LOOPTIME=5	# Wait time before checking status
MAXTIME=150	# Maximum wait time for qemu session to complete

# We run multiple builds at a time
# maxload=$(($(nproc) * 3 / 2))
maxload=$(nproc)

checkstate()
{
    if [[ ${testbuild} != 0 && $1 != 0 ]]; then
	exit $1
    fi
}

# Parse arguments and set global flags.
# The caller has to execute "shift $((OPTIND - 1).
parse_args()
{
	nobuild=0
	dodebug=0
	runall=0
	testbuild=0
	extracli=""
	while getopts ae:dnt opt; do
	case ${opt} in
	a)	runall=1;;
	d)	dodebug=1;;
	e)	extracli=${OPTARG};;
	n)	nobuild=1;;
	t)	testbuild=1;;
	*)	echo "Bad option ${opt}"; exit 1;;
	esac
	done
}

__common_scsicmd()
{
    local fixup="$1"
    local rootfs="$2"
    local device
    local sdevice
    local wwn
    local iface
    local media

    case "${fixup}" in
    "scsi")	# Standard SCSI controller provided by platform
	iface="scsi"
	;;
    "scsi[53C810]")
	device="lsi53c810"
	;;
    "scsi[53C895A]")
	device="lsi53c895a"
	;;
    "scsi[DC395]")
	device="dc390"
	;;
    "scsi[AM53C974]")
	device="am53c974"
	;;
    "scsi[MEGASAS]")
	device="megasas"
	;;
    "scsi[MEGASAS2]")
	device="megasas-gen2"
	;;
    "scsi[FUSION]")
	device="mptsas1068"
	# wwn (World Wide Name) is mandatory for this device
	wwn="0x5000c50015ea71ac"
	;;
    "scsi[virtio]")
	device="virtio-scsi-device"
	;;
    "scsi[virtio-pci]")
	device="virtio-scsi-pci"
	;;
    "scsi[virtio-ccw]")
	# s390 only
	device="virtio-scsi-ccw,devno=fe.0.0001"
	;;
    *)
	;;
    esac

    if [[ "${rootfs}" == *iso ]]; then
	initcli+=" root=/dev/sr0"
	media="cdrom"
	sdevice="scsi-cd"
    else
	initcli+=" root=/dev/sda"
	sdevice="scsi-hd"
    fi

    extra_params+=" ${device:+-device ${device},id=scsi}${__pcibus}"
    extra_params+=" ${device:+-device ${sdevice},bus=scsi.0,drive=d0${wwn:+,wwn=${wwn}}}"
    extra_params+=" -drive file=${rootfs},format=raw,if=${iface:-none}${device:+,id=d0}"
    extra_params+="${media:+,media=${media}}"
}

__common_usbcmd()
{
    local fixup="$1"
    local rootfs="$2"

    case "${fixup}" in
    "usb-ohci")
	extra_params+=" -usb -device pci-ohci,id=ohci${__pcibus}"
	extra_params+=" -device usb-storage,bus=ohci.0,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "usb-ehci")
	extra_params+=" -usb -device usb-ehci,id=ehci${__pcibus}"
	extra_params+=" -device usb-storage,bus=ehci.0,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "usb-xhci")
	extra_params+=" -usb -device qemu-xhci,id=xhci${__pcibus}"
	extra_params+=" -device usb-storage,bus=xhci.0,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "usb")
	extra_params+=" -usb -device usb-storage,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "usb-hub")
	extra_params+=" -usb -device usb-hub,bus=usb-bus.0,port=2"
	extra_params+=" -device usb-storage,bus=usb-bus.0,port=2.1,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "usb-uas-ehci")
	extra_params+=" -usb -device usb-ehci,id=ehci${__pcibus}"
	extra_params+=" -device usb-uas,bus=ehci.0,id=uas"
	extra_params+=" -device scsi-hd,bus=uas.0,scsi-id=0,lun=0,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,format=raw,id=d0"
	;;
    "usb-uas-xhci")
	extra_params+=" -usb -device qemu-xhci,id=xhci${__pcibus}"
	extra_params+=" -device usb-uas,bus=xhci.0,id=uas"
	extra_params+=" -device scsi-hd,bus=uas.0,scsi-id=0,lun=0,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,format=raw,id=d0"
	;;
    "usb-uas")
	extra_params+=" -usb -device usb-uas,id=uas"
	extra_params+=" -device scsi-hd,bus=uas.0,scsi-id=0,lun=0,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,format=raw,id=d0"
	;;
    *)
	;;
    esac

    initcli+=" root=/dev/sda rootwait"
}

__common_virtcmd()
{
    local fixup="$1"
    local rootfs="$2"

    case "${fixup}" in
    "virtio-blk-ccw")
	# s390 only
	extra_params+=" -device virtio-blk-ccw,devno=fe.0.0001,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "virtio-blk")
	extra_params+=" -device virtio-blk-device,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "virtio-pci")
	extra_params+=" -device virtio-blk-pci,drive=d0${__pcibus}"
	extra_params+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "virtio")
	extra_params+=" -drive file=${rootfs},if=virtio,format=raw"
	;;
    *)
	;;
    esac

    initcli+=" root=/dev/vda"
}

__common_mmccmd()
{
    local fixup="$1"
    local rootfs="$2"

    case "${fixup}" in
    "mmc")
	extra_params+=" -device sdhci-pci${__pcibus} -device sd-card,drive=d0"
	extra_params+=" -drive file=${rootfs},format=raw,if=none,id=d0"
	;;
    "sd")	# similar to mmc, but does not need sdhci-pci
	extra_params+=" -drive file=${rootfs},format=raw,if=sd"
	;;
    "sd1")	# sd at index 1
	extra_params+=" -drive file=${rootfs},format=raw,if=sd,index=1"
	;;
    *)
	;;
    esac

    initcli+=" root=/dev/mmcblk0 rootwait"
}

__common_satacmd()
{
    local fixup="$1"
    local rootfs="$2"
    local idedevice
    local media
    local rootdev
    local satadev

    if [[ "${rootfs}" == *iso ]]; then
	media="cdrom"
	idedevice="ide-cd"
	rootdev="sr0"
    else
	idedevice="ide-hd"
	rootdev="sda"
    fi

    case "${fixup}" in
    "sata-sii3112")
	# generic sata drive provided by SII3112 SATA controller
	# Available on ppc
	satadev="sii3112"
	;;
    "sata-cmd646")
	# generic sata drive provided by CMD646 PCI ATA/SATA controller
	# Available on alpha, parisc, sparc64
	satadev="cmd646-ide"
	;;
    "sata")	# generic sata drive, pre-existing bus
	;;
    *)
	;;
    esac
    extra_params+="${satadev:+ -device ${satadev},id=ata}"
    extra_params+=" -device ${idedevice}${satadev:+,bus=ata.0},drive=d0"
    extra_params+=" -drive file=${rootfs},if=none,id=d0,format=raw"
    extra_params+="${media:+,media=${media}}"
    initcli+=" root=/dev/${rootdev}"
}

__common_diskcmd()
{
    local fixup="$1"
    local rootfs="$2"
    local media
    local hddev

    case "${ARCH}" in
    sparc64)
	__pcibus=",bus=pciB"
	;;
    *)
	__pcibus=""
	;;
    esac

    if [[ "${rootfs}" == *iso ]]; then
	media="cdrom"
	hddev="sr0"
    else
	hddev="sda"
    fi

    case "${fixup}" in
    "ata")
	# standard ata/sata drive provided by platform
	initcli+=" root=/dev/${hddev}"
	extra_params+=" -drive file=${rootfs},format=raw,if=ide${media:+,media=${media}}"
	;;
    "ide")
	# standard ide/ata/sata drive provided by platform
	# The actual configuration determines if the root file system
	# is /dev/sda (CONFIG_ATA) or /dev/hda (CONFIG_IDE).
	# With CONFIG_IDE, the device is /dev/hda for both hdd and cdrom.
	if ! grep -q "CONFIG_ATA=y" .config; then
	    hddev="hda"
	fi
	initcli+=" root=/dev/${hddev}"
	extra_params+=" -drive file=${rootfs},format=raw,if=ide${media:+,media=${media}}"
	;;
    "mmc"|"sd"|"sd1")
	__common_mmccmd "${fixup}" "${rootfs}"
	;;
    "nvme")
	initcli+=" root=/dev/nvme0n1 rootwait"
	extra_params+=" -device nvme,serial=foo,drive=d0${__pcibus}"
	extra_params+=" -drive file=${rootfs},if=none,format=raw,id=d0"
	;;
    "sata-sii3112"|"sata-cmd646"|"sata")
	__common_satacmd "${fixup}" "${rootfs}"
	;;
    scsi*)
	__common_scsicmd "${fixup}" "${rootfs}"
	;;
    usb*)
	__common_usbcmd "${fixup}" "${rootfs}"
	;;
    virtio*)
	__common_virtcmd "${fixup}" "${rootfs}"
	;;
    *)
	;;
    esac
}

__common_fixup()
{
    local fixup="${1}"
    local rootfs="${2}"

    case "${fixup}" in
    "mmc"|"sd"|"sd1"|"nvme"|\
    "ide"|"ata"|sata*|usb*|scsi*|virtio*)
	__common_diskcmd "${fixup}" "${rootfs}"
	;;
    pci*)
	# __common_pcicmd "${fixup}" "${rootfs}"
	;;
    net*)
	# __common_netcmd "${fixup}" "${rootfs}"
	;;
    smp[1-9])
	extra_params+=" -smp ${fixup#smp}"
	;;
    efi|efi64)
	extra_params+=" -bios ${__basedir}/firmware/OVMF-pure-efi-64.fd"
	;;
    efi32)
	extra_params+=" -bios ${__basedir}/firmware/OVMF-pure-efi-32.fd"
	;;
    mem*)
	extra_params+=" -m ${fixup#mem}"
	;;
    *)
	;;
    esac
}

# Handle common fixups.
# Populate "initcli" and "extra_params".
__common_fixups()
{
    local fixups="${1//:/ }"
    local rootfs="$2"
    local fixup

    initcli="panic=-1 ${config_initcli}"
    extra_params="-snapshot"

    if [[ -z "${fixups}" ]]; then
	return
    fi

    if [[ "${rootfs}" == *cpio ]]; then
	initcli+=" rdinit=/sbin/init"
	# initrd doesn't need snapshot
	extra_params="-initrd ${rootfs}"
	rootfs=""
    fi

    for fixup in ${fixups}; do
	__common_fixup "${fixup}" "${rootfs}"
    done

    # trim leading whitespaces, if any
    initcli="${initcli##*( )}"
    extra_params="${extra_params##*( )}"
}

# Set globals diskcmd and initcli variables
# using common fixup strings.
# Supports:
# - initrd / rootfs separation
# - mmc/sd/sd1
#   Difference: mmc instantiates sdhci-pci; sd/sd1 doesn't.
#   sd1 instantiates the drive at index 1.
# - ata/sata/sata-cmd646
#   Difference: sata instantiates ide-hd, ata doesn't.
#   sata-cmd646 also instantiates cmd-646 (a PCI sata/ide controller)
# - nvme
# - ata/sata
# - scsi
# - usb, usb-xhci, usb-ehci
#   Difference: usb-xhci enables usb and instantiates qemu-xhci
# - usb-uas, usb-uas-xhci
#   Difference: same as above.
common_diskcmd()
{
    local fixup="$1"
    local rootfs="$2"

    if [[ "${rootfs}" == *cpio ]]; then
	initcli="rdinit=/sbin/init"
	diskcmd="-initrd ${rootfs}"
	return 0
    fi

    extra_params=""
    initcli=""
    __common_diskcmd "${fixup}" "${rootfs}"
    diskcmd="${extra_params}"
    if [ -z "${initcli}" ]; then
	initcli="root=/dev/sda"
    fi
}

dokill()
{
	local pid=$1
	local i

	kill ${pid} >/dev/null 2>&1
	# give it a few seconds to die, then kill it
	# the hard way if it did not work.
	for i in $(seq 1 5)
	do
	    sleep 1
	    kill -0 ${pid} >/dev/null 2>&1
	    if [ $? -ne 0 ]
	    then
		return
	    fi
	done
	kill -9 ${pid} >/dev/null 2>&1
}

doclean()
{
	local ARCH=$1

	pwd | grep buildbot >/dev/null 2>&1
	if [ $? -eq 0 ]
	then
		git clean -x -d -f -q
	else
		make ARCH=${ARCH} mrproper >/dev/null 2>&1
	fi
}

rootfsname()
{
    rootfs="$(basename $1)"
    echo "${__cachedir}/${rootfs%.gz}"
}

setup_rootfs()
{
    local dynamic=""

    OPTIND=1
    while getopts d opt
    do
	case ${opt} in
	d) dynamic="yes";;
	*) ;;
	esac
    done

    shift $((OPTIND - 1))

    local rootfs=$1
    local rootfspath="${__progdir}/${rootfs}"
    if [[ ! -e "${rootfspath}" && -e "${rootfspath}.gz" ]]; then
	rootfs="${rootfs}.gz"
	rootfspath="${rootfspath}.gz"
    fi

    local destfile="$(rootfsname ${rootfs})"

    mkdir -p "${__cachedir}"

    # Do nothing if file checksums exist and match.
    # Checksums are copied, not regenerated, so that should always work even
    # if the destination has been decompressed or dynamically modified.
    if cmp -s "${rootfspath}.md5" "${destfile}.md5"; then
	echo "${destfile}"
	return
    fi

    # If we get here, clean up the cache first.
    rm -f "${destfile}" "${destfile}.md5"

    cp "${rootfspath}" "${__cachedir}"
    if [[ "${rootfs}" == *.gz ]]; then
	gunzip -f "${destfile}.gz"
	rootfs="${rootfs%.gz}"
    fi

    if [[ -n "${dynamic}" && "${rootfs}" == *cpio ]]; then
	fakeroot ${__basedir}/scripts/genrootfs.sh "${__progdir}" "${destfile}"
    fi

    if [[ -e "${rootfspath}.md5" ]]; then
	cp "${rootfspath}.md5" "${destfile}.md5"
    fi

    # Cached files must not be modified.
    chmod 444 "${destfile}"
    if [[ -e "${destfile}.md5" ]]; then
	chmod 444 "${destfile}.md5"
    fi
    echo "${destfile}"
}

__setup_config()
{
    local defconfig="$1"
    local fragment="$2"
    local fixup="$3"
    local rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
    local arch
    local target

    case ${ARCH} in
    mips32|mips64)
	arch=mips;;
    crisv32)
	arch=cris;;
    m68k_nommu)
	arch=m68k;;
    parisc64)
	arch=parisc;;
    sparc64|sparc32)
	arch=sparc;;
    x86_64)
	arch=x86;;
    *)
	arch=${ARCH};;
    esac

    if [ -e ${__progdir}/${defconfig} ]; then
	mkdir -p arch/${arch}/configs
	cp ${__progdir}/${defconfig} arch/${arch}/configs
    fi

    make ARCH=${ARCH} CROSS_COMPILE=${PREFIX} ${defconfig} >/dev/null 2>&1 </dev/null
    if [ $? -ne 0 ]; then
	return 2
    fi

    # the configuration is in .config

    if [ -n "${fragment}" ]; then
	cat "${fragment}" >> .config
    fi

    if [ -n "${fixup}" ]; then
	patch_defconfig .config "${fixup}"
    fi
    if [ -n "${fixup}${fragment}" ]; then
	target="olddefconfig"
	if [[ "${rel}" = "v3.16" ]]; then
	    target="oldconfig"
	fi
	if ! make ARCH=${ARCH} CROSS_COMPILE=${PREFIX} ${target} >/dev/null 2>&1 </dev/null; then
	    return 1
	fi
    fi
    return 0
}

__setup_fragment()
{
    local fragment="$1"
    local fixups="${2//:/ }"
    local fixup
    local nodebug=0
    local nofs=0
    local nolocktests=0
    local noscsi=0
    local notests=0
    local nousb=0
    local novirt=0
    local preempt=0

    rm -f "${fragment}"
    touch "${fragment}"

    for fixup in ${fixups}; do
	case "${fixup}" in
	"nosmp")
	    echo "CONFIG_SMP=n" >> ${fragment}
	    ;;
	smp*)
	    echo "CONFIG_SMP=y" >> ${fragment}
	    ;;
	nodebug) nodebug=1 ;;
	nofs) nofs=1 ;;
	nolocktests) nolocktests=1 ;;
	noscsi) noscsi=1 ;;
	notests) notests=1 ;;
	nousb) nousb=1 ;;
	novirt) novirt=1 ;;
	preempt) preempt=1 ;;
	*)
	    ;;
	esac
    done

    if [[ "${nodebug}" -eq 0 ]]; then
	# debug options
	echo "CONFIG_EXPERT=y" >> ${fragment}
	echo "CONFIG_DEBUG_KERNEL" >> ${fragment}
	echo "CONFIG_LOCK_DEBUGGING_SUPPORT" >> ${fragment}
	echo "CONFIG_DEBUG_RT_MUTEXES=y" >> ${fragment}
	echo "CONFIG_DEBUG_SPINLOCK=y" >> ${fragment}
	echo "CONFIG_DEBUG_MUTEXES=y" >> ${fragment}
	echo "CONFIG_DEBUG_WW_MUTEX_SLOWPATH=y" >> ${fragment}
	echo "CONFIG_DEBUG_LOCK_ALLOC=y" >> ${fragment}
	echo "CONFIG_DEBUG_LOCKDEP=y" >> ${fragment}
	echo "CONFIG_DEBUG_ATOMIC_SLEEP=y" >> ${fragment}
	echo "CONFIG_DEBUG_LIST=y" >> ${fragment}
    fi

    if [[ "${notests}" -eq 0 ]]; then
	# selftests
	echo "CONFIG_CRYPTO_MANAGER_DISABLE_TESTS=n" >> ${fragment}
	echo "CONFIG_CRC32_SELFTEST=y" >> ${fragment}
	echo "CONFIG_DEBUG_LOCKING_API_SELFTESTS=y" >> ${fragment}
	echo "CONFIG_DEBUG_NMI_SELFTEST=y" >> ${fragment}
	echo "CONFIG_DEBUG_RODATA_TEST=y" >> ${fragment}
	echo "CONFIG_DEBUG_TLBFLUSH=y" >> ${fragment}
	echo "CONFIG_DMATEST=y" >> ${fragment}
	echo "CONFIG_GLOB_SELFTEST=y" >> ${fragment}
	echo "CONFIG_OF_UNITTEST=y" >> ${fragment}
	echo "CONFIG_PCI_EPF_TEST=y" >> ${fragment}
	echo "CONFIG_PCI_ENDPOINT_TEST=y" >> ${fragment}
	echo "CONFIG_RCU_EQS_DEBUG=y" >> ${fragment}
	echo "CONFIG_STATIC_KEYS_SELFTEST=y" >> ${fragment}
	echo "CONFIG_STRING_SELFTEST=y" >> ${fragment}
	echo "CONFIG_TEST_BITMAP=y" >> ${fragment}
	echo "CONFIG_TEST_FIRMWARE=y" >> ${fragment}
	# takes too long
	# echo "CONFIG_TEST_RHASHTABLE=y" >> ${fragment}
	echo "CONFIG_TEST_SORT=y" >> ${fragment}
	echo "CONFIG_TEST_SYSCTL=y" >> ${fragment}
	echo "CONFIG_TEST_UUID=y" >> ${fragment}
	echo "CONFIG_USB_TEST=y" >> ${fragment}
	echo "CONFIG_USB_EHSET_TEST_FIXTURE=y" >> ${fragment}
	echo "CONFIG_USB_LINK_LAYER_TEST=y" >> ${fragment}

	if [[ "${nolocktests}" -eq 0 ]]; then
	    echo "CONFIG_PROVE_RCU=y" >> ${fragment}
	    echo "CONFIG_PROVE_LOCKING=y" >> ${fragment}
	    echo "CONFIG_WW_MUTEX_SELFTEST=y" >> ${fragment}
	    echo "CONFIG_TORTURE_TEST=y" >> ${fragment}
	    echo "CONFIG_LOCK_TORTURE_TEST=y" >> ${fragment}
	    echo "CONFIG_RCU_TORTURE_TEST=y" >> ${fragment}
	fi

	echo "CONFIG_RBTREE_TEST=y" >> ${fragment}
	echo "CONFIG_INTERVAL_TREE_TEST=y" >> ${fragment}
    fi

    # BLK_DEV_INITRD
    echo "CONFIG_BLK_DEV_INITRD=y" >> ${fragment}

    # DEVTMPFS
    echo "CONFIG_DEVTMPFS=y" >> ${fragment}
    echo "CONFIG_DEVTMPFS_MOUNT=y" >> ${fragment}

    if [[ "${noscsi}" -eq 0 ]]; then
	# SCSI and SCSI controller drivers
	echo "CONFIG_SCSI=y" >> ${fragment}
	echo "CONFIG_BLK_DEV_SD=y" >> ${fragment}
	echo "CONFIG_SCSI_LOWLEVEL=y" >> ${fragment}
	echo "CONFIG_SCSI_DC395x=y" >> ${fragment}
	echo "CONFIG_SCSI_AM53C974=y" >> ${fragment}
	echo "CONFIG_SCSI_SYM53C8XX_2=y" >> ${fragment}
	echo "CONFIG_MEGARAID_SAS=y" >> ${fragment}
	echo "CONFIG_FUSION=y" >> ${fragment}
	echo "CONFIG_FUSION_SAS=y" >> ${fragment}
    fi

    # MMC/SDHCI support
    echo "CONFIG_MMC=y" >> ${fragment}
    echo "CONFIG_MMC_SDHCI=y" >> ${fragment}
    echo "CONFIG_MMC_SDHCI_PCI=y" >> ${fragment}

    # NVME support
    echo "CONFIG_BLK_DEV_NVME=y" >> ${fragment}

    # CDROM support
    echo "CONFIG_BLK_DEV_SR=y" >> ${fragment}
    echo "CONFIG_ISO9660_FS=y" >> ${fragment}
    echo "CONFIG_CDROM=y" >> ${fragment}

    if [[ "${nousb}" -eq 0 ]]; then
	# USB support
	echo "CONFIG_USB=y" >> ${fragment}
	echo "CONFIG_USB_XHCI_HCD=y" >> ${fragment}
	echo "CONFIG_USB_EHCI_HCD=y" >> ${fragment}
	echo "CONFIG_USB_OHCI_HCD=y" >> ${fragment}
	echo "CONFIG_USB_STORAGE=y" >> ${fragment}
	echo "CONFIG_USB_UAS=y" >> ${fragment}
    fi

    if [[ "${novirt}" -eq 0 ]]; then
	# Virtualization
	echo "CONFIG_VIRTIO=y" >> ${fragment}
	echo "CONFIG_VIRTIO_PCI=y" >> ${fragment}
	echo "CONFIG_VIRTIO_PCI_LEGACY=y" >> ${fragment}
	echo "CONFIG_VIRTIO_BALLOON=y" >> ${fragment}
	echo "CONFIG_VIRTIO_MMIO=y" >> ${fragment}
	echo "CONFIG_BLK_MQ_VIRTIO=y" >> ${fragment}
	echo "CONFIG_VIRTIO_BLK=y" >> ${fragment}
	echo "CONFIG_VIRTIO_BLK_SCSI=y" >> ${fragment}
	echo "CONFIG_SCSI_VIRTIO=y" >> ${fragment}
    fi

    if [[ "${nofs}" -eq 0 ]]; then
	# file systems
	echo "CONFIG_BTRFS_FS=y" >> ${fragment}
	echo "CONFIG_SQUASHFS=y" >> ${fragment}
	echo "CONFIG_SQUASHFS_XATTR=y" >> ${fragment}
	echo "CONFIG_SQUASHFS_ZLIB=y" >> ${fragment}
	echo "CONFIG_SQUASHFS_4K_DEVBLK_SIZE=y" >> ${fragment}
	echo "CONFIG_EXT3_FS=y" >> ${fragment}
    fi

    if [[ "${preempt}" -eq 1 ]]; then
	echo "CONFIG_PREEMPT=y" >> ${fragment}
    fi
}

# match_params
# match sets of strings separated by '@'.
# The first string must be non-empty for a match,
# and may include wildcards.
# return 0 if match found, 1 otherwise
match_params()
{
    local check
    local rv=0

    for check in $*
    do
	if [[ -n "${check%@*}" ]]; then
	    local _check=(${check//@/ })
	    if [[ "${_check[1]}" != ${_check[0]} ]]; then
	        rv=1
		break
	    fi
	fi
    done
    return ${rv}
}

checkskip()
{
    local build=$1
    local rel=$(git describe | cut -f1 -d- | cut -f1,2 -d. | sed -e 's/\.//' | sed -e 's/v//')
    local tmp="skip_${rel}"
    local skip=(${!tmp})
    local s

    for s in ${skip[*]}; do
	if [ "$s" = "${build}" ]; then
	    echo "skipped"
	    return 2
	fi
    done
    return 0
}

__cached_config=""
__cached_results=0
__cached_reason=""

dosetup()
{
    local rv
    local logfile="$(__mktemp /tmp/build.XXXXX)"
    local rel=$(git describe | cut -f1 -d- | cut -f1,2 -d. | sed -e 's/\.//' | sed -e 's/v//')
    local build="${ARCH}:${defconfig}"
    local EXTRAS=""
    local fixup=""
    local fixups=""
    local dynamic=""
    local cached_config=""
    local fragment=""

    __dosetup_rc=0

    OPTIND=1
    while getopts c:b:de:f:F: opt
    do
	case ${opt} in
	b) build="${OPTARG}";;
	c) cached_config="${OPTARG}";;
	d) dynamic="-d";;
	e) EXTRAS="${OPTARG}";;
	f) fixup="${OPTARG}";;
	F) fixups="${OPTARG:-dummy}";;
	*) ;;
	esac
    done

    shift $((OPTIND - 1))

    local rootfs=$1
    local defconfig=$2

    # Hack: Tests involving DC395 and AM53C974 are just not stable.
    # Skip for now unless runall is set.
    if [[ "${__skip_dc395}" -ne 0 && \
		"${runall}" -eq 0 && ( \
		"${fixup}" = *DC395* || "${fixup}" = *AM53C974* || \
		"${fixups}" = *DC395* || "${fixups}" = *AM53C974* \
		) ]]; then
	echo "skipped"
	__dosetup_rc=2
	return 2
    fi

    # If nobuild is set, don't build image, just set up the root file
    # system as needed. Assumes that the image was built already in
    # a previous test run.
    if [ ${nobuild:-0} -ne 0 ]; then
	rootfs="$(setup_rootfs ${dynamic} ${rootfs})"
	__common_fixups "${fixups}" "${rootfs}"
	return 0
    fi

    if ! checkskip "${build}"; then
	# Don't update build cache information in this case because we
	# didn't do anything. Don't clear the cache either because it
	# might still be useful for a later build.
	__dosetup_rc=2
	return 2
    fi

    if [[ -n "${cached_config}" && "${cached_config}" == "${__cached_config}" ]]; then
	if [[ ${__cached_results} -ne 0 ]]; then
	    echo "${__cached_reason} (cached)"
	    __dosetup_rc=${__cached_results}
	    return ${__cached_results}
	fi
	rootfs="$(setup_rootfs ${dynamic} ${rootfs})"
	__common_fixups "${fixups}" "${rootfs}"
        [[ ${dodebug} -ne 0 ]] && echo -n "[cached] "
	return 0
    fi

    __cached_config="${cached_config}"
    __cached_results=0
    __cached_reason=""

    doclean ${ARCH}

    if [ -n "${fixups}" ]; then
	fragment="$(__mktemp /tmp/fragment.XXXXX)"
	__setup_fragment "${fragment}" "${fixups}"
    fi

    __setup_config "${defconfig}" "${fragment}" "${fixup:-${fixups}}"
    rv=$?
    if [ ${rv} -ne 0 ]
    then
	if [ ${rv} -eq 1 ]
	then
	    __cached_reason="failed (config)"
	else
	    __cached_reason="skipped"
	fi
	echo "${__cached_reason}"
	__cached_results=${rv}
	__dosetup_rc=${rv}
	return ${rv}
    fi

    rootfs="$(setup_rootfs ${dynamic} ${rootfs})"
    __common_fixups "${fixups}" "${rootfs}"

    make -j${maxload} ARCH=${ARCH} CROSS_COMPILE=${PREFIX} ${EXTRAS} >/dev/null 2>${logfile}
    rv=$?
    if [ ${rv} -ne 0 ]
    then
	__cached_reason="failed"
	echo "failed"
	echo "------------"
	echo "Error log:"
	cat ${logfile}
	echo "------------"
    fi

    __cached_results=${rv}
    __dosetup_rc=${rv}
    return ${rv}
}

dowait()
{
    local pid=$1
    local logfile=$2
    local manual=$3
    local waitlist=("${!4}")
    local entries=${#waitlist[*]}
    local retcode=0
    local t=0
    local i
    local msg="passed"
    local dolog

    while true
    do
	kill -0 ${pid} >/dev/null 2>&1
	if [ $? -ne 0 ]
	then
		break
	fi

	# If this qemu session doesn't stop by itself, help it along.
	# Assume first entry in waitlist points to the message
	# we are waiting for here.
	# We need to do this prior to checking for a crash since
	# some kernels _do_ crash on reboot (eg sparc64)

	if [ "${manual}" = "manual" ]
	then
	    grep "${waitlist[0]}" ${logfile} >/dev/null 2>&1
	    if [ $? -eq 0 ]
	    then
		dokill ${pid}
		break
	    fi
	fi

	egrep "Oops: |Kernel panic|Internal error:|segfault" ${logfile} >/dev/null 2>&1
	if [ $? -eq 0 ]
	then
	    # x86 has the habit of crashing in restart once in a while.
	    # Try to ignore it.
	    egrep "^machine restart" ${logfile} >/dev/null 2>&1
	    if [ $? -ne 0 ]
	    then
		msg="failed (crashed)"
		retcode=1
	    fi
	    dokill ${pid}
	    break
	fi

	if [ $t -gt ${MAXTIME} ]
	then
		msg="failed (timeout)"
		dokill ${pid}
		retcode=1
		break
	fi
	sleep ${LOOPTIME}
	t=$(($t + ${LOOPTIME}))
	echo -n .
    done

    if [ ${retcode} -eq 0 ]
    then
	for i in $(seq 0 $((${entries} - 1)))
	do
	    grep "${waitlist[$i]}" ${logfile} >/dev/null 2>&1
	    if [ $? -ne 0 ]
	    then
		msg="failed (No \"${waitlist[$i]}\" message in log)"
		retcode=1
		break
	    fi
	done
    fi

    echo " ${msg}"

    dolog=${retcode}
    if grep -q "\[ cut here \]" ${logfile}; then
	dolog=1
    fi
    if grep -q "\[ end trace [0-9a-f]* \]" ${logfile}; then
	dolog=1
    fi
    if grep -q "dump_stack" ${logfile}; then
	dolog=1
    fi
    if grep -q "stack backtrace" ${logfile}; then
	dolog=1
    fi

    if [ ${dolog} -ne 0 ]
    then
	echo "------------"
	echo "qemu log:"
	cat ${logfile}
	echo "------------"
    fi
    return ${retcode}
}
