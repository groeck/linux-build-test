# Remove all log files older than 40 days

cd /opt/buildbot/master
rm $(find master-* next-* -type f -ctime +40 | grep -v workdir) 2>/dev/null
rm $(find stable-updates stable-queue-* -type f -ctime +40 | grep -v workdir) 2>/dev/null
rm $(find mmotm-* qemu-* stable-updates stable-queue-* hwmon* master-* next-* -type f -ctime +40 | grep -v workdir)
