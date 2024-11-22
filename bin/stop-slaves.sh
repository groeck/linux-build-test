rootdir="/opt/buildbot"
slaves="jupiter mars saturn desktop neptune"

cmd="${rootdir}/bin/stop-slave.sh; rm -f ${rootdir}/slave/twistd.pid"

for slave in ${slaves}
do
    echo "stopping ${slave}"
    rsh ${slave} "${cmd}"
done
