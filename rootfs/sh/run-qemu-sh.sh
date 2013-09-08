#!/bin/bash

PREFIX=sh4-linux-
ARCH=sh
rootfs=rootfs.ext2
defconfig=qemu_sh_defconfig
PATH_SH=/opt/kernel/gcc-4.6.3-nolibc/sh4-linux/bin

logfile=/tmp/qemu.$$.log
maxtime=120
looptime=5

tmprootfs=/tmp/$$.${rootfs}

PATH=${PATH_SH}:${PATH}

dir=$(cd $(dirname $0); pwd)

cp ${dir}/${defconfig} arch/${ARCH}/configs
make ARCH=${ARCH} CROSS_COMPILE=${PREFIX} ${defconfig}
if [ $? -ne 0 ]
then
    echo "failed (config) - aborting"
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

/usr/local/bin/qemu-system-sh4 -M r2d -kernel ./arch/sh/boot/zImage \
	-drive file=${tmprootfs},if=ide \
	-append "root=/dev/sda console=ttySC1,115200 noiotrap doreboot" \
	-serial null -serial stdio -net nic,model=rtl8139 -net user \
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

grep "Poweroff" ${logfile} >/dev/null 2>&1
if [ ${retcode} -eq 0 -a $? -ne 0 ]
then
	echo "No 'Poweroff' message in log. Test failed."
	retcode=1
fi

grep "Power down" ${logfile} >/dev/null 2>&1
if [ ${retcode} -eq 0 -a $? -ne 0 ]
then
	echo "No 'Power down' message in log. Test failed."
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
