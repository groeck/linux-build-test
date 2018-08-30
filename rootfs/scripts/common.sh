#!/bin/bash

shopt -s extglob

__logfiles=$(mktemp "/tmp/logfiles.XXXXXX")
__progdir="$(cd $(dirname $0); pwd)"
__basedir="${__progdir}/.."

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
    local wwn
    local iface

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

    initcli+=" root=/dev/sda rw"
    extra_params+=" ${device:+-device ${device},id=scsi}"
    extra_params+=" ${device:+-device scsi-hd,bus=scsi.0,drive=d0${wwn:+,wwn=${wwn}}}"
    extra_params+=" -drive file=${rootfs},format=raw,if=${iface:-none}${device:+,id=d0}"
}

__common_usbcmd()
{
    local fixup="$1"
    local rootfs="$2"

    case "${fixup}" in
    "usb-ohci")
	extra_params+=" -usb -device pci-ohci,id=ohci"
	extra_params+=" -device usb-storage,bus=ohci.0,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "usb-ehci")
	extra_params+=" -usb -device usb-ehci,id=ehci"
	extra_params+=" -device usb-storage,bus=ehci.0,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "usb-xhci")
	extra_params+=" -usb -device qemu-xhci,id=xhci"
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
	extra_params+=" -usb -device usb-ehci,id=ehci"
	extra_params+=" -device usb-uas,bus=ehci.0,id=uas"
	extra_params+=" -device scsi-hd,bus=uas.0,scsi-id=0,lun=0,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,format=raw,id=d0"
	;;
    "usb-uas-xhci")
	extra_params+=" -usb -device qemu-xhci,id=xhci"
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

    initcli+=" root=/dev/sda rw rootwait"
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
	extra_params+=" -device virtio-blk-pci,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "virtio")
	extra_params+=" -drive file=${rootfs},if=virtio,format=raw"
	;;
    *)
	;;
    esac

    initcli+=" root=/dev/vda rw"
}

__common_mmccmd()
{
    local fixup="$1"
    local rootfs="$2"

    case "${fixup}" in
    "mmc")
	initcli+=" root=/dev/mmcblk0 rw rootwait"
	extra_params+=" -device sdhci-pci -device sd-card,drive=d0"
	extra_params+=" -drive file=${rootfs},format=raw,if=none,id=d0"
	;;
    "sd")	# similar to mmc, but does not need sdhci-pci
	initcli+=" root=/dev/mmcblk0 rw rootwait"
	extra_params+=" -drive file=${rootfs},format=raw,if=sd"
	;;
    "sd1")	# sd at index 1
	initcli+=" root=/dev/mmcblk0 rw rootwait"
	extra_params+=" -drive file=${rootfs},format=raw,if=sd,index=1"
	;;
    *)
	;;
    esac

    initcli+=" root=/dev/mmcblk0 rw rootwait"
}

__common_satacmd()
{
    local fixup="$1"
    local rootfs="$2"

    case "${fixup}" in
    "sata-sii3112")
	# generic sata drive provided by SII3112 SATA controller
	# Available on ppc
	extra_params+=" -device sii3112,id=ata"
	extra_params+=" -device ide-hd,bus=ata.0,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "sata-cmd646")
	# generic sata drive provided by CMD646 PCI ATA/SATA controller
	# Available on alpha, parisc, sparc64
	extra_params+=" -device cmd646-ide,id=ata"
	extra_params+=" -device ide-hd,bus=ata.0,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "sata")	# generic sata drive, pre-existing bus
	extra_params+=" -device ide-hd,drive=d0"
	extra_params+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    *)
	;;
    esac

    initcli+=" root=/dev/sda rw"
}

__common_diskcmd()
{
    local fixup="$1"
    local rootfs="$2"

    case "${fixup}" in
    "ata")
	# standard ata/sata drive provided by platform
	extra_params+=" -drive file=${rootfs},format=raw,if=ide"
	initcli+=" root=/dev/sda rw"
	;;
    "ide")
	# standard ide/ata/sata drive provided by platform
	extra_params+=" -drive file=${rootfs},format=raw,if=ide"
	local hddev="hda"
	# The actual configuration determines if the root file system
	# is /dev/sda (CONFIG_ATA) or /dev/hda (CONFIG_IDE).
	if grep -q "CONFIG_ATA=y" .config; then
	    hddev="sda"
	fi
	initcli+=" root=/dev/${hddev} rw"
	;;
    "mmc"|"sd"|"sd1")
	__common_mmccmd "${fixup}" "${rootfs}"
	;;
    "nvme")
	initcli+=" root=/dev/nvme0n1 rw rootwait"
	extra_params+=" -device nvme,serial=foo,drive=d0"
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
    local rootfs="${2%.gz}"
    local fixup

    if [[ -z "${fixups}" ]]; then
	return
    fi

    initcli=""
    extra_params=""

    if [[ "${rootfs}" == *cpio ]]; then
	initcli="rdinit=/sbin/init"
	extra_params="-initrd ${rootfs}"
	rootfs=""
    fi

    for fixup in ${fixups}; do
	__common_fixup "${fixup}" "${rootfs}"
    done

    # trim leading whitespace
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
    local fixup=$1
    local rootfs="${2%.gz}"

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
	initcli="root=/dev/sda rw"
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

    if [ -n "${rootfs}" ]
    then
	if [[ -n "${dynamic}" && "${rootfs}" == *cpio ]]; then
	    fakeroot ${__basedir}/scripts/genrootfs.sh ${__progdir} ${rootfs}
	else
	    cp ${__progdir}/${rootfs} .
	fi
    fi
    if [[ "${rootfs}" == *.gz ]]; then
	gunzip -f $(basename "${rootfs}")
    fi
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
	*)
	    ;;
	esac
    done

    # BLK_DEV_INITRD
    echo "CONFIG_BLK_DEV_INITRD=y" >> ${fragment}

    # DEVTMPFS
    echo "CONFIG_DEVTMPFS=y" >> ${fragment}
    echo "CONFIG_DEVTMPFS_MOUNT=y" >> ${fragment}

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

    # MMC/SDHCI support
    echo "CONFIG_MMC=y" >> ${fragment}
    echo "CONFIG_MMC_SDHCI=y" >> ${fragment}
    echo "CONFIG_MMC_SDHCI_PCI=y" >> ${fragment}

    # NVME support
    echo "CONFIG_BLK_DEV_NVME=y" >> ${fragment}

    # USB support
    echo "CONFIG_USB=y" >> ${fragment}
    echo "CONFIG_USB_XHCI_HCD=y" >> ${fragment}
    echo "CONFIG_USB_EHCI_HCD=y" >> ${fragment}
    echo "CONFIG_USB_OHCI_HCD=y" >> ${fragment}
    echo "CONFIG_USB_STORAGE=y" >> ${fragment}
    echo "CONFIG_USB_UAS=y" >> ${fragment}

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

    # If nobuild is set, don't build image, just set up the root file
    # system as needed. Assumes that the image was built already in
    # a previous test run.
    if [ ${nobuild:-0} -ne 0 ]; then
	__common_fixups "${fixups}" "${rootfs}"
	setup_rootfs ${dynamic} "${rootfs}"
	return 0
    fi

    if ! checkskip "${build}"; then
	# Don't update build cache information in this case because we
	# didn't do anything. Don't clear the cache either because it
	# might still be useful for a later build.
	return 2
    fi

    if [[ -n "${cached_config}" && "${cached_config}" == "${__cached_config}" ]]; then
	if [[ ${__cached_results} -ne 0 ]]; then
	    echo "${__cached_reason} (cached)"
	    return ${__cached_results}
	fi
	__common_fixups "${fixups}" "${rootfs}"
	setup_rootfs ${dynamic} "${rootfs}"
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
	return ${rv}
    fi

    __common_fixups "${fixups}" "${rootfs}"
    setup_rootfs ${dynamic} "${rootfs}"

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
