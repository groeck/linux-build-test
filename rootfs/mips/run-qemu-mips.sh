#!/bin/bash

# machine specific information
rootfs=core-image-minimal-qemumips.ext3
defconfig=qemu_mips_malta_defconfig
PATH_MIPS=/opt/poky/1.3/sysroots/x86_64-pokysdk-linux/usr/bin/mips32-poky-linux
PATH_X86=/opt/poky/1.4.0-1/sysroots/x86_64-pokysdk-linux/usr/bin
PREFIX=mips-poky-linux-
ARCH=mips
QEMUCMD=qemu-system-mips
KERNEL_IMAGE=vmlinux
#KERNEL_IMAGE=/opt/buildbot/rootfs/mips/vmlinux-qemumips.bin
QEMU_MACH=malta

# global constants
maxtime=120
looptime=5

PATH=${PATH_MIPS}:${PATH_X86}:${PATH}
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

# ${QEMUCMD} -kernel ${KERNEL_IMAGE} -M ${QEMU_MACH} -hda ${tmprootfs} -vga cirrus -usb -usbdevice wacom-tablet -no-reboot -m 128 --append "root=/dev/hda rw mem=128M console=ttyS0 console=tty" -nographic
${QEMUCMD} -kernel ${KERNEL_IMAGE} -M ${QEMU_MACH} -hda ${tmprootfs} -vga cirrus -usb -usbdevice wacom-tablet -no-reboot -m 128 --append "root=/dev/hda rw mem=128M console=ttyS0 console=tty doreboot" -nographic > ${logfile} 2>&1 &

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

if [ ${retcode} -ne 0 ]
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
