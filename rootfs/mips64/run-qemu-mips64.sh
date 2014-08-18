#!/bin/bash

# machine specific information
rootfs=core-image-minimal-qemumips64.ext3
PATH_MIPS=/opt/kernel/gcc-4.6.3-nolibc/mips64-linux/bin
PREFIX=mips64-linux-
ARCH=mips
QEMUCMD=/opt/buildbot/bin/qemu-system-mips64
KERNEL_IMAGE=vmlinux
QEMU_MACH=malta

# global constants
maxtime=120
looptime=5

PATH=${PATH_MIPS}:${PATH}
logfile=/tmp/qemu.$$.log
dir=$(cd $(dirname $0); pwd)
tmprootfs=/tmp/$$.${rootfs}

doclean()
{
	pwd | grep buildbot >/dev/null 2>&1
	if [ $? -eq 0 ]
	then
		git clean -x -d -f -q
	else
		make ARCH=${ARCH} mrproper >/dev/null 2>&1
	fi
}

runkernel()
{
    local defconfig=$1
    local pid
    local retcode
    local t

    doclean

    cp ${dir}/${defconfig} arch/${ARCH}/configs
    make ARCH=${ARCH} CROSS_COMPILE=${PREFIX} ${defconfig} >/dev/null
    if [ $? -ne 0 ]
    then
	echo "Failed to configure kernel - aborting"
	return 1
    fi

    echo "Build reference: $(git describe)"
    echo "Configuration file: ${defconfig}"
    echo "Building kernel ..."
    make -j12 ARCH=${ARCH} CROSS_COMPILE=${PREFIX} >${logfile} 2>&1
    if [ $? -ne 0 ]
    then
	echo "Build failed - aborting"
	echo "------------"
	echo "Build log:"
	cat ${logfile}
	echo "------------"
	rm -f ${logfile}
	return 1
    fi

    echo -n "Running qemu ..."

    rm -f ${logfile}
    cp ${dir}/${rootfs} ${tmprootfs}

    ${QEMUCMD} -kernel ${KERNEL_IMAGE} -M ${QEMU_MACH} -hda ${tmprootfs} \
	-vga cirrus -usb -usbdevice wacom-tablet -no-reboot -m 128 \
	--append "root=/dev/hda rw mem=128M console=ttyS0 console=tty doreboot" \
	-nographic > ${logfile} 2>&1 &

    pid=$!

    retcode=0
    t=0
    while true
    do
	kill -0 ${pid} >/dev/null 2>&1
	if [ $? -ne 0 ]
	then
		break
	fi
	if [ $t -gt ${maxtime} ]
	then
		echo " timeout - aborting"
		kill ${pid} >/dev/null 2>&1
		# give it some time to die, then kill it
		# the hard way hard if it did not work.
		sleep 5
		kill -0 ${pid} >/dev/null 2>&1
		if [ $? -eq 0 ]
		then
			kill -9 ${pid} >/dev/null 2>&1
		fi
		retcode=1
		break
	fi
	sleep ${looptime}
	t=$(($t + ${looptime}))
	echo -n .
    done

    echo
    grep "Boot successful" ${logfile} >/dev/null 2>&1
    if [ ${retcode} -eq 0 -a $? -ne 0 ]
    then
	echo "No 'Boot successful' message in log. Test failed."
	retcode=1
    fi

    grep "Rebooting" ${logfile} >/dev/null 2>&1
    if [ ${retcode} -eq 0 -a $? -ne 0 ]
    then
	echo "No 'Rebooting' message in log. Test failed."
	retcode=1
    fi

    # grep "Restarting" ${logfile} >/dev/null 2>&1
    # if [ ${retcode} -eq 0 -a $? -ne 0 ]
    # then
    # 	echo "No 'Restarting' message in log. Test failed."
    # 	retcode=1
    # fi

    dolog=0
    grep "\[ cut here \]" ${logfile} >/dev/null 2>&1
    if [ $? -eq 0 ]
    then
	dolog=1
    fi

    if [ ${retcode} -ne 0 -o ${dolog} -ne 0 ]
    then
	echo "------------"
	echo "qemu log:"
	cat ${logfile}
	echo "------------"
    else
	echo "Test successful"
    fi

    return ${retcode}
}

runkernel qemu_mips_malta64_defconfig
retcode=$?
runkernel qemu_mips_malta64_smp_defconfig
retcode=$((${retcode} + $?))

rm -f ${logfile} ${tmprootfs}
exit ${retcode}
