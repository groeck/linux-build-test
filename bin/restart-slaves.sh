slaves="server jupiter mars saturn desktop"
cmd="/opt/buildbot/bin/start-slave.sh"

for slave in ${slaves}
do
    echo "restarting ${slave}"
    rsh ${slave} "${cmd}"
done
