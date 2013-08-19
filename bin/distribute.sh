#!/bin/bash

base=/opt/buildbot

for system in saturn desktop jupiter
do
	echo ${system}:${base}/bin
	rsync -r ${base}/bin ${system}:${base}/bin
	if [ $? -ne 0 ]
	then
		echo "${system}: rsync failed"
		continue
	fi

	echo ${system}:${base}/rootfs
	rsync -r ${base}/rootfs ${system}:${base}/rootfs
	if [ $? -ne 0 ]
	then
		echo "${system}: rsync failed"
	fi
done
