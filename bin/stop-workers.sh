progdir="$(dirname "$0")"
rootdir="$(cd "${progdir}/.."; pwd)"

workers="$(cd "${rootdir}/master"; python3 -c "from config import workers; print(' '.join(workers))")"
cmd="/opt/buildbot/bin/start-worker.sh"

cmd="${rootdir}/bin/stop-worker.sh; rm -f ${rootdir}/slave/twistd.pid"

for worker in ${workers}
do
    echo "stopping ${worker}"
    rsh ${worker} "${cmd}"
done
