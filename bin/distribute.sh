#!/bin/bash

sys="$(uname -n | cut -f1 -d.)"
if [ "${sys}" != "server" ]; then
	echo "$0: must run on server"
	exit 1
fi

base=/opt/buildbot
kbase=/opt/kernel

progdir="$(dirname "$0")"
cd "${progdir}/../master" || exit 1

workers="$(python3 -c "from config import workers; print(' '.join(workers))")"
for worker in ${workers}; do
	if [[ "${worker}" == "${sys}" ]]; then
		continue
	fi
	echo -n "${worker}: "
	if ! ping -c 1 -w 1 "${worker}" >/dev/null; then
		echo "not responding"
		continue
	fi
	if ! rsync -l --delete --timeout=15 -r ${base}/bin ${base}/rootfs ${base}/share \
		${base}/.git \
		${base}/lib ${base}/include ${base}/kconfig ${base}/qemu-install \
		${worker}:${base}; then
		echo "failed"
	else
		echo "done"
	fi
done

if [ -d /opt/buildbot/virtual/disk ]; then
	echo -n "virtual: "
	if ! rsync -l --delete -r ${base}/bin ${base}/rootfs ${base}/share \
		${base}/lib ${base}/include ${base}/kconfig ${base}/qemu-install \
		/opt/buildbot/virtual/disk/${base}; then
		echo "failed"
	else
		echo "done"
	fi
fi
