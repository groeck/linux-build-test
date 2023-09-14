slaves="server jupiter mars saturn desktop"
cmd="/opt/buildbot/bin/cleanup-slave.sh"

for slave in ${slaves}
do
    echo "Cleaning up ${slave}"
    rsh ${slave} "${cmd}"
done
