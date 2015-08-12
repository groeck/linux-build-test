#!/bin/bash

# Common variables used for waiting

LOOPTIME=5	# Wait time before checking status
MAXTIME=120	# Maximum wait time for qemu session to complete

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
    local rootfs=$1
    local dynamic=$2
    local progdir=$(cd $(dirname $0); pwd)

    if [ -n "${rootfs}" ]
    then
	if [ -n "${dynamic}" ]
	then
	    fakeroot ${progdir}/../scripts/genrootfs.sh ${progdir} ${rootfs}
        else
	    cp ${progdir}/${rootfs} .
	fi
    fi
}

# Automatically determine if dynamic root file system
# setup is supported.

setup_rootfs_auto()
{
    setup_rootfs "$1" "$(echo $1 | grep cpio)"
}

setup_config()
{
    local ARCH=$1
    local defconfig=$2
    local fixup=$3
    local progdir=$(cd $(dirname $0); pwd)
    local arch

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

    mkdir -p arch/${arch}/configs
    if [ -e ${progdir}/${defconfig} ]
    then
        cp ${progdir}/${defconfig} arch/${arch}/configs
    fi

    if [ -n "${fixup}" ]
    then
        local f="arch/${arch}/configs/${defconfig}"
	local ndefconfig="tmp_$(basename ${defconfig})"
        local tf="arch/${arch}/configs/${ndefconfig}"
	cp $f ${tf}
	patch_defconfig ${tf} ${fixup}
	defconfig=${ndefconfig}
    fi
    echo ${defconfig}
}

dosetup()
{
    local ARCH=$1
    local PREFIX=$2
    local EXTRAS=$3
    local rootfs=$4
    local defconfig=$5
    local dynamic=$6
    local fixup=$7
    local retcode
    local logfile=/tmp/qemu.setup.$$.log
    local tmprootfs=/tmp/rootfs.$$
    local rel=$(git describe | cut -f1 -d- | cut -f1,2 -d. | sed -e 's/\.//' | sed -e 's/v//')
    local tmp="skip_${rel}"
    local skip=(${!tmp})
    local s
    local build=${ARCH}:${defconfig}

    for s in ${skip[*]}
    do
        if [ "$s" = "${build}" ]
	then
	    echo "skipped"
	    return 2
	fi
    done

    doclean ${ARCH}

    defconfig=$(setup_config ${ARCH} ${defconfig} ${fixup})

    make ARCH=${ARCH} CROSS_COMPILE=${PREFIX} ${defconfig} >/dev/null 2>&1
    if [ $? -ne 0 ]
    then
	echo "failed (config)"
	return 1
    fi

    setup_rootfs "${rootfs}" "${dynamic}"

    make -j12 ARCH=${ARCH} CROSS_COMPILE=${PREFIX} ${EXTRAS} >${logfile} 2>&1
    retcode=$?
    if [ ${retcode} -ne 0 ]
    then
	echo "failed"
	echo "------------"
	echo "Build log:"
	cat ${logfile}
	echo "------------"
    fi

    rm -f ${logfile}

    return ${retcode}
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

	egrep "^BUG:|Kernel panic" ${logfile} >/dev/null 2>&1
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
    grep "\[ cut here \]" ${logfile} >/dev/null 2>&1
    if [ $? -eq 0 ]
    then
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
