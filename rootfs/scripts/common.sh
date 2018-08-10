#!/bin/bash

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

    initcli="root=/dev/sda rw"	# override as needed
    diskcmd=""

    if [[ "${rootfs}" == *cpio ]]; then
	initcli="rdinit=/sbin/init"
	diskcmd="-initrd ${rootfs}"
	return 0
    fi

    case "${fixup}" in
    "mmc")
	initcli="root=/dev/mmcblk0 rw rootwait"
	diskcmd="-device sdhci-pci -device sd-card,drive=d0"
	diskcmd+=" -drive file=${rootfs},format=raw,if=none,id=d0"
	;;
    "sd")	# similar to mmc, but does not need sdhci-pci
	initcli="root=/dev/mmcblk0 rw rootwait"
	diskcmd+=" -drive file=${rootfs},format=raw,if=sd"
	;;
    "sd1")	# sd at index 1
	initcli="root=/dev/mmcblk0 rw rootwait"
	diskcmd+=" -drive file=${rootfs},format=raw,if=sd,index=1"
	;;
    "nvme")
	initcli="root=/dev/nvme0n1 rw rootwait"
	diskcmd="-device nvme,serial=foo,drive=d0"
	diskcmd+=" -drive file=${rootfs},if=none,format=raw,id=d0"
	;;
    "ata")	# standard ide/ata/sata drive provided by platform
	diskcmd="-drive file=${rootfs},format=raw,if=ide"
	local hddev="hda"
	# The actual configuration determines if the root file system
	# is /dev/sda (CONFIG_ATA) or /dev/hda (CONFIG_IDE).
	if grep -q "CONFIG_ATA=y" .config; then
	    hddev="sda"
	fi
	initcli="root=/dev/${hddev} rw"
	;;
    "sata-sii3112")
	# generic sata drive provided by SII3112 SATA controller
	# Available on ppc
	diskcmd="-device sii3112,id=ata"
	diskcmd+=" -device ide-hd,bus=ata.0,drive=d0"
	diskcmd+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "sata-cmd646")
	# generic sata drive provided by CMD646 PCI ATA/SATA controller
	# Available on alpha, parisc, sparc64
	diskcmd="-device cmd646-ide,id=ata"
	diskcmd+=" -device ide-hd,bus=ata.0,drive=d0"
	diskcmd+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "sata")	# generic sata drive, pre-existing bus
	diskcmd+=" -device ide-hd,drive=d0"
	diskcmd+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "usb-ohci")
	initcli="root=/dev/sda rw rootwait"
	diskcmd="-usb -device pci-ohci,id=ohci"
	diskcmd+=" -device usb-storage,bus=ohci.0,drive=d0"
	diskcmd+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "usb-ehci")
	initcli="root=/dev/sda rw rootwait"
	diskcmd="-usb -device usb-ehci,id=ehci"
	diskcmd+=" -device usb-storage,bus=ehci.0,drive=d0"
	diskcmd+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "usb-xhci")
	initcli="root=/dev/sda rw rootwait"
	diskcmd="-usb -device qemu-xhci,id=xhci"
	diskcmd+=" -device usb-storage,bus=xhci.0,drive=d0"
	diskcmd+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "usb")
	initcli="root=/dev/sda rw rootwait"
	diskcmd="-usb -device usb-storage,drive=d0"
	diskcmd+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "usb-hub")
	initcli="root=/dev/sda rw rootwait"
	diskcmd="-usb -device usb-hub,bus=usb-bus.0,port=2"
	diskcmd+=" -device usb-storage,bus=usb-bus.0,port=2.1,drive=d0"
	diskcmd+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "usb-uas-ehci")
	initcli="root=/dev/sda rw rootwait"
	diskcmd="-usb -device usb-ehci,id=ehci"
	diskcmd+=" -device usb-uas,bus=ehci.0,id=uas"
	diskcmd+=" -device scsi-hd,bus=uas.0,scsi-id=0,lun=0,drive=d0"
	diskcmd+=" -drive file=${rootfs},if=none,format=raw,id=d0"
	;;
    "usb-uas-xhci")
	initcli="root=/dev/sda rw rootwait"
	diskcmd="-usb -device qemu-xhci,id=xhci"
	diskcmd+=" -device usb-uas,bus=xhci.0,id=uas"
	diskcmd+=" -device scsi-hd,bus=uas.0,scsi-id=0,lun=0,drive=d0"
	diskcmd+=" -drive file=${rootfs},if=none,format=raw,id=d0"
	;;
    "usb-uas")
	initcli="root=/dev/sda rw rootwait"
	diskcmd="-usb -device usb-uas,id=uas"
	diskcmd+=" -device scsi-hd,bus=uas.0,scsi-id=0,lun=0,drive=d0"
	diskcmd+=" -drive file=${rootfs},if=none,format=raw,id=d0"
	;;
    scsi*)
	local device
	local wwn
	local if

	case "${fixup}" in
	"scsi")	# Standard SCSI controller provided by platform
	    if="scsi"
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
	*)
	    echo "failed (config)"
	    return 1
	    ;;
	esac
	diskcmd="${device:+-device ${device},id=scsi}"
	diskcmd+=" ${device:+-device scsi-hd,bus=scsi.0,drive=d0${wwn:+,wwn=${wwn}}}"
	diskcmd+=" -drive file=${rootfs},format=raw,if=${if:-none}${device:+,id=d0}"
	;;
    "virtio-blk")
	initcli="root=/dev/vda rw"
	diskcmd="-device virtio-blk-device,drive=d0"
	diskcmd+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    "virtio")
	initcli="root=/dev/vda rw"
	diskcmd="-device virtio-blk-pci,drive=d0"
	diskcmd+=" -drive file=${rootfs},if=none,id=d0,format=raw"
	;;
    *)
	echo "failed (config)"
	return 1
	;;
    esac
    return 0
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
    local progdir=$(cd $(dirname $0); pwd)
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
	    fakeroot ${progdir}/../scripts/genrootfs.sh ${progdir} ${rootfs}
	else
	    cp ${progdir}/${rootfs} .
	fi
    fi
    if [[ "${rootfs}" == *.gz ]]; then
	gunzip -f $(basename "${rootfs}")
    fi
}

setup_config()
{
    local defconfig=$1
    local fixup=$2
    local rel=$(git describe | cut -f1 -d- | cut -f1,2 -d.)
    local progdir=$(cd $(dirname $0); pwd)
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

    if [ -e ${progdir}/${defconfig} ]
    then
	mkdir -p arch/${arch}/configs
	cp ${progdir}/${defconfig} arch/${arch}/configs
    fi

    make ARCH=${ARCH} CROSS_COMPILE=${PREFIX} ${defconfig} >/dev/null 2>&1 </dev/null
    if [ $? -ne 0 ]
    then
	return 2
    fi

    # the configuration is in .config

    if [ -n "${fixup}" ]
    then
	patch_defconfig .config "${fixup}"
	target="olddefconfig"
	if [[ "${rel}" = "v3.16" ]]; then
	    target="oldconfig"
	fi
	make ARCH=${ARCH} CROSS_COMPILE=${PREFIX} ${target} >/dev/null 2>&1 </dev/null
	if [ $? -ne 0 ]
	then
	    return 1
	fi
    fi
    return 0
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
    local logfile=/tmp/qemu.setup.$$.log
    local tmprootfs=/tmp/rootfs.$$
    local rel=$(git describe | cut -f1 -d- | cut -f1,2 -d. | sed -e 's/\.//' | sed -e 's/v//')
    local build="${ARCH}:${defconfig}"
    local EXTRAS=""
    local fixup=""
    local dynamic=""
    local cached_config=""

    # If nobuild is set, don't build image, just set up the root file
    # system as needed. Assumes that the image was built already in
    # a previous test run.
    if [ ${nobuild:-0} -ne 0 ]; then
	setup_rootfs ${dynamic} "${rootfs}"
	return 0
    fi

    OPTIND=1
    while getopts c:b:de:f: opt
    do
	case ${opt} in
	b) build="${OPTARG}";;
	c) cached_config="${OPTARG}";;
	d) dynamic="-d";;
	e) EXTRAS="${OPTARG}";;
	f) fixup="${OPTARG}";;
	*) ;;
	esac
    done

    shift $((OPTIND - 1))

    local rootfs=$1
    local defconfig=$2

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
	setup_rootfs ${dynamic} "${rootfs}"
        [[ ${dodebug} -ne 0 ]] && echo -n "[cached] "
	return 0
    fi

    __cached_config="${cached_config}"
    __cached_results=0
    __cached_reason=""

    doclean ${ARCH}

    setup_config "${defconfig}" "${fixup}"
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

    rm -f ${logfile}

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
