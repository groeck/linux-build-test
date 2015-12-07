# Remove all log files older than 40 days

cd /opt/buildbot/master
rm $(find mmotm-* qemu-* stable-updates stable-queue-* hwmon* master-* next-* -type f -ctime +40 | grep -v workdir)
