#!/bin/bash

PREFIX=microblaze-linux-
ARCH=microblaze
rootfs=rootfs.cpio
defconfig=qemu_microblaze_defconfig
PATH_MICROBLAZE=/opt/kernel/gcc-4.8.0-nolibc/microblaze-linux/bin

logfile=/tmp/qemu.$$.log
maxtime=120
looptime=5

PATH=${PATH_MICROBLAZE}:${PATH}

dir=$(cd $(dirname $0); pwd)

cp ${dir}/${defconfig} arch/${ARCH}/configs
make ARCH=${ARCH} CROSS_COMPILE=${PREFIX} ${defconfig}
if [ $? -ne 0 ]
then
    echo "failed (config) - aborting"
    exit 1
fi

cp ${dir}/${rootfs} .

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

/usr/local/bin/qemu-system-microblaze -M petalogix-s3adsp1800 -kernel arch/microblaze/boot/linux.bin -no-reboot -append "console=ttyUL0,115200 doreboot" -nographic > ${logfile} 2>&1 &

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
	# This qemu session doesn't stop by itself. We have to help it along.
	grep "Machine restart" ${logfile} >/dev/null 2>&1
	if [ $? -eq 0 ]
	then
		kill ${pid} >/dev/null 2>&1
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

grep "Machine restart" ${logfile} >/dev/null 2>&1
if [ ${retcode} -eq 0 -a $? -ne 0 ]
then
	echo "No 'Machine restart' message in log. Test failed."
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

rm -f ${logfile}
exit ${retcode}
