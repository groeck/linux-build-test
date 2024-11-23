workers="server jupiter mars saturn desktop"
cmd="/opt/buildbot/bin/start-worker.sh"

for worker in ${workers}
do
    echo "restarting ${worker}"
    rsh ${worker} "${cmd}"
done
