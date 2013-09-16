#!/bin/bash

# machine specific information
rootfs=core-image-minimal-qemux86.ext3
defconfig=qemu_x86_pc_defconfig
PATH_X86=/opt/poky/1.3/sysroots/x86_64-pokysdk-linux/usr/bin/x86_64-poky-linux
PREFIX=x86_64-poky-linux-
ARCH=x86
QEMUCMD=/opt/buildbot/bin/qemu-system-i386
KERNEL_IMAGE=arch/x86/boot/bzImage

# global constants
maxtime=120
looptime=5

PATH=${PATH_X86}:${PATH}
logfile=/tmp/qemu.$$.log
dir=$(cd $(dirname $0); pwd)
tmprootfs=/tmp/$$.${rootfs}

cp ${dir}/${defconfig} arch/${ARCH}/configs
make ARCH=${ARCH} CROSS_COMPILE=${PREFIX} ${defconfig}
if [ $? -ne 0 ]
then
	echo "Failed to configure kernel - aborting"
	exit 1
fi

echo "Build reference: $(git describe)"
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
	exit 1
fi

echo -n "Running qemu ..."

rm -f ${logfile}
cp ${dir}/${rootfs} ${tmprootfs}

${QEMUCMD} -kernel ${KERNEL_IMAGE} -hda ${tmprootfs} -usb -usbdevice wacom-tablet -no-reboot -m 128 --append "root=/dev/hda rw mem=128M vga=0 uvesafb.mode_option=640x480-32 oprofile.timer=1 console=ttyS0 console=tty doreboot" -nographic > ${logfile} 2>&1 &

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

git clean -d -x -f -q

rm -f ${logfile} ${tmprootfs}
exit ${retcode}
