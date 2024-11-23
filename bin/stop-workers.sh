rootdir="/opt/buildbot"
workers="jupiter mars saturn desktop neptune"

cmd="${rootdir}/bin/stop-worker.sh; rm -f ${rootdir}/slave/twistd.pid"

for worker in ${workers}
do
    echo "stopping ${worker}"
    rsh ${worker} "${cmd}"
done
