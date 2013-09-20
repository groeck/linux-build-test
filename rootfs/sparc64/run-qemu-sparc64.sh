#!/bin/bash

PREFIX=sparc64-linux-
ARCH=sparc64
rootfs=simple-root-filesystem-sparc.ext3
defconfig=qemu_sparc_defconfig
PATH_SPARC=/opt/kernel/gcc-4.6.3-nolibc/sparc64-linux/bin

logfile=/tmp/qemu.$$.log
maxtime=120
looptime=5

PATH=${PATH_SPARC}:${PATH}

dir=$(cd $(dirname $0); pwd)

cp ${dir}/${defconfig} arch/sparc/configs
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

/opt/buildbot/bin/qemu-system-sparc64 \
	-m 512 \
	-drive file=${rootfs},if=virtio \
	-net nic,model=virtio \
	-kernel arch/sparc/boot/image -no-reboot \
	-append "root=/dev/vda init=/sbin/init.sh console=ttyS0 doreboot" \
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
	# This qemu session doesn't stop by itself. We have to help it along.
	grep "Restarting system" ${logfile} >/dev/null 2>&1
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

git clean -d -x -f -q

rm -f ${logfile}
exit ${retcode}
