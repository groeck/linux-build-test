#!/bin/bash

shopt -s extglob

ulimit -c unlimited

# limit file size to 2GB to prevent log file sizes from getting out of control.
# Note that the limit needs to be a bit larger than 1GB to accommodate 1GB
# flashes, and some arm64 builds need inexplicably more space when linking.
# Update 3/21/2024: loongarch on v6.8+ now needs more than 2GB for linking.
ulimit -f $((3000 * 1024))

__logfiles=$(mktemp "/tmp/logfiles.XXXXXX")
__progdir="$(cd $(dirname $0); pwd)"
__basedir="${__progdir}/.."
__swtpmdir=$(mktemp -d "/tmp/mytpmXXXXX")
__swtpmsock="${__swtpmdir}/swtpm-sock"
__swtpmpidfile="${__swtpmdir}/pid"
__qemu_builddir_default="$(mktemp -d "/tmp/qemuXXXXX")"
__qemu_builddir_static="/tmp/qemu_builddir"

. "${__basedir}/scripts/config.sh"

if [[ -w "/var/cache/buildbot" ]]; then
    __buildbot_cachedir="/var/cache/buildbot"
else
    __buildbot_cachedir="/tmp/buildbot-cache"
fi

__cachedir="${__buildbot_cachedir}/$(basename ${__progdir})"
__fscachedir="${__buildbot_cachedir}/filesystems"

__do_network_test=0
__do_tpm_test=0

__addtmpfile()
{
    echo "$1" >> "${__logfiles}"
}

__stop_tpm()
{
    local swtpmpid

    if [[ -s "${__swtpmpidfile}" ]]; then
	swtpmpid="$(cat "${__swtpmpidfile}")"
	# swtpm exits on its own when the emulation terminates.
	# Make sure that it is gone if it is still running for some reason.
	kill "${swtpmpid}"
    fi
    rm -f "${__swtpmpidfile}"
}

__set_qemu_builddir()
{
    qemu_builddir="$1"
    __config="${qemu_builddir}/.config"
}

__set_qemu_builddir_default()
{
    __set_qemu_builddir "${__qemu_builddir_default}"
}

__set_qemu_builddir_static()
{
    __set_qemu_builddir "${__qemu_builddir_static}"
}

__cleanup()
{
    rv=$?

    if [[ -s "${__logfiles}" ]]; then
	rm -f $(cat "${__logfiles}")
    fi
    rm -f "${__logfiles}"

    __stop_tpm
    if [[ -d "${__swtpmdir}" ]]; then
	rm -rf "${__swtpmdir}"
    fi
    if [[ -d "${__qemu_builddir_default}" ]]; then
	rm -rf "${__qemu_builddir_default}"
    fi

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

trap __cleanup EXIT SIGHUP SIGINT SIGQUIT SIGILL SIGTRAP SIGABRT SIGBUS SIGFPE SIGSEGV SIGALRM SIGTERM SIGPWR

# Common variables used for waiting

LOOPTIME=5	# Wait time before checking status
MAXTIME=180	# Maximum wait time for qemu session to complete
MAXSTIME=60	# Maximum wait time for qemu session to generate output
__retries=1	# Default number of retries

__testbuild=0	# test build, do not run tests
___testbuild=0	# test build, run tests but abort after first failure
_log_abort=0	# abort after warnings / backtraces
_log_always=0	# log always
_log_all=0	# log everything, not just part of the log

# We run multiple builds at a time
# maxload=$(($(nproc) * 3 / 2))
maxload=$(nproc)

# Display build reference. It assumes that the following
# environment variables are set:
# - PATH must include the path to gcc.
# Parameters:
# - C compiler (with prefix, must be in PATH)
#   C compiler version will not be displayed if parameter is not provided
# - QEMU command, full path
build_reference()
{
    local qemu_version="$($2 --version | head -n 1 | sed -e "s/.*version //")"

    echo "Build reference: $(git describe --match 'v*')"
    if [[ -n "$1" ]]; then
	local compiler_version="$($1 --version | head -n 1)"
	echo "Compiler version: ${compiler_version}"
    fi
    echo "Qemu version: ${qemu_version}"
    echo
}

# Find file in qemu build directory.
# Return path _without_ qemu build directory itself.
__findfile()
{
    local basedir="$1"
    local filename="$2"
    local pathname

    pathname="$(cd "${qemu_builddir}"; find "${basedir}" -name "${filename}")"

    echo "${pathname}"
}

gendtb()
{
    local dts="$1"
    local dtb=""

    if [ -n "${dts}" -a -e "${dts}" ]; then
	dtb="${qemu_builddir}/${dts/.dts/.dtb}"
	if [[ ! -e "${dtb}" ]]; then
            mkdir -p "$(dirname "${dtb}")"
            dtc -I dts -O dtb ${dts} -o ${dtb} >/dev/null 2>&1
	fi
    fi
    echo "${dtb}"
}

# Return kernel version based on parameters
kernel_version()
{
    local v1=${1:-0}
    local v2=${2:-0}

    echo "$((v1 * 65536 + v2))"
}

# Current Linux kernel version
linux_version_code="$(kernel_version $(git describe --match 'v*' | cut -f1 -d- | sed -e 's/\./ /g' | sed -e 's/v//'))"

if [[ ${linux_version_code} -ge $(kernel_version 6 1) ]]; then
    DEFAULT_CC="${DEFAULT_CC13}"
elif [[ ${linux_version_code} -ge $(kernel_version 5 10) ]]; then
    DEFAULT_CC="${DEFAULT_CC12}"
else
    DEFAULT_CC="${DEFAULT_CC11}"
fi

checkstate()
{
    if [[ ${___testbuild} != 0 && $1 != 0 ]]; then
	exit $1
    fi
}

# Parse arguments and set global flags.
# The caller has to execute "shift $((OPTIND - 1).
parse_args()
{
	nobuild=0
	bugverbose=0
	nobugverbose=0
	nokallsyms=0
	dodebug=0
	runall=0
	__testbuild=0
	__log_abort=0
	__log_always=0
	__log_all=0
	___testbuild=0
	verbose=0
	extracli=""

	__set_qemu_builddir_default

	while getopts abBde:KlLnNr:tTvW opt; do
	case ${opt} in
	a)	runall="$((runall + 1))";;
	b)	bugverbose=1;;
	B)	nobugverbose=1;;
	d)	dodebug=$((dodebug + 1));;
	e)	extracli=${OPTARG};;
	K)	nokallsyms=1;;
	n)	__set_qemu_builddir_static; nobuild=1;;
	N)	__set_qemu_builddir_static;;
	t)	__testbuild=1;___testbuild=1;__retries=0;;
	T)	___testbuild=1;__retries=0;;
	r)	__retries=${OPTARG}
		if [[ -z "${__retries}" || -n ${__retries//[0-9]/} ]]; then
		    echo "Bad number of retries: ${__retries}"
		    exit 1
		fi
		;;
	v)	verbose=1;;
	W)	__log_abort=1;;
	l)	__log_always=1;;
	L)	__log_all=1;;
	*)	echo "Bad option ${opt}"; exit 1;;
	esac
	done
}

pcibus_set_root()
{
    __pcibus_root="$1"
    __pcibus_root_index="$2"
}

__pcibridge_init()
{
    __pcibridge_chassis=0
    __pcibridge_id=""
    __pcibus_ref=""
}

__pcibridge_new_bridge()
{
    __pcibridge_chassis=$((__pcibridge_chassis + 1))
    __pcibridge_id="pb${__pcibridge_chassis}"
    __pcibridge_addr=0
    extra_params+=" -device pci-bridge,id=${__pcibridge_id},chassis_nr=${__pcibridge_chassis}"
    if [[ -n "${__pcibus_root}" ]]; then
	extra_params+=",bus=${__pcibus_root}"
	if [[ -n "${__pcibus_root_index}" ]]; then
	    extra_params+=".${__pcibus_root_index}"
	    __pcibus_root_index="$((__pcibus_root_index + 1))"
	fi
    fi
}

__pcibridge_new_port()
{
    if [[ -n "${__pcibridge_id}" ]]; then
	__pcibridge_addr="$((__pcibridge_addr + 1))"
	__pcibus_ref=",bus=${__pcibridge_id},addr=${__pcibridge_addr}"
    elif [[ -n "${__pcibus_root}" ]]; then
	__pcibus_ref=",bus=${__pcibus_root}"
	if [[ -n "${__pcibus_root_index}" ]]; then
	    __pcibus_ref+=".${__pcibus_root_index}"
	    __pcibus_root_index="$((__pcibus_root_index + 1))"
	fi
    fi
}

# Use the following functions to ensure that usb controllers are loaded
# exactly once if needed.
__init_usb_xhci()
{
    __have_xhci=0
}

__load_usb_xhci()
{
    if [[ ${__have_xhci} -eq 0 ]]; then
	__pcibridge_new_port
	extra_params+=" -device qemu-xhci,id=xhci${__pcibus_ref}"
	__have_xhci=1
    fi
}

__init_usb_ohci()
{
    __have_ohci=0
}

__load_usb_ohci()
{
    if [[ ${__have_ohci} -eq 0 ]]; then
	__pcibridge_new_port
	extra_params+=" -device pci-ohci,id=ohci${__pcibus_ref}"
	__have_ohci=1
    fi
}

__init_usb_ehci()
{
    __have_ehci=0
}

__load_usb_ehci()
{
    if [[ ${__have_ehci} -eq 0 ]]; then
	__pcibridge_new_port
	extra_params+=" -device usb-ehci,id=ehci${__pcibus_ref}"
	__have_ehci=1
    fi
}

__init_usb()
{
    __init_usb_ehci
    __init_usb_ohci
    __init_usb_xhci
}

__init_disk()
{
    local fixups="$1"

    __disk_index=0
    __partition_offset=1
    unset __rootfsname

    if echo "${fixups}" | grep -q "fstest="; then
        __run_fstest=1
    else
        __run_fstest=0
    fi
}

__next_disk()
{
    __disk_index=$((__disk_index + 1))
}

__init_rootdev()
{
    unset __rootdev
    unset __rootwait
    unset __fstest_dev
}

__set_rootdev()
{
    local dev="$1"

    if [[ -n "${__rootdev}" ]]; then
	return
    fi

    if [[ "${__run_fstest}" -ne 0 ]]; then
	if echo "${dev}" | grep -q -e "nvme" -e "mmcblk"; then
	    # nvme and mmc partition name is "p<index>"
	    dev="${dev}p"
	fi
	__rootdev="${dev}1"
	__fstest_dev="${dev}2"
    else
	__rootdev="${dev}"
    fi
    __rootwait="$2"
}

__gendisk()
{
    local fspath="$1"
    local fssize="$(stat -c '%s' "${fspath}")"
    local oneM="$((1024 * 1024))"
    local parttype="${fspath##*.}"

    # First time around create disk image and add a partition to it.
    # Make disk large enough that two file system copies are guaranteed
    # to fit. Use MiB units to avoid alignment complaints by parted.

    if [[ "${__disk_index}" -eq 0 ]]; then
	__rootfsname="$(__mktemp /tmp/rootfs.XXXXX)"
	truncate -s 256M "${__rootfsname}"
	parted -s "${__rootfsname}" mklabel gpt
    fi

    fssize="$(((fssize + oneM - 1) / oneM))"
    local fsend="$((__partition_offset + fssize))"

    parted -s "${__rootfsname}" unit MiB mkpart "${parttype}" "${__partition_offset}" "${fsend}"

    dd if="${fspath}" of="${__rootfsname}" bs=1M seek="${__partition_offset}" conv=notrunc status=none

    __partition_offset="$((__partition_offset + fssize))"
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
    "scsi[virtio-pci-old]")
	device="virtio-scsi-pci,disable-modern=on"
	;;
    "scsi[virtio-ccw]")
	# s390 only
	device="virtio-scsi-ccw,devno=fe.0.0001"
	;;
    *)
	;;
    esac

    if [[ "${rootfs}" == *iso ]]; then
	__set_rootdev "/dev/sr0"
	media="cdrom"
	sdevice="scsi-cd"
    else
	__set_rootdev "/dev/sda"
	sdevice="scsi-hd"
    fi

    __pcibridge_new_port
    extra_params+=" ${device:+-device ${device},id=scsi}${__pcibus_ref}"
    extra_params+=" ${device:+-device ${sdevice},bus=scsi.0,drive=d0${wwn:+,wwn=${wwn}}}"
    extra_params+=" -drive file=${rootfs},format=raw,if=${iface:-none}${device:+,id=d0}"
    extra_params+="${media:+,media=${media}}"
}

__common_usbcmd()
{
    local fixup="$1"
    local rootfs="$2"
    local bus

    if [[ "${__have_usb_param}" -eq 0 ]]; then
	extra_params+=" -usb"
	__have_usb_param=1
    fi

    case "${fixup}" in
    "usb-ohci")
	__load_usb_ohci
	extra_params+=" -device usb-storage,bus=ohci.0,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "usb-ehci")
	__load_usb_ehci
	extra_params+=" -device usb-storage,bus=ehci.0,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "usb-xhci")
	__load_usb_xhci
	extra_params+=" -device usb-storage,bus=xhci.0,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "usb")
	extra_params+=" -device usb-storage,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    usb[0-9])
	# Same as "usb", but with explicit bus number
	# The above must not be in quotes to enable pattern matching
	extra_params+=" -device usb-storage,drive=d0,bus=usb-bus.${fixup#usb}"
	extra_params+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    usb[0-9].[0-9])
	# Same as "usb", but with explicit bus and port number
	# The above must not be in quotes to enable pattern matching
	bus="${fixup#usb}"
	extra_params+=" -device usb-storage,drive=d0,bus=usb-bus.${bus%.*},port=${bus#*.}"
	extra_params+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "usb-hub")
	extra_params+=" -device usb-hub,bus=usb-bus.0,port=2"
	extra_params+=" -device usb-storage,bus=usb-bus.0,port=2.1,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    usb-hub[0-9])
	# Same as "usb-hub", but with explicit bus number
	# The above must not be in quotes to enable pattern matching
	extra_params+=" -device usb-hub,bus=usb-bus.${fixup#usb-hub},port=2"
	extra_params+=" -device usb-storage,bus=usb-bus.${fixup#usb-hub},port=2.1,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    usb-hub[0-9].[0-9])
	# Same as "usb-hub", but with explicit bus and port number
	# The above must not be in quotes to enable pattern matching
	bus="${fixup#usb-hub}"
	extra_params+=" -device usb-hub,bus=usb-bus.${bus%.*},port=${bus#*.}"
	extra_params+=" -device usb-storage,bus=usb-bus.${bus%.*},port=${bus#*.}.1,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "usb-uas-ehci")
	__load_usb_ehci
	extra_params+=" -device usb-uas,bus=ehci.0,id=uas"
	extra_params+=" -device scsi-hd,bus=uas.0,scsi-id=0,lun=0,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,format=raw,id=d0"
	;;
    "usb-uas-xhci")
	__load_usb_xhci
	extra_params+=" -device usb-uas,bus=xhci.0,id=uas"
	extra_params+=" -device scsi-hd,bus=uas.0,scsi-id=0,lun=0,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,format=raw,id=d0"
	;;
    "usb-uas")
	extra_params+=" -device usb-uas,id=uas"
	extra_params+=" -device scsi-hd,bus=uas.0,scsi-id=0,lun=0,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,format=raw,id=d0"
	;;
    *)
	;;
    esac

    __set_rootdev "/dev/sda" 1
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
	__pcibridge_new_port
	extra_params+=" -device virtio-blk-pci,drive=d0${__pcibus_ref}"
	extra_params+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "virtio-pci-old")
	__pcibridge_new_port
	extra_params+=" -device virtio-blk-pci,disable-modern=on,drive=d0${__pcibus_ref}"
	extra_params+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "virtio")
	extra_params+=" -drive file=${rootfs},if=virtio,format=raw"
	;;
    *)
	;;
    esac

    __set_rootdev "/dev/vda"
}

__common_flashcmd()
{
    local fixup="$1"
    local rootfs="$2"
    local tmpfile="$(__mktemp /tmp/flash.XXXXX)"
    local flashif="${fixup%%[0-9]*}"
    local params

    if [[ "${flashif}" = "mtd" ]]; then
        params="${fixup#mtd}"
    else
        params="${fixup#flash}"
	flashif="pflash"
    fi
    # Sub-parameters are separated by '.'.
    # First sub-parameter is flash size (in MB),
    # second parameter is partition offset (default in MB, accepts units),
    # third parameter is partition index, 4th parameter is device index.
    local plist=(${params//,/ })
    local flashsize="${plist[0]}"
    local seek="${plist[1]}"
    if [[ -n "${seek}" ]]; then
	local unit="${seek##*[0-9]}"
	if [[ -z "${unit}" ]]; then
	    unit="M"
	else
	    seek="${seek%%[a-zA-Z]*}"
	fi
	case "${unit}" in
	'K'|'k') copysize="$((flashsize * 1024 - seek))";;
	'M'|'m') copysize="$((flashsize - seek))";;
	*) copysize="$((flashsize - seek))";;
	esac
        seek="bs=1${unit} seek=${seek} count=${copysize}"
    fi
    local partition="${plist[2]}"
    if [[ -z "${partition}" ]]; then
	partition="0"
    fi
    local devindex="${plist[3]}"

    truncate -s "${flashsize}M" "${tmpfile}"
    dd if="${rootfs}" of="${tmpfile}" ${seek} conv=notrunc status=none
    extra_params+=" -drive file=${tmpfile},format=raw,if=${flashif}"
    if [[ -n "${devindex}" ]]; then
        extra_params+=",index=${devindex}"
    fi
    __set_rootdev "/dev/mtdblock${partition}"
}

__highest_bit_set()
{
    local cnt=0
    local var="$1"

    while [[ "${var}" -gt 0 ]]; do
	: $((cnt+=1, var>>=1))
    done
    echo "$cnt"
}

__bits_set()
{
    local cnt=0
    local var="$1"

    while [[ "${var}" -gt 0 ]]; do
	: $((cnt+=var&1, var>>=1))
    done
    echo "$cnt"
}

__common_mmccmd()
{
    local fixup="$1"
    local rootfs="$2"
    local rootdev="/dev/mmcblk0"
    local fsize="$(stat --format="%s" "${rootfs}")"
    local bits="$(__bits_set ${fsize})"

    if [[ "${bits}" -ne 1 && "${__run_fstest}" -ne 1 ]]; then
	# ssd/mmc drive size must be an exponent of 2
	# Create temporary file with the appropriate size if the root
	# file system does not meet the criteria.
	# This is only needed if we are not running file system tests;
	# in that case the generated partition image can be used directly.
	local tmpfile="$(__mktemp /tmp/flash.XXXXX)"
	local highest="$(__highest_bit_set "${fsize}")"
	local flashsize

	if [[ "${highest}" -lt 20 ]]; then
	    flashsize=1
	else
	    flashsize="$((1<<highest-20))"
	fi

	# adjust file system size to next exponent of 2
	truncate -s "${flashsize}M" "${tmpfile}"
	dd if="${rootfs}" of="${tmpfile}" ${seek} conv=notrunc status=none

	rootfs="${tmpfile}"
    fi

    if [[ "${fixup}" == sdhci-mmc* ]]; then
	# instantiate sdhci-pci (needed as pre-requisite for mmc)
	__pcibridge_new_port
	extra_params+=" -device sdhci-pci${__pcibus_ref}"
	# continue with rest of mmc handling
	fixup="${fixup##sdhci-}"
    fi

    case "${fixup}" in
    mmc,*)
	# mmc followed by root device name
	extra_params+=" -device sd-card,drive=d0"
	extra_params+=" -drive file=${rootfs},format=raw,if=none,id=d0"
	rootdev="${fixup#mmc,}"
	;;
    mmc|mmc[0-9])
	# mmc optionally followed by mmc device index
	local devindex=${fixup#mmc}
	extra_params+=" -device sd-card,drive=d0"
	extra_params+=" -drive file=${rootfs},format=raw,if=none,id=d0"
	rootdev="/dev/mmcblk${devindex:-0}"
	;;
    "sd")	# similar to mmc, but does not need sd-card; uses if=sd
	extra_params+=" -drive file=${rootfs},format=raw,if=sd"
	;;
    sd[0-9])	# sd drive at index [0-9]
	extra_params+=" -drive file=${rootfs},format=raw,if=sd,index=${fixup#sd}"
	;;
    sd,*)	# sd followed by root device name
	extra_params+=" -drive file=${rootfs},format=raw,if=sd"
	rootdev="${fixup#sd,}"
	;;
    *)
	;;
    esac

    __set_rootdev "${rootdev}" 1
}

__common_satacmd()
{
    local fixup="$1"
    local rootfs="$2"
    local idedevice
    local media
    local satadev

    if [[ "${rootfs}" == *iso ]]; then
	media="cdrom"
	idedevice="ide-cd"
	__set_rootdev "/dev/sr0"
	rootdev="sr0"
    else
	idedevice="ide-hd"
	__set_rootdev "/dev/sda"
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
}

__common_diskcmd()
{
    local fixup="$1"
    local rootfs="$2"
    local media
    local hddev

    if [[ "${rootfs}" == *iso ]]; then
	media="cdrom"
	hddev="/dev/sr0"
    else
	if [[ "${__run_fstest}" -ne 0 ]]; then
	    __gendisk "${rootfs}"
	    if [[ "${__disk_index}" -ne 0 ]]; then
		return 0
	    fi
	    rootfs="${__rootfsname}"
	fi
	hddev="/dev/sda"
    fi

    case "${fixup}" in
    "ata")
	# standard ata/sata drive provided by platform
	# rootwait may be needed for PCMCIA drives and does not hurt
	# otherwise.
	__set_rootdev "${hddev}" 1
	extra_params+=" -drive file=${rootfs},format=raw,if=ide${media:+,media=${media}}"
	;;
    "ide")
	# standard ide/ata/sata drive provided by platform
	# The actual configuration determines if the root file system
	# is /dev/sda (CONFIG_ATA) or /dev/hda (CONFIG_IDE).
	# With CONFIG_IDE, the device is /dev/hda for both hdd and cdrom.
	if ! grep -q "CONFIG_ATA=y" "${__config}"; then
	    hddev="/dev/hda"
	fi
	__set_rootdev "${hddev}"
	extra_params+=" -drive file=${rootfs},format=raw,if=ide${media:+,media=${media}}"
	;;
    sdhci-mmc*|mmc*|sd*)
	__common_mmccmd "${fixup}" "${rootfs}"
	;;
    flash*|mtd*)
	__common_flashcmd "${fixup}" "${rootfs}"
	;;
    "nvme")
	__set_rootdev "/dev/nvme0n1" 1
	__pcibridge_new_port
	extra_params+=" -device nvme,serial=foo,drive=d0${__pcibus_ref}"
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

    __next_disk
}

# Set up secondary file system.
# Format is "fstest=<file system type>".
# A file named filesystem.<file system type> is expected to exist in the
# filesystems/ directory. The primary disk must be specified first in the
# list of fixups.
__common_fscmd()
{
    local fixup=$1
    local params=(${fixup//=/ })
    local fstype="${params[1]}"
    local fspath="$(setup_filesystem "filesystem.${fstype}")"

    if [[ "${__disk_index}" -eq 0 ]]; then
	return 1
    fi

    if [[ -z "${fspath}" ]]; then
	return 1
    fi

    __common_diskcmd "" "${fspath}"
    return 0
}

__common_netcmd()
{
    local fixup="$1"
    local params=(${fixup//=/ })
    local netdev="${params[1]}"

    __do_network_test=1
    case "${netdev}" in
    "default")
	;;
    "nic")
	# preinstalled network device which needs to be instantiated
	extra_params+=" -nic user"
	;;
    usb*)
	if [[ "${__have_usb_param}" -eq 0 ]]; then
	    extra_params+=" -usb"
	    __have_usb_param=1
	fi
	case "${netdev}" in
	"usb-xhci")
	    __load_usb_xhci
	    extra_params+=" -device usb-net,bus=xhci.0,netdev=net0 -netdev user,id=net0"
	    ;;
	"usb")
	    extra_params+=" -device usb-net,netdev=net0 -netdev user,id=net0"
	    ;;
	"usb-ohci")
	    __load_usb_ohci
	    extra_params+=" -device usb-net,bus=ohci.0,netdev=net0 -netdev user,id=net0"
	    ;;
	"usb-uhci")
	    __pcibridge_new_port
	    extra_params+=" -device piix4-usb-uhci,id=uhci_net${__pcibus_ref}"
	    extra_params+=" -device usb-net,bus=uhci_net.0,netdev=net0 -netdev user,id=net0"
	    ;;
	*)
	    ;;
	esac
	;;
    "virtio-net"|"virtio-net-pci"|"virtio-net-device")
	extra_params+=" -device ${netdev},netdev=net0${__pcibus_ref} -netdev user,id=net0"
	;;
    "virtio-net-old"|"virtio-net-pci-old")
	extra_params+=" -device ${netdev%%-old},disable-modern=on,netdev=net0${__pcibus_ref} -netdev user,id=net0"
	;;
    *)
	__pcibridge_new_port
	extra_params+=" -device ${netdev},netdev=net0${__pcibus_ref} -netdev user,id=net0"
	;;
    esac
}

__start_tpm()
{
    __stop_tpm
    if ! /opt/buildbot/bin/swtpm socket --tpmstate dir="${__swtpmdir}" \
		--ctrl type=unixio,path="${__swtpmsock}" --tpm2 \
		-d --pid file="${__swtpmpidfile}"; then
	echo "Failed to start swtpm on ${__swtpmsock}"
	return 1
    fi
    sleep 1
    # Abort if swtpm failed to start
    if [[ ! -s "${__swtpmpidfile}" ]]; then
	echo "Failed to start swtpm"
	rm -f "${__swtpmpidfile}"
	return 1
    fi
    return 0
}

__common_fixup()
{
    local fixup="${1}"
    local rootfs="${2}"

    case "${fixup}" in
    tpm*)
	if [[ ${linux_version_code} -ge $(kernel_version 5 10) ]]; then
	    # Skip tpm tests for earlier kernels because the TPM version
	    # file is missing there but the root file system expects it.
	    __do_tpm_test=1
	    # the QEMU TPM device name depends on the architecture.
	    # Assume the calling code provides the correct device.
	    extra_params+=" -chardev socket,id=chrtpm,path=${__swtpmsock}"
	    extra_params+=" -tpmdev emulator,id=tpm0,chardev=chrtpm"
	    extra_params+=" -device ${fixup},tpmdev=tpm0"
	fi
	;;
    "pci-bridge")
	# Instantiate a new PCI bridge. Instantiate subsequent PCI devices
	# behind this PCI bridge.
	__pcibridge_new_bridge
	;;
    sdhci-mmc*|mmc*|sd*|"nvme"|\
    "ide"|"ata"|sata*|usb*|scsi*|virtio*|flash*|mtd*)
	__common_diskcmd "${fixup}" "${rootfs}"
	;;
    fstest=*)
	# Instantiate disk to run file system tests
	__common_fscmd "${fixup}"
	;;
    pci*)
	# __common_pcicmd "${fixup}" "${rootfs}"
	;;
    net*)
	__common_netcmd "${fixup}"
	;;
    smp[1-9])
	extra_params+=" -smp ${fixup#smp}"
	;;
    efi|efi64)
	case "${ARCH}" in
	"arm64")
	    extra_params+=" -bios ${__basedir}/firmware/QEMU_EFI-aarch64.fd"
	    ;;
	"loongarch")
	    extra_params+=" -bios ${__basedir}/firmware/QEMU_EFI-loongarch64.fd"
	    ;;
	*)
	    extra_params+=" -bios ${__basedir}/firmware/OVMF-pure-efi-64.fd"
	    ;;
	esac
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

    __init_usb
    __init_disk "${fixups}"
    __init_rootdev

    initcli="${config_initcli} kunit.stats_enabled=2 kunit.filter=speed>slow"
    extra_params="-snapshot -audio none"
    __have_usb_param=0
    __do_network_test=0
    __do_tpm_test=0
    __pcibridge_init

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

    # Specify root file system and rootwait on command line if requested
    initcli+="${__rootdev+ root=${__rootdev}}${__rootwait+" rootwait"}"
    # Also specify file system test device if available
    initcli+="${__fstest_dev+ fstest=${__fstest_dev}}"

    # trim leading whitespaces, if any
    initcli="${initcli##*( )}"
    extra_params="${extra_params##*( )}"
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

	if pwd | grep -q buildbot; then
		git clean -x -d -f -q
	else
		make ARCH=${ARCH} mrproper >/dev/null 2>&1
		rm -f .config
	fi
	if [[ -n "${qemu_builddir}" ]]; then
	    rm -rf "${qemu_builddir}"
	fi
}

rootfsname()
{
    local rootfs="$(basename $1)"
    echo "${__cachedir}/${rootfs%.gz}"
}

setup_rootfs()
{
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
    # if the destination has been decompressed.
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
	# Make it sparse
	fallocate -d "${destfile}"
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

fscachepath()
{
    local fname="$(basename $1)"
    echo "${__fscachedir}/${fname%.gz}"
}

setup_filesystem()
{
    local fsfile=$1
    local fspath="${__basedir}/filesystems/${fsfile}"

    if [[ ! -e "${fspath}" && -e "${fspath}.gz" ]]; then
	fsfile="${fsfile}.gz"
	fspath="${fspath}.gz"
    fi

    if [[ ! -e "${fspath}" ]]; then
	return
    fi

    local destfile="$(fscachepath ${fsfile})"

    # TODO: Handle the rest in a common function between root file
    # system setup and this code.

    mkdir -p "${__fscachedir}"

    # Do nothing if file checksums exist and match.
    # Checksums are copied, not regenerated, so that should always work even
    # if the destination has been decompressed.
    if cmp -s "${fspath}.md5" "${destfile}.md5"; then
	echo "${destfile}"
	return
    fi

    # If we get here, clean up the cache first.
    rm -f "${destfile}" "${destfile}.md5"

    cp "${fspath}" "${__fscachedir}"
    if [[ "${fsfile}" == *.gz ]]; then
	gunzip -f "${destfile}.gz"
	fsfile="${fsfile%.gz}"
	# Make it sparse
	fallocate -d "${destfile}"
    fi

    if [[ -e "${fspath}.md5" ]]; then
	cp "${fspath}.md5" "${destfile}.md5"
    fi

    # Cached files must not be modified.
    chmod 444 "${destfile}"
    if [[ -e "${destfile}.md5" ]]; then
	chmod 444 "${destfile}.md5"
    fi
    echo "${destfile}"
}

set_config()
{
    local defconfig="$1"
    local flag="$2"
    local value="$3"

    echo "${flag}=${value}" >> "${defconfig}"
}

disable_config()
{
    local defconfig="$1"
    local flag

    shift

    for flag in $*; do
	set_config "${defconfig}" "${flag}" "n"
    done
}

enable_config()
{
    local defconfig="$1"
    local flag

    shift

    for flag in $*; do
	set_config "${defconfig}" "${flag}" "y"
    done
}

enable_config_supported()
{
    local defconfig="$1"
    local flag

    shift

    for flag in $*; do
	if grep -F -q "${flag}" "${defconfig}"; then
	    enable_config "${defconfig}" "${flag}"
	fi
    done
}

enable_config_cond()
{
    local defconfig="$1"
    local flag

    shift

    for flag in $*; do
	sed -i -e "s/${flag}=m/${flag}=y/" "${defconfig}"
    done
}

__domake()
{
    local CROSS32=""

    if [ "${PREFIX32}" != "" ]; then
        CROSS32="CROSS32_COMPILE=${PREFIX32}"
    fi
    make -j${maxload} O="${qemu_builddir}" ARCH=${ARCH} CROSS_COMPILE=${PREFIX} ${CROSS32} $* >/dev/null </dev/null
    return $?
}

__setup_config()
{
    local defconfig="$1"
    local fragment="$2"
    local fixup="$3"
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

    CROSS32=""
    if [ "${PREFIX32}" != "" ]; then
        CROSS32="CROSS32_COMPILE=${PREFIX32}"
    fi

    if ! __domake ${defconfig} 2>/dev/null; then
	return 2
    fi

    # the configuration is in "${__config}"

    if [ -n "${fragment}" ]; then
	cat "${fragment}" >> "${__config}"
    fi

    if [ -n "${fixup}" ]; then
	patch_defconfig "${__config}" "${fixup}"
    fi

    if [ -n "${fixup}${fragment}" ]; then
	target="olddefconfig"
	if ! __domake ${target} 2>/dev/null; then
	    return 1
	fi
    fi
    return 0
}

is_supported()
{
    local option="${1#CONFIG_}"
    git grep -F -q "config ${option}"
    return $?
}

is_enabled()
{
    grep -q -e "^$1=[m|y]\$" "${__config}"
    return $?
}

is_available()
{
    grep -q -e "^$1=[m|y]\$" -e "^# $1 is not set$" "${__config}"
    return $?
}

is_testing()
{
    if [[ "$(git rev-parse --abbrev-ref HEAD)" = "testing" ]]; then
	return 0
    fi
    return 1
}

__setup_fragment()
{
    local fragment="$1"
    local fixups="${2//:/ }"
    local fixup
    local nocd=0
    local nodebug=0
    local nodebugobj=0
    local nodebugtimers=0
    local nolockup=0
    local nofs=0
    local nolocktests=0
    local nolockdep=0
    local nonvme=0
    local noscsi=0
    local nosecurity=0
    local notests="${__testbuild}"
    local nousb=0
    local novirt=0
    local preempt=0
    local nonet=0

    rm -f "${fragment}"
    touch "${fragment}"

    for fixup in ${fixups}; do
	case "${fixup}" in
	"nosmp")
	    disable_config "${fragment}" CONFIG_SMP
	    ;;
	smp*)
	    enable_config "${fragment}" CONFIG_SMP
	    ;;
	noextras)
	    nodebug=1
	    nocd=1
	    nofs=1
	    nonvme=1
	    noscsi=1
	    notests=1
	    nousb=1
	    novirt=1
	    nonet=1
	    ;;
	nodebug) nodebug=1 ;;
	nodebugobj) nodebugobj=1 ;;
	nodebugtimers) nodebugtimers=1 ;;
	nocd) nocd=1 ;;
	nofs) nofs=1 ;;
	nolockdep)
	    nolockdep=1
	    nolocktests=1
	    ;;
	nolocktests) nolocktests=1 ;;
	nolockup) nolockup=1 ;;
	nonvme) nonvme=1 ;;
	noscsi) noscsi=1 ;;
	nosecurity) nosecurity=1 ;;
	notests) notests=1 ;;
	nousb) nousb=1 ;;
	novirt) novirt=1 ;;
	nonet) nonet=1;;
	preempt) preempt=1 ;;
	*)
	    ;;
	esac
    done

    # Always build with CONFIG_KALLSYMS=y unless explicitly disabled
    if [[ "${nokallsyms}" -eq 1 ]]; then
	disable_config "${fragment}" CONFIG_KPROBES
	disable_config "${fragment}" CONFIG_FUNCTION_TRACER
	disable_config "${fragment}" CONFIG_STACK_TRACER
	disable_config "${fragment}" CONFIG_FTRACE_SYSCALLS
	disable_config "${fragment}" CONFIG_KALLSYMS
	# lock debugging selects CONFIG_KALLSYMS
	nolockdep=1
	nolocktests=1
    else
	enable_config "${fragment}" CONFIG_KALLSYMS
    fi

    # We do not use a userspace helper to download firmware.
    # Disable it to avoid long (60 second) timeouts with
    # rtnl lock held.
    disable_config "${fragment}" CONFIG_FW_LOADER_USER_HELPER
    disable_config "${fragment}" CONFIG_FW_LOADER_USER_HELPER_FALLBACK

    # With CONFIG_DEBUG_SHIRQ enabled, the irq core issues a dummy interrupt
    # to the driver when an interrupt is released using free_irq(). This
    # results in an extra call into the affected interrupt handlers.
    # If/when this happens as part of usb_hcd_pci_shutdown(),
    # the usb interface is already disabled the hardware and does not
    # handle the interrupt. It appears that this may cause random USB
    # errors when shutting down the system.
    # Disabling CONFIG_DEBUG_SHIRQ does not really solve the problem.
    # There is (at least) another problem where usb-ohci does not get
    # or handle handle interrupts, resulting in interface timeouts
    # and hung task resets. The underlying problem is that the qemu
    # interrupts are level triggered. If Linux does not handle all
    # interrupts, pending interrupts will never be cleared and Linux
    # does not receive interrupts even if interrupts are pending
    # It is unclear if the problem is caused by the qemu OHCI implementation
    # or by the Linux kernel. For now it is worked around in qemu
    # (v8.2 and later local branches).
    # disable_config "${fragment}" CONFIG_DEBUG_SHIRQ

    if [[ "${nodebug}" -eq 0 ]]; then
	if [[ "${nosecurity}" -eq 0 ]]; then
	    # security modules
	    enable_config "${fragment}" CONFIG_SECURITY
	    enable_config "${fragment}" CONFIG_SECURITY_APPARMOR
	    enable_config "${fragment}" CONFIG_SECURITY_APPARMOR_KUNIT_TEST
	    enable_config "${fragment}" CONFIG_SECURITY_LANDLOCK
	    enable_config "${fragment}" CONFIG_SECURITY_LANDLOCK_KUNIT_TEST
	    enable_config "${fragment}" CONFIG_SECURITY_LOCKDOWN_LSM
	    enable_config "${fragment}" CONFIG_SECURITY_LOCKDOWN_LSM_EARLY
	    enable_config "${fragment}" CONFIG_SECURITY_YAMA
	    enable_config "${fragment}" CONFIG_SECURITY_LOADPIN
	    enable_config "${fragment}" CONFIG_SECURITY_SAFESETID
	    enable_config "${fragment}" CONFIG_BPF_LSM
	    set_config "${fragment}" CONFIG_LSM "landlock,lockdown,yama,loadpin,safesetid,bpf"
	fi

	# debug options
	enable_config "${fragment}" CONFIG_SLAB_FREELIST_RANDOM

	if [[ ${linux_version_code} -ne $(kernel_version 6 6) ]] || \
		! is_enabled CONFIG_PARISC || is_enabled CONFIG_64BIT; then
	    # Crashes in v6.6.y on 32-bit parisc tests. Older and newer
	    # branches as well as 64-bit tests are ok.
	    # According to bisect, commit 284f17ac13fe ("mm/slub: handle bulk
	    # and single object freeing separately") fixes the problem in v6.8.
	    # Not really worth tracking down details.
	    enable_config "${fragment}" CONFIG_SLAB_FREELIST_HARDENED
	fi

	enable_config "${fragment}" CONFIG_SLUB_DEBUG CONFIG_SLUB_DEBUG_ON
	enable_config "${fragment}" CONFIG_EXPERT CONFIG_DEBUG_KERNEL CONFIG_LOCK_DEBUGGING_SUPPORT
	enable_config "${fragment}" CONFIG_DEBUG_RT_MUTEXES CONFIG_DEBUG_SPINLOCK CONFIG_DEBUG_MUTEXES

	if [[ "${nolockdep}" -eq 0 ]]; then
	    enable_config "${fragment}" CONFIG_DEBUG_LOCKDEP CONFIG_DEBUG_LOCK_ALLOC
	    enable_config "${fragment}" CONFIG_DEBUG_WW_MUTEX_SLOWPATH
	fi

	enable_config "${fragment}" CONFIG_DEBUG_ATOMIC_SLEEP CONFIG_DEBUG_LIST
	enable_config "${fragment}" CONFIG_DEBUG_NOTIFIERS CONFIG_DEBUG_PLIST

	# loongarch crashes if CONFIG_KFENCE is enabled
	if is_testing || ! is_enabled CONFIG_LOONGARCH; then
	    enable_config "${fragment}" CONFIG_DEBUG_SG
	fi

	enable_config "${fragment}" CONFIG_KFENCE
	enable_config "${fragment}" CONFIG_DEBUG_INFO_DWARF5

	if [[ "${nodebugobj}" -eq 0 ]]; then
	    enable_config "${fragment}" CONFIG_DEBUG_OBJECTS CONFIG_DEBUG_OBJECTS_FREE
	    enable_config "${fragment}" CONFIG_DEBUG_OBJECTS_WORK
	    enable_config "${fragment}" CONFIG_DEBUG_OBJECTS_RCU_HEAD
	    enable_config "${fragment}" CONFIG_DEBUG_OBJECTS_PERCPU_COUNTER
	    enable_config "${fragment}" CONFIG_DEBUG_OBJECTS_SELFTEST
	    if [[ "${nodebugtimers}" -eq 0 ]]; then
		enable_config "${fragment}" CONFIG_DEBUG_OBJECTS_TIMERS
	    fi
	fi
	if [[ "${nolockup}" -eq 0 ]]; then
	    enable_config "${fragment}" CONFIG_LOCKUP_DETECTOR CONFIG_SOFTLOCKUP_DETECTOR
	    enable_config "${fragment}" CONFIG_BOOTPARAM_SOFTLOCKUP_PANIC
	    enable_config "${fragment}" CONFIG_DETECT_HUNG_TASK CONFIG_BOOTPARAM_HUNG_TASK_PANIC
	    set_config "${fragment}" CONFIG_DEFAULT_HUNG_TASK_TIMEOUT 30
	fi
    else
	disable_config "${fragment}" CONFIG_SLUB_DEBUG
    fi

    if [[ "${bugverbose}" -eq 1 ]]; then
	enable_config "${fragment}" CONFIG_DEBUG_BUGVERBOSE
    elif [[ "${nobugverbose}" -eq 1 ]]; then
	disable_config "${fragment}" CONFIG_DEBUG_BUGVERBOSE
    fi

    if [[ "${notests}" -eq 0 ]]; then
	# selftests
	# kunit
	# We can not run all tests since some crash on some architectures/platforms.
	# Unfortunately, CONFIG_KUNIT_ALL_TESTS is all or nothing, and individual
	# tests can not be disabled if it is set. That means we have to explicitly
	# disable it and manually select all applicable tests.
	disable_config "${fragment}" CONFIG_KUNIT_ALL_TESTS
	enable_config "${fragment}" CONFIG_KUNIT CONFIG_PM_QOS_KUNIT_TEST
	enable_config "${fragment}" CONFIG_KUNIT_TEST
	# Explicitly disable KUNIT_FAULT_TEST to avoid BUG() messages
	disable_config "${fragment}" CONFIG_KUNIT_FAULT_TEST
	enable_config "${fragment}" CONFIG_SYSCTL_KUNIT_TEST

	# As of v6.9-rc5, ext4 kunit tests pass but result in memory corruption.
	# The problem was introduced in the v6.9 commit window. It looks like the
	# fix may not be applied to v6.9, potentially corrupting test images in
	# this release. Disable for now.
	if is_testing || [[ "${runall}" -ge 2 ]]; then
	    enable_config "${fragment}" CONFIG_EXT4_KUNIT_TESTS
	fi

	# New in v6.10
	enable_config "${fragment}" CONFIG_FIREWIRE_KUNIT_PACKET_SERDES_TEST
	enable_config "${fragment}" CONFIG_ARM_SMMU_V3_KUNIT_TEST
	enable_config "${fragment}" CONFIG_SND_SOC_CARD_KUNIT_TEST

	# New in v6.11
	enable_config "${fragment}" CONFIG_EXEC_KUNIT_TEST CONFIG_BINFMT_ELF_KUNIT_TEST
	enable_config "${fragment}" CONFIG_FIREWIRE_KUNIT_SELF_ID_SEQUENCE_HELPER_TEST
	enable_config "${fragment}" CONFIG_FIREWIRE_KUNIT_OHCI_SERDES_TEST

	# Fails on arm, loongarch, mips, nios2, microblaze, sparc32 (as of v6.11-rc2)
	if [[ "${runall}" -ge 2 ]]; then
	    enable_config "${fragment}" CONFIG_USERCOPY_KUNIT_TEST
	fi

	enable_config "${fragment}" CONFIG_LIST_KUNIT_TEST
	enable_config "${fragment}" CONFIG_RESOURCE_KUNIT_TEST
	enable_config "${fragment}" CONFIG_CMDLINE_KUNIT_TEST
	enable_config "${fragment}" CONFIG_HASH_UNIT_TEST
	enable_config "${fragment}" CONFIG_CPUMASK_KUNIT_TEST CONFIG_BITFIELD_KUNIT
	enable_config "${fragment}" CONFIG_HASH_KUNIT_TEST CONFIG_HASHTABLE_KUNIT_TEST
	enable_config "${fragment}" CONFIG_OVERFLOW_KUNIT_TEST CONFIG_STRSCPY_KUNIT_TEST
	enable_config "${fragment}" CONFIG_KUNIT_DEBUGFS
	enable_config "${fragment}" CONFIG_MPTCP_KUNIT_TEST CONFIG_NET_HANDSHAKE_KUNIT_TEST
	enable_config "${fragment}" CONFIG_IIO_FORMAT_KUNIT_TEST CONFIG_IIO_RESCALE_KUNIT_TEST
	enable_config "${fragment}" CONFIG_REGMAP_KUNIT CONFIG_REGMAP_BUILD
	enable_config "${fragment}" CONFIG_INPUT_KUNIT_TEST
	enable_config "${fragment}" CONFIG_HID_KUNIT_TEST
	enable_config "${fragment}" CONFIG_IS_SIGNED_TYPE_KUNIT_TEST

	if ! is_enabled CONFIG_ARCH_MPS2 || [[ "${runall}" -ge 2 ]]; then
	    # Unaligned IPv6 checksum tests cause a crash with CONFIG_ARCH_MPS2
	    enable_config "${fragment}" CONFIG_CHECKSUM_KUNIT
	fi

	enable_config "${fragment}" CONFIG_STACKINIT_KUNIT_TEST

	enable_config "${fragment}" CONFIG_LIST_HARDENED CONFIG_DEBUG_LIST
	# Oddity: We have to disable the following option to enable the tests
	disable_config "${fragment}" CONFIG_CRYPTO_MANAGER_DISABLE_TESTS
	enable_config "${fragment}" CONFIG_DEBUG_NMI_SELFTEST CONFIG_DEBUG_RODATA_TEST
	enable_config "${fragment}" CONFIG_DEBUG_TLBFLUSH CONFIG_DMATEST
	enable_config "${fragment}" CONFIG_PCI_EPF_TEST CONFIG_PCI_ENDPOINT_TEST
	enable_config "${fragment}" CONFIG_RCU_EQS_DEBUG CONFIG_STATIC_KEYS_SELFTEST
	enable_config "${fragment}" CONFIG_TEST_SORT
	enable_config "${fragment}" CONFIG_USB_TEST CONFIG_USB_EHSET_TEST_FIXTURE
	enable_config "${fragment}" CONFIG_USB_LINK_LAYER_TEST

	enable_config "${fragment}" CONFIG_DM_KUNIT_TEST CONFIG_DRIVER_PE_KUNIT_TEST
	enable_config "${fragment}" CONFIG_USB4_KUNIT_TEST CONFIG_BINFMT_ELF_KUNIT_TEST
	enable_config "${fragment}" CONFIG_FAT_KUNIT_TEST
	enable_config "${fragment}" CONFIG_TEST_LIST_SORT TEST_SORT
	enable_config "${fragment}" CONFIG_PERCPU_TEST
	enable_config "${fragment}" CONFIG_TEST_KSTRTOX
	enable_config "${fragment}" CONFIG_TEST_BPF
	enable_config "${fragment}" CONFIG_TEST_BLACKHOLE_DEV
	enable_config "${fragment}" CONFIG_MMC_SDHCI_OF_ASPEED_TEST
	enable_config "${fragment}" CONFIG_TEST_IOV_ITER

	enable_config "${fragment}" CONFIG_CROS_KUNIT_EC_PROTO_TEST
	enable_config "${fragment}" CONFIG_RATIONAL_KUNIT_TEST

	enable_config "${fragment}" CONFIG_MEAN_AND_VARIANCE_UNIT_TEST
	if [[ "${runall}" -ge 2 ]] || \
		( ! is_enabled CONFIG_ARCH_MPS2 && ! is_enabled CONFIG_NIOS2 && \
		  ! is_enabled CONFIG_PARISC ); then
	    # Crashes in gso tests on an385, nios2, and parisc.
	    enable_config "${fragment}" CONFIG_NET_TEST
	fi
	if is_enabled CONFIG_CFG80211; then
	    enable_config "${fragment}" CONFIG_CFG80211
	    enable_config "${fragment}" CONFIG_CFG80211_KUNIT_TEST
	fi

	if is_enabled CONFIG_MAC80211; then
	    enable_config CONFIG_MAC80211
	    enable_config "${fragment}" CONFIG_MAC80211_KUNIT_TEST
	fi

	if [[ ${linux_version_code} -ge $(kernel_version 6 1) ]]; then
	    # slub unit tests fail in v5.15.y and older kernels.
	    enable_config "${fragment}" CONFIG_SLUB_KUNIT_TEST
	fi

	enable_config "${fragment}" CONFIG_STRCAT_KUNIT_TEST
	enable_config "${fragment}" CONFIG_SIPHASH_KUNIT_TEST
	enable_config "${fragment}" CONFIG_STRING_KUNIT_TEST
	enable_config "${fragment}" CONFIG_STRING_HELPERS_KUNIT_TEST
	enable_config "${fragment}" CONFIG_FORTIFY_KUNIT_TEST

	enable_config "${fragment}" CONFIG_CLK_KUNIT_TEST
	enable_config "${fragment}" CONFIG_CLK_FD_KUNIT_TEST
	if [[ ${linux_version_code} -ge $(kernel_version 6 7) ]]; then
	    # clock gate unit tests fail on some systems in v6.6 and older
	    # kernels. See upstream commit 75357829cc8e ("clk: Fix clk gate
	    # kunit test on big-endian CPUs").
	    enable_config "${fragment}" CONFIG_CLK_GATE_KUNIT_TEST
	fi

	enable_config "${fragment}" CONFIG_RPCSEC_GSS_KRB5_KUNIT_TEST

	enable_config "${fragment}" CONFIG_FIREWIRE_KUNIT_UAPI_TEST CONFIG_FIREWIRE_KUNIT_DEVICE_ATTRIBUTE_TEST
	enable_config "${fragment}" CONFIG_FPGA_KUNIT_TESTS

	if ( ! is_enabled CONFIG_ARM && ! is_enabled CONFIG_ARM64 && \
		! is_enabled CONFIG_LOONGARCH && ! is_enabled CONFIG_PPC64 ) \
		|| [[ "${runall}" -ge 1 ]]; then
	    # hardware breakpoint tests are known to be broken on arm/arm64. See
	    # https://lore.kernel.org/lkml/Ytl9L0Zn1PVuL1cB@FVFF77S0Q05N.cambridge.arm.com/
	    # for details.
	    # Other failures:
	    # - The loongarch failure is due to its qemu emulation.
	    # - ppc64:powernv tests are known to fail. The failures have not been
	    #   evaluated.
	    enable_config "${fragment}" CONFIG_HW_BREAKPOINT_KUNIT_TEST
	fi

	if is_enabled CONFIG_SND_HDA; then
	    enable_config "${fragment}" CONFIG_SND_HDA
	    enable_config "${fragment}" CONFIG_SND_HDA_CIRRUS_SCODEC_KUNIT_TEST
	fi
	if is_enabled CONFIG_SND_SOC; then
	    enable_config "${fragment}" CONFIG_SND_SOC
	    enable_config "${fragment}" CONFIG_SND_SOC_TOPOLOGY_BUILD
	    enable_config "${fragment}" CONFIG_SND_SOC_TOPOLOGY_KUNIT_TEST
	    enable_config "${fragment}" CONFIG_SND_SOC_UTILS_KUNIT_TEST
	fi

	# CONFIG_MEMCPY_KUNIT_TEST sometimes takes more than 45 seconds to run.
	# CONFIG_MEMCPY_SLOW_KUNIT_TEST avoids this, so only configure
	# CONFIG_MEMCPY_KUNIT_TEST if slow tests can be disabled.
	if is_supported CONFIG_MEMCPY_SLOW_KUNIT_TEST ||
		[[ ${linux_version_code} -ge $(kernel_version 6 6) ]]; then
	    enable_config "${fragment}" CONFIG_MEMCPY_KUNIT_TEST
	    disable_config "${fragment}" CONFIG_MEMCPY_SLOW_KUNIT_TEST
	fi

	# If DRM is enabled for a given configuration, build it into the kernel
	# and enable unit tests on it. Do the same for its various sub-tests.
	#
	# The tests result in warning backtraces in drm code. At least some of
	# them are intentional (see below for details), making the tests all
	# but unusable due to WARNING noise.
	# Note that TTM is a single-use functionality (see linux-next commit
	# de1b1b78516d ("drm/ttm/tests: depend on UML || COMPILE_TEST")
	# but is not protected against multi-use. Running TTM unit tests
	# (CONFIG_DRM_TTM_KUNIT_TEST) is therefore not possible on real
	# hardware or even in qemu, and must never be enabled.
	if [[ "${runall}" -ge 2 ]]; then
	    if is_enabled CONFIG_DRM; then
		enable_config "${fragment}" CONFIG_DRM
		# Results in warning backtraces triggered by intentionally
		# bad API calls in drm_rect_test.c.
		enable_config "${fragment}" CONFIG_DRM_KUNIT_TEST
		# see above
		# enable_config "${fragment}" CONFIG_DRM_TTM_KUNIT_TEST
		if is_enabled CONFIG_DRM_XE; then
		    enable_config "${fragment}" CONFIG_DRM_XE
		    enable_config "${fragment}" CONFIG_DRM_XE_KUNIT_TEST
		fi
		if is_enabled CONFIG_DRM_VC4; then
		    enable_config "${fragment}" CONFIG_DRM_VC4
		    enable_config "${fragment}" CONFIG_DRM_VC4_KUNIT_TEST
		fi
	    fi
	fi

	# non-standard output, can not parse
	# enable_config "${fragment}" CONFIG_TEST_PRINTF CONFIG_TEST_SCANF CONFIG_TEST_UUID
	# enable_config "${fragment}" CONFIG_TEST_HEXDUMP CONFIG_TEST_BITMAP CONFIG_TEST_FIRMWARE
	# enable_config "${fragment}" CONFIG_TEST_XARRAY
	# enable_config "${fragment}" CONFIG_TEST_SYSCTL
	# enable_config "${fragment}" CONFIG_CRC32_SELFTEST CONFIG_TEST_MIN_HEAP
	# enable_config "${fragment}" CONFIG_DEBUG_LOCKING_API_SELFTESTS
	# enable_config "${fragment}" CONFIG_ATOMIC64_SELFTEST
	# enable_config "${fragment}" CONFIG_RBTREE_TEST CONFIG_INTERVAL_TREE_TEST
	# enable_config "${fragment}" CONFIG_GLOB_SELFTEST

	if is_testing || [[ "${runall}" -ge 2 ]]; then
	    # RTC library unit tests are slow but not marked as such
	    # (as of v6.8, v6.9-rc4).
	    enable_config "${fragment}" CONFIG_RTC_LIB_KUNIT_TEST
	fi

	#
	# runs too long (> 2 minutes) or hangs, and non-standard output
	# enable_config "${fragment}" CONFIG_REED_SOLOMON_TEST
	#
	# hangs without output
	# enable_config "${fragment}" CONFIG_TEST_MAPLE_TREE
	#
	# hangs with soft lockup (arm, microblaze) and/or reports RCU stalls
	# (mips). Even if not hanging or stalling, it takes a long time to run
	# on older kernels.
	if is_testing || [[ "${runall}" -ge 2 ]] || \
		[[ ${linux_version_code} -ge $(kernel_version 6 6) ]]; then
	    enable_config "${fragment}" CONFIG_TIME_KUNIT_TEST
	fi
	#
	# non-standard output
	# enable_config "${fragment}" CONFIG_OF_UNITTEST
	#
	# takes too long
	# enable_config "${fragment}" CONFIG_TEST_RHASHTABLE
	#
	# triggers tracebacks, runs for a long time
	# enable_config "${fragment}" CONFIG_KFENCE_KUNIT_TEST

	if is_testing || [[ "${runall}" -ge 1 ]]; then
	    enable_config "${fragment}" CONFIG_NETDEV_ADDR_LIST_TEST
	fi

	if [[ "${nolocktests}" -eq 0 ]]; then
	    enable_config "${fragment}" CONFIG_PROVE_RCU CONFIG_PROVE_LOCKING
	    # takes too long
	    # enable_config "${fragment}" CONFIG_TORTURE_TEST CONFIG_LOCK_TORTURE_TEST CONFIG_RCU_TORTURE_TEST
	    # CONFIG_WW_MUTEX_SELFTEST interferes with CONFIG_PREEMPT=y.
	    # Even without it it may run very long or hang.
	    if ! is_enabled CONFIG_PREEMPT && [[ "${runall}" -ge 3 ]]; then
		enable_config "${fragment}" CONFIG_WW_MUTEX_SELFTEST
	    fi
	fi
    else
	disable_config "${fragment}" CONFIG_KUNIT
    fi

    if [[ "${nonet}" -eq 0 ]]; then
	enable_config "${fragment}" CONFIG_NET_VENDOR_INTEL CONFIG_E100 CONFIG_E1000 CONFIG_E1000E
	enable_config "${fragment}" CONFIG_NET_VENDOR_REALTEK CONFIG_8139CP
	enable_config "${fragment}" CONFIG_NET_VENDOR_AMD CONFIG_PCNET32
	enable_config "${fragment}" CONFIG_NET_VENDOR_NATSEMI
	enable_config "${fragment}" CONFIG_NET_VENDOR_8390 CONFIG_NE2K_PCI
	enable_config "${fragment}" CONFIG_NET_VENDOR_DEC CONFIG_NET_TULIP CONFIG_TULIP
	if [[ "${nousb}" -eq 0 ]]; then
	    enable_config "${fragment}" CONFIG_USB_NET_DRIVERS CONFIG_USB_USBNET
	    enable_config "${fragment}" CONFIG_USB_NET_CDCETHER CONFIG_USB_NET_CDC_SUBSET
	fi
	# explicitly disable built-in dhcp server
	disable_config "${fragment}" CONFIG_IP_PNP_DHCP
    fi

    # BLK_DEV_INITRD
    enable_config "${fragment}" CONFIG_BLK_DEV_INITRD

    # DEVTMPFS
    enable_config "${fragment}" CONFIG_DEVTMPFS CONFIG_DEVTMPFS_MOUNT

    if [[ "${noscsi}" -eq 0 ]]; then
	# SCSI and SCSI controller drivers
	enable_config "${fragment}" CONFIG_SCSI CONFIG_BLK_DEV_SD CONFIG_SCSI_LOWLEVEL
	enable_config "${fragment}" CONFIG_SCSI_DC395x CONFIG_SCSI_AM53C974 CONFIG_SCSI_SYM53C8XX_2
	enable_config "${fragment}" CONFIG_MEGARAID_SAS CONFIG_FUSION CONFIG_FUSION_SAS
    fi

    # MMC/SDHCI support
    enable_config "${fragment}" CONFIG_MMC CONFIG_MMC_SDHCI CONFIG_MMC_SDHCI_PCI

    if [[ "${nonvme}" -eq 0 ]]; then
	# NVME support
	enable_config "${fragment}" CONFIG_BLK_DEV_NVME
    fi

    if [[ "${nocd}" -eq 0 ]]; then
	# CDROM support
	enable_config "${fragment}" CONFIG_BLK_DEV_SR CONFIG_ISO9660_FS CONFIG_CDROM
    else
	disable_config "${fragment}" CONFIG_BLK_DEV_SR CONFIG_ISO9660_FS CONFIG_CDROM
    fi

    if [[ "${nousb}" -eq 0 ]]; then
	# USB support
	enable_config "${fragment}" CONFIG_USB CONFIG_USB_XHCI_HCD CONFIG_USB_EHCI_HCD
	enable_config "${fragment}" CONFIG_USB_OHCI_HCD CONFIG_USB_STORAGE CONFIG_USB_UAS
    fi

    if [[ "${novirt}" -eq 0 ]]; then
	# Virtualization
	enable_config "${fragment}" CONFIG_VIRTIO CONFIG_VIRTIO_PCI CONFIG_VIRTIO_PCI_LEGACY
	enable_config "${fragment}" CONFIG_VIRTIO_BALLOON CONFIG_VIRTIO_MMIO CONFIG_BLK_MQ_VIRTIO
	enable_config "${fragment}" CONFIG_VIRTIO_BLK CONFIG_VIRTIO_BLK_SCSI CONFIG_SCSI_VIRTIO
	if [[ "${nonet}" -eq 0 ]]; then
	    enable_config "${fragment}" CONFIG_VIRTIO_NET
	fi
    fi

    if [[ "${nofs}" -eq 0 ]]; then
	# file systems
	enable_config "${fragment}" CONFIG_BTRFS_FS
	# Needed to address broken dependencies in -next (around 20190708)
	enable_config "${fragment}" CONFIG_LIBCRC32C
	# MISC_FILESYSTEMS is needed for SQUASHFS
	enable_config "${fragment}" CONFIG_MISC_FILESYSTEMS CONFIG_SQUASHFS CONFIG_SQUASHFS_XATTR
	enable_config "${fragment}" CONFIG_SQUASHFS_ZLIB CONFIG_SQUASHFS_4K_DEVBLK_SIZE
	enable_config "${fragment}" CONFIG_EXT3_FS
    fi

    if [[ "${preempt}" -eq 1 ]]; then
	enable_config "${fragment}" CONFIG_PREEMPT
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
    local rel=$(git describe --match 'v*' | cut -f1 -d- | cut -f1,2 -d. | sed -e 's/\.//' | sed -e 's/v//')
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
    local build="${ARCH}:${defconfig}"
    local EXTRAS=""
    local fixup=""
    local fixups=""
    local cached_config=""
    local fragment=""

    __dosetup_rc=0

    OPTIND=1
    while getopts c:b:de:f:F: opt
    do
	case ${opt} in
	b) build="${OPTARG}";;
	c) cached_config="${OPTARG}";;
	e) EXTRAS="${OPTARG}";;
	f) fixup="${OPTARG}";;
	F) fixups="${OPTARG:-dummy}";;
	*) ;;
	esac
    done

    shift $((OPTIND - 1))

    local rootfs=$1
    local defconfig=$2

    # If nobuild is set, don't build image, just set up the root file
    # system as needed. Assumes that the image was built already in
    # a previous test run. Bail out if that is not the case.
    if [ ${nobuild:-0} -ne 0 ]; then
	if [[ ! -d "${qemu_builddir}" ]]; then
	    echo "failed (no build directory)"
	    __dosetup_rc=1
	    return 1
	fi
	rootfs="$(setup_rootfs ${rootfs})"
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
	rootfs="$(setup_rootfs ${rootfs})"
	__common_fixups "${fixups}" "${rootfs}"
        [[ ${dodebug} -ne 0 ]] && echo -n "[cached] "
	return 0
    fi

    __cached_config="${cached_config}"
    __cached_results=0
    __cached_reason=""

    doclean ${ARCH}

    if [[ -z "${qemu_builddir}" ]]; then
	__set_qemu_builddir_default
    fi

    mkdir -p "${qemu_builddir}"

    if [ -n "${fixups}" ]; then
	# dummy call to initialize .config
	__setup_config "${defconfig}" "" "${fixup:-${fixups}}"
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

    rootfs="$(setup_rootfs ${rootfs})"
    __common_fixups "${fixups}" "${rootfs}"

    if ! __domake ${EXTRAS} 2>${logfile}; then
	rv=1
	__cached_reason="failed"
	echo "failed"
	echo "------------"
	echo "Error log:"
	if [[ "${__log_all}" -ne 0 ]]; then
	    cat ${logfile}
	else
	    head -1000 ${logfile}
	fi
	echo "------------"
    fi

    __cached_results=${rv}
    __dosetup_rc=${rv}
    return ${rv}
}

# Combine all kunit test results into a single log line
kunit_summary()
{
    declare results="$(grep -a -e '# Totals: pass:[0-9]* fail:[0-9]* skip:[0-9]* total:[0-9]*' "$1" | sed -e 's/^\[.*\] # Totals: //')"
    local pass=0
    local fail=0
    local skip=0
    local total=0

    for result in ${results[@]}; do
	# Drop trailing '\r'
	result="${result%$'\r'}"
	for r in ${result}; do
	    case $r in
	    pass:[0-9]*)
		pass="$((pass + ${r//pass:}))"
		;;
	    fail:[0-9]*)
		fail="$((fail + ${r//fail:}))"
		;;
	    skip:[0-9]*)
		skip="$((skip + ${r//skip:}))"
		;;
	    total:[0-9]*)
		total="$((total + ${r//total:}))"
		;;
	    esac
	done
    done
    echo "# Totals: pass:${pass} fail:${fail} skip:${skip} total:${total}"
}

dowait()
{
    local pid=$1
    local logfile=$2
    local report=$3
    local manual=$4
    local waitlist=("${!5}")
    local entries=${#waitlist[*]}
    local retcode=0
    local t=0
    local st=0
    local i
    local msg="passed"
    local dolog
    local fsize=0
    local fsize_tmp

    # Give the process some time to start
    sleep 2

    # Sometimes the log file goes missing
    if [[ ! -e "${logfile}" ]]; then
	echo " failed (missing log file)"
	return 1
    fi

    while true
    do
        # terminate if process is no longer running
	if [[ ! -d "/proc/${pid}" ]]; then
	    wait ${pid} >/dev/null 2>&1
	    if [[ $? -ne 0 ]]; then
		msg="failed (qemu)"
		retcode=1
	    fi
	    break
	fi

	# If this qemu session doesn't stop by itself, help it along.
	# Assume first entry in waitlist points to the message
	# we are waiting for here.
	# We need to do this prior to checking for a crash since
	# some kernels _do_ crash on reboot (eg sparc64, openrisc)

	if [ "${manual}" = "manual" ]; then
	    if grep -a -q "${waitlist[0]}" ${logfile}; then
		dokill ${pid}
		break
	    fi
	fi

	if grep -a -q -e "Oops: \|Kernel panic\|Internal error:\|segfault" ${logfile}; then
	    # x86 has the habit of crashing in restart once in a while.
	    # Try to ignore it.
	    if ! grep -a -q -e "^machine restart" ${logfile}; then
		msg="failed (crashed)"
		retcode=1
	    fi
	    dokill ${pid}
	    break
	fi

	fsize_tmp="$(stat -c "%s" ${logfile})"
	if [[ "${fsize}" = "${fsize_tmp}" ]]; then
	    if [[ ${st} -gt ${MAXSTIME} ]]; then
		msg="failed (silent)"
		dokill ${pid}
		retcode=1
		break
	    fi
	else
	    fsize="${fsize_tmp}"
	    st=0
	fi

	if [ $t -gt ${MAXTIME} ]; then
		msg="failed (timeout)"
		dokill ${pid}
		retcode=1
		break
	fi
	sleep ${LOOPTIME}
	t=$((t + ${LOOPTIME}))
	st=$((st + ${LOOPTIME}))
	echo -n .
    done

    # Sometimes qemu exits immediately after a crash and the above code
    # does not catch it. Catch it here, with exceptions as noted.
    if [[ ${retcode} -eq 0 ]]; then
	if grep -a -q -e "Oops: \|Kernel panic\|Internal error:\|segfault" ${logfile}; then
	    if [[ "${ARCH}" == "xtensa" ]]; then
		# xtensa images may crash during reboot; reason unknown.
		# It may be because its reboot handler jumps directly to
		# the reset address but doesn't really reset the CPU,
		# leaving some exception handling still enabled.
		if ! grep -a -q "reboot: Restarting system" ${logfile}; then
		    msg="failed (crashed)"
		    retcode=1
		fi
		if ! grep -a -q "Unrecoverable error in exception handler" ${logfile}; then
		    msg="failed (crashed)"
		    retcode=1
		fi
	    elif ! grep -a -q -e "^machine restart\|MACHINE RESTART" ${logfile}; then
		# x86 has the habit of crashing in restart once in a while,
		# and openrisc crashes all the time.
		# Try to ignore it.
		msg="failed (crashed)"
		retcode=1
	    fi
	fi
    fi

    # Look for missing root file system
    if [[ ${retcode} -eq 0 ]]; then
	if grep -a -q "Cannot open root device" ${logfile}; then
	    msg="failed (no root file system)"
	    retcode=1
	fi
    elif [[ "${msg}" = "failed (silent)" ]]; then
	# If nothing happened for a while, we may be waiting for
	# the root file system. Detect that situation as well.
	# Expect the log message to be at the end of the log;
	# we don't want to overwrite the reason if something else
	# happened after we started waiting for the root file system.
	if tail ${logfile} | grep -a -q "Waiting for root device"; then
	    msg="failed (no root file system)"
	    retcode=1
	fi
    fi

    # Look for network test failures
    if [[ ${retcode} -eq 0 && "${__do_network_test}" -ne 0 ]]; then
	if ! grep -a -q "Network interface test passed" ${logfile}; then
	    msg="failed (network)"
	    retcode=1
	fi
    fi

    # Look for TPM test failures
    if [[ ${retcode} -eq 0 && "${__do_tpm_test}" -ne 0 ]]; then
	if ! grep -a -q "TPM selftest passed" ${logfile}; then
	    msg="failed (tpm)"
	    retcode=1
	fi
    fi

    # Look for file system test failures
    if [[ ${retcode} -eq 0 ]]; then
	if grep -a -q "File system test failed" ${logfile}; then
	    msg="failed (file system)"
	    retcode=1
	fi
    fi

    if [ ${retcode} -eq 0 ]; then
	for i in $(seq 0 $((${entries} - 1)))
	do
	    if ! grep -a -q -E "${waitlist[$i]}" ${logfile}; then
		# The first entry is not always found; this can happen
		# if qemu executes the reset before it is displayed.
		# Look for alternate.
	        if [[ $i -eq 0 ]]; then
		    if grep -a -q "Requesting system reboot" ${logfile}; then
			continue
		    fi
		    if grep -a -q "Rebooting" ${logfile}; then
			continue
		    fi
		fi
		msg="failed (No \"${waitlist[$i]}\" message in log)"
		retcode=1
		break
	    fi
	done
    fi

    dolog=$((retcode + __log_always))
    if grep -a -q "cannot create duplicate filename" ${logfile}; then
	dolog=1
    fi
    if grep -a -q "\[ cut here \]" ${logfile}; then
	dolog=1
    fi
    if grep -a -q "\[ end trace [0-9a-f]* \]" ${logfile}; then
	dolog=1
    fi
    if grep -a -q "dump_stack" ${logfile}; then
	dolog=1
    fi
    if grep -a -q "stack backtrace" ${logfile}; then
	dolog=1
    fi
    if grep -a -q "Call Trace" ${logfile}; then
	dolog=1
    fi
    if grep -a -q "BUG: KFENCE:" ${logfile}; then
	dolog=1
    fi
    # Try to catch failing kunit tests
    if grep -a -q -e '# Totals: pass:[0-9]* fail:[1-9][0-9]* skip:[0-9]* total:[0-9]*' ${logfile}; then
	dolog=1
    fi

    # Store coredump in well defined location
    if [[ -e core ]]; then
	dolog=1
	mkdir -p /tmp/coredumps
	# Wait until coredump is complete
	sleep 1
	while lsof core >/dev/null 2>&1; do
	    sleep 1
	done
	# Sometimes the core dump still has a size of 0.
	# No idea what is going on, but let's wait a little longer.
	if [[ ! -s core ]]; then
	    sleep 10
	    while lsof core >/dev/null 2>&1; do
	        sleep 1
	    done
	fi
	# There is no value in saving zero size core dumps
	if [[ -s core ]]; then
	    gzip core
	    mv core.gz /tmp/coredumps/core.$(basename ${QEMU}).${pid}.gz
	fi
	# clear out leftover empty core files
	rm -f core
    fi

    if [[ ${report} -ne 0 || ${retcode} -eq 0 ]]; then
	echo " ${msg}"

	if [[ ${dolog} -ne 0 || ${verbose} -ne 0 ]]; then
	    # Empty lines are irrelevant / don't add value.
	    # First replace sequences of <cr> with a single <newline>
	    sed -i 's/\r\+/\n/g'  "${logfile}"
	    # Now remove empty lines
	    sed -i '/^[[:space:]]*$/d' "${logfile}"
	    echo "------------"
	    echo "qemu log:"
	    if [[ "${__log_all}" -ne 0 ]]; then
		cat ${logfile}
	    else
		head -5000 ${logfile}
	    fi
	    echo "------------"
	elif grep -a -q -e '# Totals: pass:[0-9]* fail:[0-9]* skip:[0-9]* total:[0-9]*' ${logfile}; then
	    echo "Kunit tests:"
	    kunit_summary "${logfile}"
	fi
	if [[ ${dolog} -ne 0 && ${__log_abort} -ne 0 ]]; then
	    retcode=1
	fi
    fi

    return ${retcode}
}

execute()
{
    local waitflag=$1
    local waitlist=("${!2}")
    local cmd="$3"
    local pid
    local logfile="$(__mktemp /tmp/run.XXXXX)"
    local retries=0
    local retcode
    local last=0

    shift; shift; shift

    echo -n "running ..."

    pushd "${qemu_builddir}" >/dev/null

    if [[ ${dodebug} -ne 0 ]]; then
	local x
	local len="$(echo ${cmd} | wc | awk '{print $3}')"
	local is_kernel_opt=0
	local is_dtb_opt=0

	echo
	echo -n "${cmd}"
	# The loop is needed to quote multi-element parameters correctly.
	# At the same time, it lets us conveniently split command line output
	# to multiple lines, which is quite useful to improve readability.
	for x in "$@"; do
	    # Override kernel location to include the build directory.
	    if [[ "$x" == "-kernel" ]]; then
	        is_kernel_opt=1
	    elif [[ ${is_kernel_opt} -ne 0 ]]; then
		x="${qemu_builddir}/$x"
	        is_kernel_opt=0
	    fi

	    # Override dtb file location to include the build directory.
	    if [[ "$x" == "-dtb" ]]; then
	        is_dtb_opt=1
	    elif [[ ${is_dtb_opt} -ne 0 ]]; then
		x="${qemu_builddir}/$x"
	        is_dtb_opt=0
	    fi

	    local n="$(echo $x | wc | awk '{print $2}')"
	    local l="$(echo $x | wc | awk '{print $3}')"

	    if [[ "$((len + l))" -ge 80 ]]; then
	        echo " \\"; echo -n "    "
		len=4
	    fi
	    len="$((len + l + 1))"
	    if [[ n -gt 1 ]]; then
		echo -n " \"$x\""
		len="$((len + 2))"
	    else
		echo -n " $x"
	    fi
	done
	echo
    fi

    while [[ ${retries} -le ${__retries} ]]; do
	if [[ ${retries} -eq ${__retries} ]]; then
	    last=1
	fi
	if [[ ${retries} -ne 0 ]]; then
	    echo -n "R"
	fi

	if [[ "${__do_tpm_test}" -ne 0 ]]; then
	    if ! __start_tpm; then
		retries=$((retries + 1))
		continue
	    fi
	fi

	"${cmd}" "$@" > "${logfile}" 2>&1 &
	pid=$!

	dowait "${pid}" "${logfile}" "${last}" "${waitflag}" waitlist[@]
	retcode=$?

	if [[ ${retcode} -eq 0 ]]; then
	    break
	fi

	retries=$((retries + 1))
    done

    popd >/dev/null

    return ${retcode}
}
