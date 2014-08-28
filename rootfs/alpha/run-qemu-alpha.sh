#!/bin/bash

PREFIX=alpha-linux-
ARCH=alpha
rootfs=busybox-alpha.cpio
PATH_ALPHA=/opt/kernel/alpha/gcc-4.8.3/usr/bin

logfile=/tmp/qemu.$$.log
maxtime=120
looptime=5

PATH=${PATH_ALPHA}:${PATH}

dir=$(cd $(dirname $0); pwd)

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

    mkdir -p arch/${ARCH}/configs
    cp ${dir}/${defconfig} arch/${ARCH}/configs
    make ARCH=${ARCH} CROSS_COMPILE=${PREFIX} ${defconfig} >/dev/null
    if [ $? -ne 0 ]
    then
        echo "failed (config) - aborting"
        return 1
    fi

    cp ${dir}/${rootfs} .

    echo "Build reference: $(git describe)"
    echo "Configuration file: ${defconfig}"
    echo "Building kernel ..."
    make -j12 ARCH=${ARCH} KALLSYMS_EXTRA_PASS=1 CROSS_COMPILE=${PREFIX} >${logfile} 2>&1
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

    /opt/buildbot/bin/qemu-system-alpha -M clipper \
	-kernel arch/alpha/boot/vmlinux -no-reboot \
	-initrd ${rootfs} \
	-append 'rdinit=/sbin/init console=ttyS0 console=tty doreboot' \
	-m 128M -nographic -monitor null -serial stdio \
	> ${logfile} 2>&1 &

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

    grep "Restarting system" ${logfile} >/dev/null 2>&1
    if [ ${retcode} -eq 0 -a $? -ne 0 ]
    then
	echo "No 'Restarting system' message in log. Test failed."
	retcode=1
    fi

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

runkernel qemu_alpha_defconfig
retcode=$?

rm -f ${logfile}
exit ${retcode}
