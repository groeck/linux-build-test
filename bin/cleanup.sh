# Remove all log files older than 30 days

cd /opt/buildbot/master
rm $(find mmotm-* qemu-* stable-queue-* hwmon-* master-* next-* -type f -ctime +30 | grep -v workdir)
