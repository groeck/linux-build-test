#!/bin/bash

# Set the following variable to true to skip DC395/AM53C97 build tests
__skip_dc395=0

shopt -s extglob

ulimit -c unlimited

# limit file size to 1GB to prevent log file sizes from getting out of control.
# Note that the limit needs to be a bit larger than 1GB to accommodate 1GB
# flashes, and some arm64 builds need inexplicably more space when linking.
ulimit -f $((1500 * 1024))

__logfiles=$(mktemp "/tmp/logfiles.XXXXXX")
__progdir="$(cd $(dirname $0); pwd)"
__basedir="${__progdir}/.."
. "${__basedir}/scripts/config.sh"

if [[ -w /var/cache/buildbot ]]; then
    __cachedir="/var/cache/buildbot/$(basename ${__progdir})"
else
    __cachedir="/tmp/buildbot-cache/$(basename ${__progdir})"
fi

__do_network_test=0

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

trap __cleanup EXIT SIGHUP SIGINT SIGQUIT SIGILL SIGTRAP SIGABRT SIGBUS SIGFPE SIGSEGV SIGALRM SIGTERM SIGPWR

# Common variables used for waiting

LOOPTIME=5	# Wait time before checking status
MAXTIME=150	# Maximum wait time for qemu session to complete
MAXSTIME=60	# Maximum wait time for qemu session to generate output
__retries=1	# Default number of retries

__testbuild=0

# We run multiple builds at a time
# maxload=$(($(nproc) * 3 / 2))
maxload=$(nproc)

# Return kernel version based on parameters
kernel_version()
{
    local v1=${1:-0}
    local v2=${2:-0}
    local v3=${3:-0}

    echo "$((v1 * 16777216 + v2 * 65536 + v3))"
}

# Current Linux kernel version
linux_version_code="$(kernel_version $(git describe --match 'v*' | cut -f1 -d- | sed -e 's/\./ /g' | sed -e 's/v//'))"

checkstate()
{
    if [[ ${__testbuild} != 0 && $1 != 0 ]]; then
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
	__testbuild=0
	verbose=0
	extracli=""
	while getopts ae:dnr:tv opt; do
	case ${opt} in
	a)	runall=1;;
	d)	dodebug=$((dodebug + 1));;
	e)	extracli=${OPTARG};;
	n)	nobuild=1;;
	t)	__testbuild=1;__retries=0;;
	r)	__retries=${OPTARG}
		if [[ -z "${__retries}" || -n ${__retries//[0-9]/} ]]; then
		    echo "Bad number of retries: ${__retries}"
		    exit 1
		fi
		;;
	v)	verbose=1;;
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
	__pcibridge_new_port
	extra_params+=" -device pci-ohci,id=ohci${__pcibus_ref}"
	extra_params+=" -device usb-storage,bus=ohci.0,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "usb-ehci")
	__pcibridge_new_port
	extra_params+=" -device usb-ehci,id=ehci${__pcibus_ref}"
	extra_params+=" -device usb-storage,bus=ehci.0,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "usb-xhci")
	__pcibridge_new_port
	extra_params+=" -device qemu-xhci,id=xhci${__pcibus_ref}"
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
    "usb-uas-ehci")
	__pcibridge_new_port
	extra_params+=" -device usb-ehci,id=ehci${__pcibus_ref}"
	extra_params+=" -device usb-uas,bus=ehci.0,id=uas"
	extra_params+=" -device scsi-hd,bus=uas.0,scsi-id=0,lun=0,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,format=raw,id=d0"
	;;
    "usb-uas-xhci")
	__pcibridge_new_port
	extra_params+=" -device qemu-xhci,id=xhci${__pcibus_ref}"
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
	__pcibridge_new_port
	extra_params+=" -device virtio-blk-pci,drive=d0${__pcibus_ref}"
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
    # third parameter is partition index.
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

    dd if=/dev/zero of="${tmpfile}" bs=1M count="${flashsize}" status=none
    dd if="${rootfs}" of="${tmpfile}" ${seek} conv=notrunc status=none
    extra_params+=" -drive file=${tmpfile},format=raw,if=${flashif}"
    initcli+=" root=/dev/mtdblock${partition}"
}

__common_mmccmd()
{
    local fixup="$1"
    local rootfs="$2"
    local rootdev="/dev/mmcblk0"

    case "${fixup}" in
    "sdhci")
	__pcibridge_new_port
	extra_params+=" -device sdhci-pci${__pcibus_ref}"
	;;
    mmc*)
	local devindex=${fixup#mmc}
	extra_params+=" -device sd-card,drive=d0"
	extra_params+=" -drive file=${rootfs},format=raw,if=none,id=d0"
	if [[ -n "${devindex}" ]]; then
	    rootdev="/dev/mmcblk${devindex}"
	fi
	;;
    "sd")	# similar to mmc, but does not need sd-card; uses if=sd
	extra_params+=" -drive file=${rootfs},format=raw,if=sd"
	;;
    sd[0-9])	# sd drive at index [0-9]
	extra_params+=" -drive file=${rootfs},format=raw,if=sd,index=${fixup#sd}"
	;;
    *)
	;;
    esac

    initcli+=" root=${rootdev} rootwait"
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
	# "rootwait" may be needed for PCMCIA drives and does not hurt
	# otherwise.
	initcli+=" rootwait"
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
    mmc*|sd*|"sdhci")
	__common_mmccmd "${fixup}" "${rootfs}"
	;;
    flash*|mtd*)
	__common_flashcmd "${fixup}" "${rootfs}"
	;;
    "nvme")
	initcli+=" root=/dev/nvme0n1 rootwait"
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
}

__common_netcmd()
{
    local fixup="$1"
    local params=(${fixup//,/ })
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
	"usb")
	    extra_params+=" -device usb-net,netdev=net0 -netdev user,id=net0"
	    ;;
	"usb-ohci")
	    __pcibridge_new_port
	    extra_params+=" -device pci-ohci,id=ohci_net${__pcibus_ref}"
	    extra_params+=" -device usb-net,bus=ohci_net.0,netdev=net0 -netdev user,id=net0"
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
    virtio-net*)
	extra_params+=" -device ${netdev},netdev=net0${__pcibus_ref} -netdev user,id=net0"
	;;
    *)
	__pcibridge_new_port
	extra_params+=" -device ${netdev},netdev=net0${__pcibus_ref} -netdev user,id=net0"
	;;
    esac
}

__common_fixup()
{
    local fixup="${1}"
    local rootfs="${2}"

    case "${fixup}" in
    "pci-bridge")
	# Instantiate a new PCI bridge. Instantiate subsequent PCI devices
	# behind this PCI bridge.
	__pcibridge_new_bridge
	;;
    mmc*|sd*|"sdhci"|"nvme"|\
    "ide"|"ata"|sata*|usb*|scsi*|virtio*|flash*|mtd*)
	__common_diskcmd "${fixup}" "${rootfs}"
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
        if [[ "${ARCH}" == "arm64" ]]; then
	    extra_params+=" -bios ${__basedir}/firmware/QEMU_EFI-aarch64.fd"
	else
	    extra_params+=" -bios ${__basedir}/firmware/OVMF-pure-efi-64.fd"
	fi
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
    __have_usb_param=0
    __do_network_test=0
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

    # trim leading whitespaces, if any
    initcli="${initcli##*( )}"
    extra_params="${extra_params##*( )}"
}

# Set globals diskcmd and initcli variables
# using common fixup strings.
# Supports:
# - initrd / rootfs separation
# - mmc/mmc[0-9]/sd/sd[0-9]/sdhci
#   Difference:
#   - sdhci instantiates sdhci-pci, as pre-requisite of mmc
#   - mmc/mmc[0-9] instantiates sd-card
#     mmc[0-9] uses mmcblk[0-9] as root device
#   - sd/sd[0-9] uses if=sd
#   sd[0-9] instantiates the drive at index [0-9].
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
# - flash{size_in_MB}
# - mtd{size_in_MB}
#   Creates flash file with root file system at start
common_diskcmd()
{
    local fixups="${1//:/ }"
    local rootfs="$2"

    if [[ "${rootfs}" == *cpio ]]; then
	initcli="rdinit=/sbin/init"
	diskcmd="-initrd ${rootfs}"
	return 0
    fi

    extra_params=""
    initcli=""
    __have_usb_param=0
    __pcibridge_init

    for fixup in ${fixups}; do
	__common_diskcmd "${fixup}" "${rootfs}"
    done
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

    if ! make ARCH=${ARCH} CROSS_COMPILE=${PREFIX} ${defconfig} >/dev/null 2>&1 </dev/null; then
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
    local nocd=0
    local nodebug=0
    local nofs=0
    local nolocktests=0
    local nonvme=0
    local noscsi=0
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
	nocd) nocd=1 ;;
	nofs) nofs=1 ;;
	nolocktests) nolocktests=1 ;;
	nonvme) nonvme=1 ;;
	noscsi) noscsi=1 ;;
	notests) notests=1 ;;
	nousb) nousb=1 ;;
	novirt) novirt=1 ;;
	nonet) nonet=1;;
	preempt) preempt=1 ;;
	*)
	    ;;
	esac
    done

    # Always build with CONFIG_KALLSYMS enabled
    enable_config "${fragment}" CONFIG_KALLSYMS

    if [[ "${nodebug}" -eq 0 ]]; then
	# debug options
	enable_config "${fragment}" CONFIG_EXPERT CONFIG_DEBUG_KERNEL CONFIG_LOCK_DEBUGGING_SUPPORT
	enable_config "${fragment}" CONFIG_DEBUG_RT_MUTEXES CONFIG_DEBUG_SPINLOCK CONFIG_DEBUG_MUTEXES
	enable_config "${fragment}" CONFIG_DEBUG_WW_MUTEX_SLOWPATH CONFIG_DEBUG_LOCK_ALLOC
	enable_config "${fragment}" CONFIG_DEBUG_LOCKDEP CONFIG_DEBUG_ATOMIC_SLEEP CONFIG_DEBUG_LIST
    fi

    if [[ "${notests}" -eq 0 ]]; then
	# selftests
	# kunit
	enable_config "${fragment}" CONFIG_KUNIT CONFIG_KUNIT_TEST CONFIG_PM_QOS_KUNIT_TEST
	enable_config "${fragment}" CONFIG_EXT4_KUNIT_TESTS CONFIG_SYSCTL_KUNIT_TEST
	enable_config "${fragment}" CONFIG_LIST_KUNIT_TEST CONFIG_SECURITY_APPARMOR_KUNIT_TEST
	# other
	disable_config "${fragment}" CONFIG_CRYPTO_MANAGER_DISABLE_TESTS
	# CONFIG_CRYPTO_SHA512 is needed for crypto self tests starting with v5.14
	enable_config "${fragment}" CONFIG_CRYPTO_SHA512
	enable_config "${fragment}" CONFIG_CRC32_SELFTEST CONFIG_DEBUG_LOCKING_API_SELFTESTS
	enable_config "${fragment}" CONFIG_DEBUG_NMI_SELFTEST CONFIG_DEBUG_RODATA_TEST
	enable_config "${fragment}" CONFIG_DEBUG_TLBFLUSH CONFIG_DMATEST CONFIG_GLOB_SELFTEST
	enable_config "${fragment}" CONFIG_OF_UNITTEST CONFIG_PCI_EPF_TEST CONFIG_PCI_ENDPOINT_TEST
	enable_config "${fragment}" CONFIG_RCU_EQS_DEBUG CONFIG_STATIC_KEYS_SELFTEST
	enable_config "${fragment}" CONFIG_STRING_SELFTEST CONFIG_TEST_BITMAP CONFIG_TEST_FIRMWARE
	# takes too long
	# enable_config "${fragment}" CONFIG_TEST_RHASHTABLE
	enable_config "${fragment}" CONFIG_TEST_SORT CONFIG_TEST_SYSCTL CONFIG_TEST_UUID
	enable_config "${fragment}" CONFIG_USB_TEST CONFIG_USB_EHSET_TEST_FIXTURE
	enable_config "${fragment}" CONFIG_USB_LINK_LAYER_TEST

	if [[ "${nolocktests}" -eq 0 ]]; then
	    enable_config "${fragment}" CONFIG_PROVE_RCU CONFIG_PROVE_LOCKING CONFIG_WW_MUTEX_SELFTEST
	    # takes too long
	    # enable_config "${fragment}" CONFIG_TORTURE_TEST CONFIG_LOCK_TORTURE_TEST CONFIG_RCU_TORTURE_TEST
	fi

	enable_config "${fragment}" CONFIG_RBTREE_TEST CONFIG_INTERVAL_TREE_TEST
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
	enable_config "${fragment}"  CONFIG_PREEMPT
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

    rootfs="$(setup_rootfs ${rootfs})"
    __common_fixups "${fixups}" "${rootfs}"

    make -j${maxload} ARCH=${ARCH} CROSS_COMPILE=${PREFIX} ${EXTRAS} </dev/null >/dev/null 2>${logfile}
    rv=$?
    if [ ${rv} -ne 0 ]
    then
	__cached_reason="failed"
	echo "failed"
	echo "------------"
	echo "Error log:"
	head -1000 ${logfile}
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

    while true
    do
        # terminate if process is no longer running
	if ! kill -0 ${pid} >/dev/null 2>&1; then
	    break
	fi

	# If this qemu session doesn't stop by itself, help it along.
	# Assume first entry in waitlist points to the message
	# we are waiting for here.
	# We need to do this prior to checking for a crash since
	# some kernels _do_ crash on reboot (eg sparc64, openrisc)

	if [ "${manual}" = "manual" ]; then
	    if grep -q "${waitlist[0]}" ${logfile}; then
		dokill ${pid}
		break
	    fi
	fi

	if grep -q -e "Oops: \|Kernel panic\|Internal error:\|segfault" ${logfile}; then
	    # x86 has the habit of crashing in restart once in a while.
	    # Try to ignore it.
	    if ! grep -q -e "^machine restart" ${logfile}; then
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

    # Look for missing root file system
    if [[ ${retcode} -eq 0 ]]; then
	if grep -q "Cannot open root device" ${logfile}; then
	    msg="failed (no root file system)"
	    retcode=1
	fi
    elif [[ "${msg}" = "failed (silent)" ]]; then
	# If nothing happened for a while, we may be waiting for
	# the root file system. Detect that situation as well.
	# Expect the log message to be at the end of the log;
	# we don't want to overwrite the reason if something else
	# happened after we started waiting for the root file system.
	if tail ${logfile} | grep -q "Waiting for root device"; then
	    msg="failed (no root file system)"
	    retcode=1
	fi
    fi

    # Look for network test failures
    if [[ ${retcode} -eq 0 && "${__do_network_test}" -ne 0 ]]; then
	if ! grep -q "Network interface test passed" ${logfile}; then
	    msg="failed (network)"
	    retcode=1
	fi
    fi

    if [ ${retcode} -eq 0 ]; then
	for i in $(seq 0 $((${entries} - 1)))
	do
	    if ! grep -q -E "${waitlist[$i]}" ${logfile}; then
		# The first entry is not always found; this can happen
		# if qemu executes the reset before it is displayed.
		# Look for alternate.
	        if [[ $i -eq 0 ]]; then
		    if grep -q "Requesting system reboot" ${logfile}; then
			continue
		    fi
		fi
		msg="failed (No \"${waitlist[$i]}\" message in log)"
		retcode=1
		break
	    fi
	done
    fi

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
	    echo "------------"
	    echo "qemu log:"
	    head -5000 ${logfile}
	    echo "------------"
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
    local logfile="$(__mktemp)"
    local retries=0
    local retcode
    local last=0

    shift; shift; shift

    echo -n "running ..."

    if [[ ${dodebug} -ne 0 ]]; then
	local x
	local len="$(echo ${cmd} | wc | awk '{print $3}')"

	echo
	echo -n "${cmd}"
	# The loop is needed to quote multi-element parameters correctly.
	# At the same time, it lets us conveniently split command line output
	# to multiple lines, which is quite useful to improve readability.
	for x in "$@"; do
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

	"${cmd}" "$@" > "${logfile}" 2>&1 &
	pid=$!

	dowait "${pid}" "${logfile}" "${last}" "${waitflag}" waitlist[@]
	retcode=$?

	if [[ ${retcode} -eq 0 ]]; then
	    break
	fi

	retries=$((retries + 1))
    done

    return ${retcode}
}
