#!/bin/sh

cd /

echo "Boot successful."

grep "doreboot" /proc/cmdline >/dev/null 2>&1
if [ $? -eq 0 ]
then
	echo "Rebooting."
	reboot
	sleep 2
fi

exec /bin/sh
