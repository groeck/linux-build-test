#!/bin/sh

cd /

echo "Boot successful."

grep "noreboot" /proc/cmdline >/dev/null 2>&1
if [ $? -ne 0 ]
then
	echo "Rebooting."
	reboot
	sleep 2
fi

exec /bin/sh
