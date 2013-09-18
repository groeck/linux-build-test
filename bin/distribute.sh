#!/bin/bash

sys=$(uname -n | cut -f1 -d.)
if [ "${sys}" != "server" ]
then
	echo "$0: must run on server"
	exit 1
fi

base=/opt/buildbot

for system in saturn.roeck-us.net desktop jupiter hyperion titan
do
	echo -n "${system}: "
	rsync --timeout=15 -r ${base}/bin ${base}/rootfs ${system}:${base}
	if [ $? -ne 0 ]
	then
		echo "failed"
	else
		echo "done"
	fi
done
