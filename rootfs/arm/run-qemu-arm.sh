#!/bin/bash

PREFIX=arm-poky-linux-gnueabi-
ARCH=arm
rootfs=core-image-minimal-qemuarm.ext3
defconfig=qemu_arm_versatile_defconfig
# PATH_ARM=/opt/poky/1.3/sysroots/x86_64-pokysdk-linux/usr/bin/armv5te-poky-linux-gnueabi
PATH_ARM=/opt/poky/1.4.2/sysroots/x86_64-pokysdk-linux/usr/bin/armv7a-vfp-neon-poky-linux-gnueabi

logfile=/tmp/qemu.$$.log
maxtime=120
looptime=5

tmprootfs=/tmp/$$.${rootfs}

PATH=${PATH_ARM}:${PATH}

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

    cp ${dir}/${defconfig} arch/${ARCH}/configs
    make ARCH=${ARCH} CROSS_COMPILE=${PREFIX} ${defconfig} >/dev/null
    if [ $? -ne 0 ]
    then
	echo "failed (config) - aborting"
	exit 1
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

    if [ "${defconfig}" = "qemu_arm_versatile_defconfig" ]
    then
      /opt/buildbot/bin/qemu-system-arm -kernel arch/arm/boot/zImage \
	-M versatilepb -drive file=${tmprootfs},if=scsi -no-reboot \
	-m 128 \
	--append "root=/dev/sda rw mem=128M console=ttyAMA0,115200 console=tty doreboot" \
	-nographic > ${logfile} 2>&1 & 
      pid=$!
    else
      /opt/buildbot/bin/qemu-system-arm -M vexpress-a9 \
	-kernel arch/arm/boot/zImage \
	-drive file=${tmprootfs},if=sd \
	-append "root=/dev/mmcblk0 rw console=ttyAMA0,115200 console=tty1 doreboot" \
	-no-reboot -nographic > ${logfile} 2>&1 &
      pid=$!
    fi

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

    grep "Restarting" ${logfile} >/dev/null 2>&1
    if [ ${retcode} -eq 0 -a $? -ne 0 ]
    then
	echo "No 'Restarting' message in log. Test failed."
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

runkernel qemu_arm_versatile_defconfig
retcode=$?
runkernel qemu_arm_vexpress_defconfig
retcode=$((${retcode} + $?))

rm -f ${logfile} ${tmprootfs}
exit ${retcode}
