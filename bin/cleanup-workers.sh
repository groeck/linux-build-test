workers="server jupiter mars saturn desktop neptune"
cmd="/opt/buildbot/bin/cleanup-worker.sh"

for worker in ${workers}
do
    echo "Cleaning up ${worker}"
    rsh ${worker} "${cmd}"
done
