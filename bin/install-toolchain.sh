#!/bin/bash

if [[ -z "$1" ]] || [[ ! -e "$1" ]]; then
    echo "Need valid toolchain as parameter"
    exit 1
fi

doit()
{
	echo scp "$2" "$1":
	scp "$2" "$1:/tmp"
	if [ $? -ne 0 ]; then
		echo "Warning: scp to $1 failed!"
		# exit 1
	fi
	ssh -t $1 /opt/buildbot/bin/install-gcc.sh "$(basename $2)"
}

sys="$(uname -n | cut -f1 -d.)"
progdir="$(dirname "$0")"

workers="$(cd "${progdir}/../master"; python3 -c "from config import workers; print(' '.join(workers))")"
for worker in ${workers}; do
    doit ${worker} $1
done
