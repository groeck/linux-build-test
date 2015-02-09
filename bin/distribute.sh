#!/bin/bash

sys=$(uname -n | cut -f1 -d.)
if [ "${sys}" != "server" ]
then
	echo "$0: must run on server"
	exit 1
fi

base=/opt/buildbot

for system in saturn.roeck-us.net desktop jupiter mars hyperion titan
do
	echo -n "${system}: "
	ping -c 1 -w 1 ${system} >/dev/null
	if [ $? -ne 0 ]
	then
		echo "not responding"
		continue
	fi
	rsync --delete --timeout=15 -r ${base}/bin ${base}/rootfs ${base}/share \
		${base}/lib ${base}/include ${base}/kconfig ${system}:${base}
	if [ $? -ne 0 ]
	then
		echo "failed"
	else
		echo "done"
	fi
done
