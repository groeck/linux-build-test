progdir="$(dirname "$0")"
cd "${progdir}/../master" || exit 1
workers="$(python3 -c "from config import workers; print(' '.join(workers))")"

cmd="/opt/buildbot/bin/cleanup-worker.sh"

for worker in ${workers}
do
    echo "Cleaning up ${worker}"
    rsh ${worker} "${cmd}"
done
